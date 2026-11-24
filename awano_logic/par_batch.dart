import 'dart:async'; import 'dart:collection'; import 'dart:io'; import 'dart:isolate';
import 'par.dart';

const parMaxWorkers = 4;

String normalizePathKey(String path) {
  final absolute = File(path).absolute.path.replaceAll('/', '\\');
  final parts = <String>[];
  for (final part in absolute.split('\\')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.length > 1) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('\\').toLowerCase();
}

String baseName(String path) {
  final cleaned = path.replaceAll('/', '\\');
  final trimmed = cleaned.endsWith('\\') ? cleaned.substring(0, cleaned.length - 1) : cleaned;
  return trimmed.substring(trimmed.lastIndexOf('\\') + 1);
}

String parentPath(String path) {
  final cleaned = path.replaceAll('/', '\\');
  final cut = cleaned.lastIndexOf('\\');
  return cut <= 0 ? cleaned : cleaned.substring(0, cut);
}

String sanitizeOutputName(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  final isPar = dot > 0 && name.substring(dot).toLowerCase() == '.par';
  final candidate = isPar ? name.substring(0, dot) : '${name}_unpack';
  var safe = candidate.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  safe = safe.replaceAll(RegExp(r'[. ]+$'), '').trim();
  return safe.isEmpty ? '${name}_unpack' : safe;
}

String defaultOutputDir(String source) => '${parentPath(source)}\\${sanitizeOutputName(source)}';

bool hasParExtension(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  return dot > 0 && name.substring(dot).toLowerCase() == '.par';
}

int comparePaths(String a, String b) {
  final pa = a.toLowerCase().split('\\');
  final pb = b.toLowerCase().split('\\');
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

List<String> listParFiles(String root, {bool skipUnpackFolders = false}) {
  final found = <String>[];
  for (final entity in Directory(root).listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !hasParExtension(entity.path)) continue;
    final absolute = entity.absolute.path;
    if (skipUnpackFolders && absolute.split('\\').any((part) => part.endsWith('_unpack'))) continue;
    found.add(absolute);
  }
  found.sort(comparePaths);
  return found;
}

List<String> scanParArchives(String root) {
  if (!Directory(root).existsSync()) throw FileSystemException('Folder doesnt exist: $root');
  return listParFiles(root, skipUnpackFolders: true);
}

String buildTopLevelOutputDir(String source, String root, String outputRoot) {
  final rootPath = Directory(root).absolute.path.replaceAll('/', '\\');
  final parent = parentPath(source);
  var relative = parent.length > rootPath.length ? parent.substring(rootPath.length) : '';
  while (relative.startsWith('\\')) {
    relative = relative.substring(1);
  }
  final base = relative.isEmpty ? outputRoot : '$outputRoot\\$relative';
  return '$base\\${sanitizeOutputName(source)}';
}

void parWorkerMain(SendPort coordinator) {
  final inbox = ReceivePort();
  coordinator.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is! List) {
      inbox.close();
      return;
    }
    final id = message[0] as int;
    final source = message[1] as String;
    final output = message[2] as String;
    try {
      Directory(parentPath(output)).createSync(recursive: true);
      final result = unpackPar(source, output);
      coordinator.send({
        'id': id,
        'extracted_files': result.extractedFiles,
        'decompressed_files': result.decompressedFiles,
        'nested_containers': result.nestedContainers,
      });
    } catch (error) {
      coordinator.send({'id': id, 'error': error.toString()});
    }
  });
}

class ParJob {
  final String source, output;
  final int depth;
  ParJob(this.source, this.output, this.depth);
}

