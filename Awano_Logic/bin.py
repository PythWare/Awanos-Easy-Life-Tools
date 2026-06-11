from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

MAGIC = bytes.fromhex("20070319")
PARAMETER_RECORD_SIZE = 64
PARAMETER_NAME_SIZE = 48
HEADER_BASE_SIZE = 16
AUTO_ENCODING = "auto"

PARAMETER_TYPES = [
    "string",
    "string_tbl",
    "string_idx",
    "value",
    "value_tbl",
    "value_idx",
    "special_scenariocategory",
    "special_scenariostatus",
    "stageid",
    "special_scenariocompare",
    "special_value",
    "itemid",
    "comment",
    "BGM_ID",
    "unknown",
    "USE_COUNTER",
    "ENTITY_UID",
]

TEXT_PARAMETER_TYPES = {
    "string",
    "string_tbl",
    "string_idx",
    "value",
    "value_tbl",
    "value_idx",
    "stageid",
}
TABLE_PARAMETER_TYPES = {"string_tbl", "value_tbl"}
INDEX_PARAMETER_TYPES = {"string_idx", "value_idx"}
HEX_PARAMETER_TYPES = {
    "special_scenariocategory",
    "special_scenariostatus",
    "special_scenariocompare",
    "BGM_ID",
    "ENTITY_UID",
}
INT_PARAMETER_TYPES = {"special_value", "itemid", "USE_COUNTER"}
UNSUPPORTED_PARAMETER_TYPES = {"comment", "unknown"}


class BinFormatError(ValueError):
    pass


@dataclass(slots=True)
class BinParameter:
    name: str
    type_index: int
    count: int
    size: int
    tail_padding: bytes = b"\x00\x00"

    @property
    def type_name(self):
        try:
            return PARAMETER_TYPES[self.type_index]
        except IndexError as exc:
            raise BinFormatError(f"Unknown parameter type index {self.type_index}") from exc


@dataclass(slots=True)
class BinDocument:
    parameters: list[BinParameter]
    entry_count: int
    entries: list[dict[str, object]]
    encoding: str = "utf-8"
    file_path: str | None = None

    @property
    def parameter_names(self):
        return [parameter.name for parameter in self.parameters]

    def get_parameter(self, parameter_name):
        for parameter in self.parameters:
            if parameter.name == parameter_name:
                return parameter
        raise KeyError(parameter_name)

    def get_value(self, entry_index, parameter_name, default=""):
        return self.entries[entry_index].get(parameter_name, default)

    def has_value(self, entry_index, parameter_name):
        return parameter_name in self.entries[entry_index]

    def set_value(self, entry_index, parameter_name, value):
        parameter = self.get_parameter(parameter_name)
        normalized = normalize_parameter_value(parameter.type_name, value)

        if normalized is None:
            self.entries[entry_index].pop(parameter_name, None)
            return

        self.entries[entry_index][parameter_name] = normalized

    def unset_value(self, entry_index, parameter_name):
        self.entries[entry_index].pop(parameter_name, None)

    def append_entry(self, source_entry=None):
        if source_entry is None:
            new_entry = {}
        else:
            new_entry = dict(source_entry)

        self.entries.append(new_entry)
        self.entry_count = len(self.entries)
        return self.entry_count - 1

    def to_bytes(self, encoding=None):
        return build_bin_bytes(self, encoding=encoding or self.encoding)

    def save(self, path=None, encoding=None):
        target = path or self.file_path
        if not target:
            raise ValueError("No output path was provided.")

        output_bytes = self.to_bytes(encoding=encoding)
        Path(target).write_bytes(output_bytes)

        self.file_path = str(target)
        if encoding:
            self.encoding = encoding


def load_bin(file_path, encoding=AUTO_ENCODING):
    data = Path(file_path).read_bytes()
    return parse_bin_bytes(data, encoding=encoding, file_path=str(file_path))


def parse_bin_bytes(data, encoding=AUTO_ENCODING, file_path=None):
    if encoding == AUTO_ENCODING:
        last_error = None
        for candidate in ("utf-8", "cp932", "shift_jis"):
            try:
                return parse_bin_bytes_with_encoding(data, candidate, file_path=file_path)
            except UnicodeDecodeError as exc:
                last_error = exc

        if last_error is not None:
            raise BinFormatError("Failed to decode BIN with UTF-8, CP932, or Shift-JIS.") from last_error

    return parse_bin_bytes_with_encoding(data, encoding, file_path=file_path)


