from __future__ import annotations

import json, os, shutil, subprocess, time
from collections import deque
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path

PAR_MAX_WORKERS = 4
PAR_EXTENSIONS = {".par"}


def run_par_batch_unpack(root_dir, update_queue, cancel_event, worker_count=PAR_MAX_WORKERS):
    root_path = Path(root_dir)

    try:
        worker_command = resolve_par_worker_command()
        output_root = resolve_batch_output_root(root_path)
        discovered_sources = scan_par_archives(root_path)
    except Exception as exc:
        update_queue.put({"type": "error", "message": str(exc)})
        update_queue.put({"type": "finished"})
        return

    if not discovered_sources:
        update_queue.put(
            {
                "type": "state",
                "status": "No PAR archives found in the selected folder.",
                "progress": 0.0,
                "total_jobs": 0,
                "completed_jobs": 0,
                "active_jobs": 0,
                "queued_jobs": 0,
                "error_count": 0,
                "running": False,
            }
        )
        update_queue.put({"type": "finished"})
        return

    pending_jobs = deque()
    scheduled_sources = set()

    for source_path in discovered_sources:
        scheduled_sources.add(normalize_path_key(source_path))
        pending_jobs.append(
            (
                source_path,
                build_top_level_output_dir(source_path, root_path, output_root),
                0,
            )
        )

    top_level_jobs = len(pending_jobs)
    total_jobs = top_level_jobs
    completed_jobs = 0
    error_count = 0
    display_progress = 0.0

    update_queue.put(
        {
            "type": "log",
            "message": (
                f"Found {top_level_jobs} top-level PAR archive(s) under "
                f"{os.fspath(root_path)}. Output root: {os.fspath(output_root)}. "
                "Nested PARs will be queued as they are discovered."
            ),
        }
    )
    update_queue.put(
        {
            "type": "state",
            "status": "Scanning complete. Starting PAR workers...",
            "progress": display_progress,
            "output_root": os.fspath(output_root),
            "top_level_jobs": top_level_jobs,
            "total_jobs": total_jobs,
            "completed_jobs": 0,
            "active_jobs": 0,
            "queued_jobs": len(pending_jobs),
            "nested_jobs": 0,
            "error_count": 0,
            "running": True,
        }
    )

    active_jobs = {}

    with ThreadPoolExecutor(max_workers=max(1, worker_count)) as executor:
        while (pending_jobs or active_jobs) and not cancel_event.is_set():
            while pending_jobs and len(active_jobs) < max(1, worker_count) and not cancel_event.is_set():
                source_path, output_dir, depth = pending_jobs.popleft()
                update_queue.put(
                    {
                        "type": "log",
                        "message": (
                            f"[Job {completed_jobs + len(active_jobs) + 1:03d}] "
                            f"Unpacking {os.fspath(source_path)}"
                        ),
                    }
                )
                future = executor.submit(
                    run_par_worker_job,
                    worker_command,
                    source_path,
                    output_dir,
                    cancel_event,
                )
                active_jobs[future] = (source_path, output_dir, depth)
                update_queue.put(
                    {
                        "type": "state",
                        "status": f"Running {len(active_jobs)} PAR worker(s)...",
                        "progress": display_progress,
                        "output_root": os.fspath(output_root),
                        "top_level_jobs": top_level_jobs,
                        "total_jobs": total_jobs,
                        "completed_jobs": completed_jobs,
                        "active_jobs": len(active_jobs),
                        "queued_jobs": len(pending_jobs),
                        "nested_jobs": max(total_jobs - top_level_jobs, 0),
                        "error_count": error_count,
                        "running": True,
                    }
                )

            if not active_jobs:
                break

            done, _ = wait(active_jobs.keys(), timeout=0.1, return_when=FIRST_COMPLETED)
            if not done:
                continue

            for future in done:
                source_path, output_dir, depth = active_jobs.pop(future)
                completed_jobs += 1
                completion_progress = completed_jobs / max(total_jobs, 1)

                try:
                    result = future.result()
                except Exception as exc:
                    error_count += 1
                    update_queue.put(
                        {
                            "type": "log",
                            "message": (
                                f"Failed to unpack {os.fspath(source_path)}: {exc}"
                            ),
                        }
                    )
                else:
                    extracted_files = int(result.get("extracted_files", 0))
                    nested_paths = collect_nested_sources(
                        result.get("nested_containers", []),
                        output_dir,
                    )
                    decompressed_files = int(result.get("decompressed_files", 0))
                    update_queue.put(
                        {
                            "type": "log",
                            "message": (
                                f"Finished {os.fspath(source_path)} -> {os.fspath(output_dir)} | "
                                f"{extracted_files} file(s), {decompressed_files} decompressed, "
                                f"{len(nested_paths)} nested PAR(s)."
                            ),
                        }
                    )

                    queued_nested = 0
                    queued_samples = []
                    for nested_path_text in nested_paths:
                        nested_path = Path(nested_path_text)
                        nested_key = normalize_path_key(nested_path)
                        if nested_key in scheduled_sources:
                            continue

                        scheduled_sources.add(nested_key)
                        pending_jobs.append(
                            (
                                nested_path,
                                default_output_dir(nested_path),
                                depth + 1,
                            )
                        )
                        total_jobs += 1
                        queued_nested += 1
                        if len(queued_samples) < 5:
                            queued_samples.append(nested_path.name)

                    if queued_nested:
                        sample_suffix = ""
                        if queued_samples:
                            sample_suffix = f" Sample: {', '.join(queued_samples)}"
                            if queued_nested > len(queued_samples):
                                sample_suffix += ", ..."

                        update_queue.put(
                            {
                                "type": "log",
                                "message": (
                                    f"Queued {queued_nested} nested PAR(s) from "
                                    f"{os.fspath(source_path)}.{sample_suffix}"
                                ),
                            }
                        )

                display_progress = max(
                    display_progress,
                    completion_progress,
                )
                update_queue.put(
                    {
                        "type": "state",
                        "status": (
                            "Processing nested PAR archives..."
                            if pending_jobs or active_jobs
                            else "PAR batch unpack completed."
                        ),
                        "progress": display_progress,
                        "output_root": os.fspath(output_root),
                        "top_level_jobs": top_level_jobs,
                        "total_jobs": total_jobs,
                        "completed_jobs": completed_jobs,
                        "active_jobs": len(active_jobs),
                        "queued_jobs": len(pending_jobs),
                        "nested_jobs": max(total_jobs - top_level_jobs, 0),
                        "error_count": error_count,
                        "running": bool(pending_jobs or active_jobs),
                    }
                )

    if cancel_event.is_set():
        update_queue.put({"type": "log", "message": "Cancellation requested. Stopping PAR batch."})
        update_queue.put(
            {
                "type": "state",
                "status": "PAR batch cancelled.",
                "progress": display_progress,
                "output_root": os.fspath(output_root),
                "top_level_jobs": top_level_jobs,
                "total_jobs": total_jobs,
                "completed_jobs": completed_jobs,
                "active_jobs": 0,
                "queued_jobs": len(pending_jobs),
                "nested_jobs": max(total_jobs - top_level_jobs, 0),
                "error_count": error_count,
                "running": False,
            }
        )

    update_queue.put({"type": "finished"})