Future<void> parBatchEntry(List<Object?> args) async {
  final updates = args[0] as SendPort;
  final rootDir = args[1] as String;
  final outputRoot = args[2] as String;
  final workerCount = (args[3] as int) < 1 ? 1 : args[3] as int;
  final control = ReceivePort();
  updates.send({'type': 'control', 'port': control.sendPort});
  final done = Completer<void>();
  var cancelled = false;
  final workers = <Isolate>[];

  void send(Map<String, Object?> event) => updates.send(event);

  late final List<String> discovered;
  try {
    discovered = scanParArchives(rootDir);
  } catch (error) {
    send({'type': 'error', 'message': error.toString()});
    send({'type': 'finished'});
    control.close();
    return;
  }

  if (discovered.isEmpty) {
    send({
      'type': 'state',
      'status': 'No PAR archives found in the selected folder.',
      'progress': 0.0,
      'total_jobs': 0,
      'completed_jobs': 0,
      'active_jobs': 0,
      'queued_jobs': 0,
      'error_count': 0,
      'running': false,
    });
    send({'type': 'finished'});
    control.close();
    return;
  }

  final pending = Queue<ParJob>();
  final scheduled = <String>{};
  for (final source in discovered) {
    scheduled.add(normalizePathKey(source));
    pending.add(ParJob(source, buildTopLevelOutputDir(source, rootDir, outputRoot), 0));
  }
  final topLevelJobs = pending.length;
  var totalJobs = topLevelJobs;
  var completedJobs = 0;
  var errorCount = 0;
  var displayProgress = 0.0;
  final active = <int, ParJob>{};
  final idle = <SendPort>[];
  final busy = <int, SendPort>{};
  var nextId = 0;

  Map<String, Object?> state(String status, bool running) => {
        'type': 'state',
        'status': status,
        'progress': displayProgress,
        'output_root': outputRoot,
        'top_level_jobs': topLevelJobs,
        'total_jobs': totalJobs,
        'completed_jobs': completedJobs,
        'active_jobs': active.length,
        'queued_jobs': pending.length,
        'nested_jobs': totalJobs - topLevelJobs < 0 ? 0 : totalJobs - topLevelJobs,
        'error_count': errorCount,
        'running': running,
      };

  final clock = Stopwatch()..start();
  var lastStateAt = -1000;

  void sendState(String status, bool running, {bool force = false}) {
    final now = clock.elapsedMilliseconds;
    if (!force && now - lastStateAt < 80) return;
    lastStateAt = now;
    send(state(status, running));
  }

  String currentStatus() => 'Unpacking PAR archives';

  String summary() {
    final nested = totalJobs - topLevelJobs;
    final unpacked = completedJobs - errorCount;
    final seconds = (clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return '$unpacked ${unpacked == 1 ? 'PAR' : 'PARs'} unpacked, $nested nested, $seconds s, '
        '$errorCount ${errorCount == 1 ? 'error' : 'errors'}';
  }

  send({
    'type': 'log',
    'message': 'Found $topLevelJobs top-level PAR archives under $rootDir. Output root: $outputRoot. '
        'Nested PARs will be queued as they are discovered.',
  });
  sendState('Scanning complete. Starting PAR workers', true, force: true);

  void finish() {
    if (done.isCompleted) return;
    for (final isolate in workers) {
      isolate.kill(priority: Isolate.immediate);
    }
    done.complete();
  }

  void dispatch() {
    while (!cancelled && pending.isNotEmpty && idle.isNotEmpty) {
      final job = pending.removeFirst();
      final port = idle.removeLast();
      final id = nextId++;
      active[id] = job;
      busy[id] = port;
      port.send([id, job.source, job.output]);
      sendState(currentStatus(), true);
    }
    if (!cancelled && pending.isEmpty && active.isEmpty) {
      send({'type': 'log', 'message': 'Finished, ${summary()}.'});
      send({'type': 'summary', 'message': summary()});
      finish();
    }
  }

  void handleResult(Map message) {
    final id = message['id'] as int;
    final job = active.remove(id);
    final port = busy.remove(id);
    if (job == null || port == null) return;
    completedJobs++;
    final completion = completedJobs / (totalJobs < 1 ? 1 : totalJobs);
    final error = message['error'];
    if (error != null) {
      errorCount++;
      send({'type': 'log', 'message': 'Failed to unpack ${job.source}: $error'});
    } else {
      for (final path in (message['nested_containers'] as List).cast<String>()) {
        if (!scheduled.add(normalizePathKey(path))) continue;
        pending.add(ParJob(path, defaultOutputDir(path), job.depth + 1));
        totalJobs++;
      }
    }
    if (completion > displayProgress) displayProgress = completion;
    final stillRunning = pending.isNotEmpty || active.isNotEmpty;
    if (stillRunning) {
      sendState(currentStatus(), true);
    } else {
      sendState('PAR batch unpack completed.', false, force: true);
    }
    idle.add(port);
    dispatch();
  }

  final inbox = ReceivePort();
  inbox.listen((message) {
    if (message is SendPort) {
      idle.add(message);
      dispatch();
    } else if (message is Map) {
      handleResult(message);
    }
  });

  control.listen((message) {
    if (message == 'cancel' && !cancelled) {
      cancelled = true;
      active.clear();
      send({'type': 'log', 'message': 'Cancelled, ${summary()}.'});
      send({'type': 'summary', 'message': 'Cancelled, ${summary()}'});
      sendState('PAR batch cancelled.', false, force: true);
      finish();
    }
  });

  for (var i = 0; i < workerCount; i++) {
    workers.add(await Isolate.spawn(parWorkerMain, inbox.sendPort, debugName: 'par-worker-$i'));
  }

  await done.future;
  inbox.close();
  control.close();
  send({'type': 'finished'});
}