def build_bin_bytes(document, encoding=None):
    selected_encoding = encoding or document.encoding
    parameter_count = len(document.parameters)

    header = bytearray(HEADER_BASE_SIZE + PARAMETER_RECORD_SIZE * parameter_count)
    header[0:4] = MAGIC
    struct.pack_into(">I", header, 4, parameter_count)
    struct.pack_into(">I", header, 8, document.entry_count)

    body_chunks = []

    for parameter_index, parameter in enumerate(document.parameters):
        count, body = encode_parameter_block(document, parameter, selected_encoding)
        name_bytes = parameter.name.encode(selected_encoding)

        if len(name_bytes) > PARAMETER_NAME_SIZE:
            raise BinFormatError(
                f"Parameter name '{parameter.name}' is too long for the BIN header."
            )

        record_start = HEADER_BASE_SIZE + parameter_index * PARAMETER_RECORD_SIZE
        header[record_start : record_start + len(name_bytes)] = name_bytes

        struct.pack_into(">I", header, record_start + 48, parameter.type_index)
        struct.pack_into(">I", header, record_start + 52, count)
        struct.pack_into(">I", header, record_start + 56, len(body))

        body_chunks.append(body)

    return bytes(header) + b"".join(body_chunks)


def format_value_for_editor(parameter_type, value):
    if value is None:
        return ""

    if parameter_type in INT_PARAMETER_TYPES:
        return str(value)

    return str(value)


def normalize_parameter_value(parameter_type, value):
    raw_text = value if isinstance(value, str) else str(value)

    if parameter_type in TEXT_PARAMETER_TYPES:
        return raw_text

    if parameter_type == "special_scenariostatus":
        return normalize_status_text(raw_text)

    if parameter_type in {
        "special_scenariocategory",
        "special_scenariocompare",
        "BGM_ID",
        "ENTITY_UID",
    }:
        return normalize_fixed_hex32(raw_text)

    if parameter_type in INT_PARAMETER_TYPES:
        cleaned = raw_text.strip()
        if not cleaned:
            return None
        return parse_int_text(cleaned)

    if parameter_type in UNSUPPORTED_PARAMETER_TYPES:
        return raw_text

    raise BinFormatError(f"Unsupported parameter type '{parameter_type}'.")


def parse_bin_bytes_with_encoding(data, encoding, file_path=None):
    if len(data) < HEADER_BASE_SIZE:
        raise BinFormatError("BIN file is too small to contain a valid header.")

    if data[0:4] != MAGIC:
        raise BinFormatError("Not a 20070319 BIN file.")

    parameter_amount = struct.unpack_from(">I", data, 4)[0]
    entry_amount = struct.unpack_from(">I", data, 8)[0]
    header_end = HEADER_BASE_SIZE + parameter_amount * PARAMETER_RECORD_SIZE

    parameters = []
    entries = [dict() for _ in range(entry_amount)]
    current_position = 0

    for current_param in range(parameter_amount):
        record_start = HEADER_BASE_SIZE + current_param * PARAMETER_RECORD_SIZE
        raw_name = data[record_start : record_start + PARAMETER_NAME_SIZE]
        parameter_name = raw_name.split(b"\x00", maxsplit=1)[0].decode(encoding)
        parameter_type = struct.unpack_from(">I", data, record_start + 48)[0]
        parameter_count = struct.unpack_from(">I", data, record_start + 52)[0]
        parameter_size = struct.unpack_from(">I", data, record_start + 56)[0]

        parameter = BinParameter(
            name=parameter_name,
            type_index=parameter_type,
            count=parameter_count,
            size=parameter_size,
        )
        parameters.append(parameter)

        if parameter_size == 0:
            continue

        block_start = header_end + current_position
        block_end = block_start + parameter_size
        if block_end > len(data):
            raise BinFormatError(
                f"Parameter '{parameter_name}' extends past the end of the BIN."
            )
        parameter_buffer = data[block_start:block_end]
        decode_parameter_block(entries, parameter, parameter_buffer, entry_amount, encoding)
        parameter.tail_padding = detect_parameter_tail_padding(
            parameter,
            parameter_buffer,
            entry_amount,
            encoding,
        )
        current_position += parameter_size

    return BinDocument(
        parameters=parameters,
        entry_count=entry_amount,
        entries=entries,
        encoding=encoding,
        file_path=file_path,
    )