def resolve_par_worker_command():
    module_dir = Path(__file__).resolve().parent
    exe_path = module_dir / "par.exe"
    dart_path = module_dir / "par.dart"

    if exe_path.exists() and dart_path.exists():
        if exe_path.stat().st_mtime >= dart_path.stat().st_mtime:
            return [os.fspath(exe_path)]

    if exe_path.exists() and not dart_path.exists():
        return [os.fspath(exe_path)]

    if dart_path.exists():
        dart_binary = shutil.which("dart")
        if dart_binary:
            return [dart_binary, os.fspath(dart_path)]

    if exe_path.exists():
        return [os.fspath(exe_path)]

    raise FileNotFoundError(
        "Could not find a PAR worker. Expected Awano_Logic/par.exe or a usable Dart runtime for Awano_Logic/par.dart."
    )


def scan_par_archives(root_dir):
    root_path = Path(root_dir)
    if not root_path.exists():
        raise FileNotFoundError(f"Folder does not exist: {os.fspath(root_path)}")

    return sorted(
        path
        for path in root_path.rglob("*")
        if path.is_file()
        and path.suffix.lower() in PAR_EXTENSIONS
        and not any(part.endswith("_unpack") for part in path.parts)
    )


def default_output_dir(source_path):
    source = Path(source_path)
    return source.with_name(sanitize_output_name(source))


