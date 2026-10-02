from __future__ import annotations
import struct
from dataclasses import dataclass
from pathlib import Path

AUTO_ENCODING = "auto"
HEADER_SIZE = 8
GROUP_RECORD_SIZE = 8
POINTER_SIZE = 4
ENTRY_PREVIEW_LIMIT = 60
FIELD_PREVIEW_LIMIT = 160

class StringTableFormatError(ValueError):
    pass

@dataclass(slots=True)
class StringTableDocument:
    groups: list[list[str | None]]
    table_offset: int = HEADER_SIZE
    tail_padding: bytes = b""
    encoding: str = "utf-8"
    file_path: str | None = None

    @property
    def entry_count(self):
        return len(self.groups)

    @property
    def string_count(self):
        return sum(len(group) for group in self.groups)

    def entry_label(self, entry_index):
        preview = next((value for value in self.groups[entry_index] if value), "")
        return f"{entry_index:04d} {preview_text(preview, ENTRY_PREVIEW_LIMIT)}"

    def field_label(self, entry_index, string_index):
        value = self.groups[entry_index][string_index]
        preview = "(null)" if value is None else preview_text(value, FIELD_PREVIEW_LIMIT)
        return f"{string_index:03d} {preview}"

    def field_labels_for_entry(self, entry_index):
        return [
            self.field_label(entry_index, string_index)
            for string_index in range(len(self.groups[entry_index]))
        ]

    def get_value(self, entry_index, string_index):
        return self.groups[entry_index][string_index]

    def set_value(self, entry_index, string_index, value):
        group = self.groups[entry_index]
        if value is None or (group[string_index] is None and value == ""):
            group[string_index] = None
            return

        group[string_index] = str(value)

    def to_bytes(self, encoding=None):
        return build_string_tbl_bytes(self, encoding=encoding or self.encoding)

    def save(self, path=None, encoding=None):
        target = path or self.file_path
        if not target:
            raise ValueError("No output path was provided.")

        Path(target).write_bytes(self.to_bytes(encoding=encoding))
        self.file_path = str(target)
        if encoding:
            self.encoding = encoding

def load_string_tbl(file_path, encoding=AUTO_ENCODING):
    data = Path(file_path).read_bytes()
    return parse_string_tbl_bytes(data, encoding=encoding, file_path=str(file_path))

def parse_string_tbl_bytes(data, encoding=AUTO_ENCODING, file_path=None):
    if encoding == AUTO_ENCODING:
        last_error = None
        for candidate in ("utf-8", "cp932", "shift_jis"):
            try:
                return parse_string_tbl_bytes(data, encoding=candidate, file_path=file_path)
            except UnicodeDecodeError as exc:
                last_error = exc

        raise StringTableFormatError(
            "Failed to decode string table with UTF-8, CP932, or Shift-JIS."
        ) from last_error

    if len(data) < HEADER_SIZE:
        raise StringTableFormatError("String table is too small to contain a header.")

    group_count, table_offset = struct.unpack_from(">II", data, 0)
    table_end = table_offset + group_count * GROUP_RECORD_SIZE
    if table_offset < HEADER_SIZE or table_end > len(data):
        raise StringTableFormatError("Group table doesnt fit inside the file.")

    groups = []
    content_end = table_end

    for group_index in range(group_count):
        string_count, pointer_offset = struct.unpack_from(
            ">II", data, table_offset + group_index * GROUP_RECORD_SIZE
        )
        pointer_end = pointer_offset + string_count * POINTER_SIZE
        if string_count and (pointer_offset < table_end or pointer_end > len(data)):
            raise StringTableFormatError(
                f"Group {group_index:04d} points outside the file."
            )
        content_end = max(content_end, pointer_end)

        group = []
        for string_index in range(string_count):
            string_offset = struct.unpack_from(
                ">I", data, pointer_offset + string_index * POINTER_SIZE
            )[0]
            if string_offset == 0:
                group.append(None)
                continue

            if string_offset < table_end or string_offset >= len(data):
                raise StringTableFormatError(
                    f"Group {group_index:04d} string {string_index:03d} points outside the file."
                )

            string_end = data.find(b"\x00", string_offset)
            if string_end == -1:
                raise StringTableFormatError(
                    f"Group {group_index:04d} string {string_index:03d} is unterminated."
                )

            group.append(data[string_offset:string_end].decode(encoding))
            content_end = max(content_end, string_end + 1)

        groups.append(group)

    return StringTableDocument(
        groups=groups,
        table_offset=table_offset,
        tail_padding=data[content_end:],
        encoding=encoding,
        file_path=file_path,
    )

def build_string_tbl_bytes(document, encoding=None):
    selected_encoding = encoding or document.encoding
    group_count = len(document.groups)
    table_end = document.table_offset + group_count * GROUP_RECORD_SIZE
    strings_start = table_end + document.string_count * POINTER_SIZE

    output = bytearray(strings_start)
    struct.pack_into(">II", output, 0, group_count, document.table_offset)

    pointer_offset = table_end
    for group_index, group in enumerate(document.groups):
        struct.pack_into(
            ">II",
            output,
            document.table_offset + group_index * GROUP_RECORD_SIZE,
            len(group),
            pointer_offset,
        )

        for value in group:
            if value is not None:
                struct.pack_into(">I", output, pointer_offset, len(output))
                output.extend(value.encode(selected_encoding))
                output.append(0)
            pointer_offset += POINTER_SIZE

    output.extend(document.tail_padding)
    return bytes(output)

def format_string_tbl_value_for_editor(value):
    return "" if value is None else value

def preview_text(value, limit=40):
    flattened = " ".join(value.split())
    return flattened if len(flattened) <= limit else flattened[: limit - 3] + "..."