def decode_parameter_block(entries, parameter, parameter_buffer, entry_amount, encoding):
    parameter_name = parameter.name
    parameter_type = parameter.type_name

    if parameter_type in {"string", "value", "stageid"}:
        strings = parameter_buffer.decode(encoding).split("\x00")
        for entry_index in range(entry_amount):
            if entry_index < len(strings):
                entries[entry_index][parameter_name] = strings[entry_index]
        return

    if parameter_type in TABLE_PARAMETER_TYPES:
        strings_for_table, table_start = read_counted_strings(
            parameter_buffer,
            parameter.count,
            encoding,
        )
        table_bytes = parameter_buffer[table_start : table_start + entry_amount]

        for entry_index in range(entry_amount):
            if entry_index >= len(table_bytes):
                continue

            table_index = table_bytes[entry_index]
            if table_index < len(strings_for_table):
                entries[entry_index][parameter_name] = strings_for_table[table_index]
        return

    if parameter_type in INDEX_PARAMETER_TYPES:
        for entry_index in range(entry_amount):
            entries[entry_index][parameter_name] = ""

        current_byte = 0
        current_word = 0

        while current_word < parameter.count and current_byte + 2 <= len(parameter_buffer):
            entry_id = int.from_bytes(parameter_buffer[current_byte : current_byte + 2], "big")
            current_byte += 2

            word_end_byte = parameter_buffer.find(b"\x00", current_byte)
            if word_end_byte == -1:
                word_end_byte = len(parameter_buffer)

            value = parameter_buffer[current_byte:word_end_byte].decode(encoding)

            if 0 <= entry_id < entry_amount:
                entries[entry_id][parameter_name] = value

            current_byte = word_end_byte + 1
            current_word += 1
        return

    if parameter_type in {
        "special_scenariocategory",
        "special_scenariocompare",
        "BGM_ID",
        "ENTITY_UID",
    }:
        hex_values = split_hex_chunks(parameter_buffer)
        for entry_index in range(entry_amount):
            entries[entry_index][parameter_name] = (
                hex_values[entry_index] if entry_index < len(hex_values) else ""
            )
        return

    if parameter_type == "special_scenariostatus":
        values = decode_status_values(parameter_buffer)
        for entry_index in range(entry_amount):
            entries[entry_index][parameter_name] = values[entry_index] if entry_index < len(values) else ""
        return

    if parameter_type in INT_PARAMETER_TYPES:
        hex_values = split_hex_chunks(parameter_buffer)
        for entry_index in range(entry_amount):
            entries[entry_index][parameter_name] = (
                int(hex_values[entry_index], 16) if entry_index < len(hex_values) else 0
            )
        return

    if parameter_type == "comment":
        return

    raise BinFormatError(f"Unknown parameter type '{parameter_type}'.")


def encode_parameter_block(document, parameter, encoding):
    parameter_name = parameter.name
    parameter_type = parameter.type_name
    entries = document.entries
    present_entries = [index for index, entry in enumerate(entries) if parameter_name in entry]

    if parameter_type in {"string", "value", "stageid"}:
        if not present_entries:
            return 0, b""

        body = bytearray()
        for entry_index in present_entries:
            body.extend(str(entries[entry_index][parameter_name]).encode(encoding))
            body.append(0)
        body.extend(parameter.tail_padding)
        return len(present_entries), bytes(body)

    if parameter_type in TABLE_PARAMETER_TYPES:
        if not present_entries:
            return 0, b""

        values = [str(entry.get(parameter_name, "")) for entry in entries]
        unique_entries = list(dict.fromkeys(values))

        if len(unique_entries) > 256:
            raise BinFormatError(
                f"Parameter '{parameter_name}' uses more than 256 table values."
            )

        body = bytearray()
        for value in unique_entries:
            body.extend(value.encode(encoding))
            body.append(0)

        for value in values:
            body.append(unique_entries.index(value))

        body.extend(parameter.tail_padding)
        return len(unique_entries), bytes(body)

    if parameter_type in INDEX_PARAMETER_TYPES:
        if not present_entries:
            return 0, b""

        body = bytearray()
        entry_count = 0

        for entry_index in present_entries:
            value = str(entries[entry_index][parameter_name])
            if value == "":
                continue

            body.extend(entry_index.to_bytes(2, "big"))
            body.extend(value.encode(encoding))
            body.append(0)
            entry_count += 1

        body.extend(parameter.tail_padding)
        return entry_count, bytes(body)

    if parameter_type == "special_scenariostatus":
        if not present_entries:
            return 0, b""

        body = bytearray()
        for entry_index in present_entries:
            normalized = normalize_value_for_write(
                parameter_type,
                entries[entry_index][parameter_name],
                parameter_name,
                entry_index,
            )
            if normalized:
                body.extend(bytes.fromhex(normalized))
            body.extend(bytes.fromhex("FFFFFFFF"))

        return len(present_entries), bytes(body)

    if parameter_type in {
        "special_scenariocategory",
        "special_scenariocompare",
        "BGM_ID",
        "ENTITY_UID",
    }:
        if not present_entries:
            return 0, b""

        body = bytearray()
        for entry_index in present_entries:
            normalized = normalize_value_for_write(
                parameter_type,
                entries[entry_index][parameter_name],
                parameter_name,
                entry_index,
            )
            body.extend(bytes.fromhex(normalized))

        return len(present_entries), bytes(body)

    if parameter_type in INT_PARAMETER_TYPES:
        if not present_entries:
            return 0, b""

        body = bytearray()
        for entry_index in present_entries:
            numeric_value = normalize_value_for_write(
                parameter_type,
                entries[entry_index][parameter_name],
                parameter_name,
                entry_index,
            )
            body.extend((numeric_value & 0xFFFFFFFF).to_bytes(4, "big"))

        return len(present_entries), bytes(body)

    if parameter_type == "comment":
        return 0, b""

    raise BinFormatError(f"Unknown parameter type '{parameter_type}'.")