def build_top_level_output_dir(source_path, source_root, output_root):
    source = Path(source_path)
    source_root_path = Path(source_root)
    output_root_path = Path(output_root)
    relative_parent = source.parent.relative_to(source_root_path)
    return output_root_path / relative_parent / sanitize_output_name(source)


def resolve_batch_output_root(root_dir):
    root_path = Path(root_dir)
    workspace_root = Path(__file__).resolve().parent.parent
    par_unpack_root = workspace_root / "PAR_Unpacker"
    return par_unpack_root / f"{root_path.name}_awano_unpack"


def run_par_worker_job(worker_command, source_path, output_dir, cancel_event):
    source = Path(source_path)
    output = Path(output_dir)
    output.parent.mkdir(parents=True, exist_ok=True)

    process = subprocess.Popen(
        worker_command + ["unpack", os.fspath(source), os.fspath(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        **subprocess_window_options(),
    )

    try:
        while True:
            if cancel_event.is_set():
                process.kill()
                process.wait(timeout=5)
                raise RuntimeError("Canceled")

            try:
                stdout, stderr = process.communicate(timeout=0.1)
                break
            except subprocess.TimeoutExpired:
                continue
    finally:
        if process.poll() is None:
            process.kill()

    if process.returncode != 0:
        raise RuntimeError(summarize_worker_failure(source, stdout, stderr))

    worker_output = stdout.strip()
    if not worker_output:
        raise RuntimeError(f"PAR worker returned no metadata for {os.fspath(source)}.")

    try:
        return json.loads(worker_output)
    except json.JSONDecodeError:
        last_line = worker_output.splitlines()[-1]
        try:
            return json.loads(last_line)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"PAR worker returned invalid metadata for {os.fspath(source)}."
            ) from exc


def normalize_path_key(path):
    return os.path.normcase(os.path.abspath(os.fspath(path)))


def collect_nested_sources(worker_nested_paths, output_dir):
    discovered_paths = []
    seen_paths = set()

    for nested_path in resolve_worker_nested_paths(worker_nested_paths, output_dir):
        nested_key = normalize_path_key(nested_path)
        if nested_key in seen_paths:
            continue
        seen_paths.add(nested_key)
        discovered_paths.append(nested_path)

    for nested_path in discover_nested_archives(output_dir):
        nested_key = normalize_path_key(nested_path)
        if nested_key in seen_paths:
            continue
        seen_paths.add(nested_key)
        discovered_paths.append(nested_path)

    return discovered_paths


def resolve_worker_nested_paths(worker_nested_paths, output_dir):
    output_root = Path(output_dir)

    for nested_path_text in worker_nested_paths or []:
        nested_path = Path(nested_path_text)
        if not nested_path.is_absolute():
            nested_path = output_root / nested_path
        yield nested_path


def discover_nested_archives(output_dir):
    output_root = Path(output_dir)
    if not output_root.exists():
        return []

    return sorted(
        path
        for path in output_root.rglob("*")
        if path.is_file()
        and path.suffix.lower() in PAR_EXTENSIONS
    )


def sanitize_output_name(path):
    source = Path(path)
    candidate = source.stem if source.suffix.lower() == ".par" else source.name
    safe = "".join(character if character not in '<>:"/\\|?*' else "_" for character in candidate)
    safe = safe.rstrip(". ").strip()
    return safe or f"{source.name}_unpack"


def subprocess_window_options():
    if os.name != "nt":
        return {}

    return {"creationflags": subprocess.CREATE_NO_WINDOW}


def summarize_worker_failure(source_path, stdout_text, stderr_text):
    detail = stderr_text.strip() or stdout_text.strip() or "Unknown worker error."
    return f"{os.fspath(source_path)} -> {detail.splitlines()[-1]}"