def detect_parameter_tail_padding(parameter, parameter_buffer, entry_amount, encoding):
    parameter_type = parameter.type_name

    if parameter_type in {"string", "value", "stageid"}:
        position = 0
        for _ in range(parameter.count):
            end = parameter_buffer.find(b"\x00", position)
            if end == -1:
                return b"\x00\x00"
            position = end + 1
        return parameter_buffer[position:]

    if parameter_type in TABLE_PARAMETER_TYPES:
        strings_for_table, table_start = read_counted_strings(
            parameter_buffer,
            parameter.count,
            encoding,
        )
        tail_start = min(table_start + entry_amount, len(parameter_buffer))
        return parameter_buffer[tail_start:]

    if parameter_type in INDEX_PARAMETER_TYPES:
        position = 0
        for _ in range(parameter.count):
            if position + 2 > len(parameter_buffer):
                return b"\x00\x00"

            position += 2
            end = parameter_buffer.find(b"\x00", position)
            if end == -1:
                return b"\x00\x00"
            position = end + 1
        return parameter_buffer[position:]

    return b"\x00\x00"


def read_counted_strings(buffer, count, encoding):
    values = []
    position = 0

    for _ in range(count):
        end = buffer.find(b"\x00", position)
        if end == -1:
            end = len(buffer)
        values.append(buffer[position:end].decode(encoding))
        position = min(end + 1, len(buffer))

    return values, position


def split_hex_chunks(buffer):
    hex_string = buffer.hex().upper()
    return [hex_string[index : index + 8] for index in range(0, len(hex_string), 8) if hex_string[index : index + 8]]


def decode_status_values(buffer):
    values = []
    current_chunks = []

    for offset in range(0, len(buffer), 4):
        chunk = buffer[offset : offset + 4]
        if len(chunk) < 4:
            break

        chunk_hex = chunk.hex().upper()
        if chunk_hex == "FFFFFFFF":
            values.append("".join(current_chunks))
            current_chunks = []
        else:
            current_chunks.append(chunk_hex)

    if current_chunks:
        values.append("".join(current_chunks))

    return values


def normalize_value_for_write(parameter_type, value, parameter_name, entry_index):
    try:
        return normalize_parameter_value(parameter_type, value)
    except BinFormatError as exc:
        raise BinFormatError(
            f"{parameter_name} entry {entry_index:03d}: {exc}"
        ) from exc


def clean_hex_input(raw_text):
    cleaned = raw_text.strip().replace(" ", "").replace("\n", "").replace("\r", "")

    if cleaned.startswith("0x") or cleaned.startswith("0X"):
        cleaned = cleaned[2:]

    return cleaned


def normalize_fixed_hex32(raw_text, allow_empty=False):
    cleaned = clean_hex_input(raw_text)

    if cleaned == "":
        if allow_empty:
            return None
        return None

    try:
        int(cleaned, 16)
    except ValueError as exc:
        raise BinFormatError("Hex values may only contain 0-9 and A-F.") from exc

    if len(cleaned) > 8:
        raise BinFormatError("Hex values must fit in 4 bytes (up to 8 hex characters).")

    return cleaned.upper().zfill(8)


def normalize_status_text(raw_text):
    stripped = raw_text.strip()
    if stripped == "":
        return ""

    whitespace_chunks = [chunk for chunk in stripped.replace(",", " ").split() if chunk]
    if len(whitespace_chunks) > 1:
        return "".join(normalize_fixed_hex32(chunk) for chunk in whitespace_chunks)

    cleaned = clean_hex_input(raw_text)
    if cleaned == "":
        return ""

    try:
        int(cleaned, 16)
    except ValueError as exc:
        raise BinFormatError("Hex values may only contain 0-9 and A-F.") from exc

    if len(cleaned) <= 8:
        return cleaned.upper().zfill(8)

    if len(cleaned) % 8 != 0:
        raise BinFormatError(
            "Scenario status values must be 8-hex-character groups."
        )

    return cleaned.upper()


def parse_int_text(raw_text):
    base = 16 if raw_text.lower().startswith("0x") else 10

    try:
        return int(raw_text, base)
    except ValueError as exc:
        raise BinFormatError("Integer fields must be decimal or 0x-prefixed hex.") from exc
