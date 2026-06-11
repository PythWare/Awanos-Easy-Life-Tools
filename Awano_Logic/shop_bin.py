from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

AUTO_ENCODING = "auto"
SHOP_GAME_Y0 = "y0"
SHOP_GAME_Y3 = "y3"
SHOP_GAME_LABELS = {
    SHOP_GAME_Y0: "Y0",
    SHOP_GAME_Y3: "Y3",
}

SHARED_FIELD_NAME = "String"

Y0_ITEM_RECORD_SIZE = 48
Y0_DESCRIPTION_POINTER_OFFSET = 32
Y0_ITEM_FIELDS = [
    ("Item ID", "u16", 0),
    ("Price 1", "u32", 20),
    ("Price 2", "u32", 28),
    ("Description", "string", Y0_DESCRIPTION_POINTER_OFFSET),
    ("Unk 1", "u32", 40),
]

Y3_ITEM_RECORD_SIZE = 20
Y3_DESCRIPTION_POINTER_OFFSET = 16
Y3_ITEM_FIELDS = [
    ("Item ID", "u16", 0),
    ("Unk", "u16", 2),
    ("Price", "u32", 4),
    ("Unk 1", "u32", 8),
    ("Unk 2", "u32", 12),
    ("Description", "string", Y3_DESCRIPTION_POINTER_OFFSET),
]


class ShopBinFormatError(ValueError):
    pass


@dataclass(slots=True)
class ShopStringEntry:
    offset: int
    value: str


@dataclass(slots=True)
class ShopSharedText:
    pointer_offset: int
    string_offset: int
    value: str


@dataclass(slots=True)
class ShopItem:
    raw: bytearray
    description_offset: int | None
    description: str


@dataclass(slots=True)
class ShopBinDocument:
    game: str
    prefix: bytes
    item_table_offset: int
    item_record_size: int
    description_pointer_offset: int
    middle: bytes
    shared_texts: list[ShopSharedText]
    items: list[ShopItem]
    string_entries: list[ShopStringEntry]
    encoding: str = "utf-8"
    file_path: str | None = None

    @property
    def entry_count(self):
        return len(self.shared_texts) + len(self.items)

    @property
    def item_fields(self):
        return Y3_ITEM_FIELDS if self.game == SHOP_GAME_Y3 else Y0_ITEM_FIELDS

    @property
    def item_count(self):
        return len(self.items)

    @property
    def shared_count(self):
        return len(self.shared_texts)

    def entry_label(self, entry_index):
        entry_type, local_index = self.describe_entry(entry_index)
        if entry_type == "shared":
            return f"Shared {local_index:03d}"
        return f"Item {local_index:03d}"

    def describe_entry(self, entry_index):
        if entry_index < 0 or entry_index >= self.entry_count:
            raise IndexError(entry_index)

        if entry_index < len(self.shared_texts):
            return "shared", entry_index

        return "item", entry_index - len(self.shared_texts)

    def field_names_for_entry(self, entry_index):
        entry_type, _local_index = self.describe_entry(entry_index)
        if entry_type == "shared":
            return [SHARED_FIELD_NAME]

        return [field_name for field_name, _field_type, _offset in self.item_fields]

    def get_value(self, entry_index, field_name):
        entry_type, local_index = self.describe_entry(entry_index)
        if entry_type == "shared":
            if field_name != SHARED_FIELD_NAME:
                raise ShopBinFormatError(f"Unknown shared field '{field_name}'.")
            return self.shared_texts[local_index].value

        item = self.items[local_index]
        for candidate_name, field_type, offset in self.item_fields:
            if candidate_name != field_name:
                continue

            if field_type == "string":
                return item.description

            if field_type == "u16":
                return struct.unpack_from(">H", item.raw, offset)[0]

            if field_type == "u32":
                return struct.unpack_from(">I", item.raw, offset)[0]

        raise ShopBinFormatError(f"Unknown item field '{field_name}'.")

    def set_value(self, entry_index, field_name, raw_value):
        entry_type, local_index = self.describe_entry(entry_index)
        if entry_type == "shared":
            if field_name != SHARED_FIELD_NAME:
                raise ShopBinFormatError(f"Unknown shared field '{field_name}'.")
            shared = self.shared_texts[local_index]
            self.set_string_value(shared.string_offset, str(raw_value))
            return

        item = self.items[local_index]
        for candidate_name, field_type, offset in self.item_fields:
            if candidate_name != field_name:
                continue

            if field_type == "string":
                value = str(raw_value)
                item.description = value
                if item.description_offset is not None:
                    self.set_string_value(item.description_offset, value)
                return

            if field_type == "u16":
                struct.pack_into(">H", item.raw, offset, parse_unsigned_int(raw_value, 0xFFFF))
                return

            if field_type == "u32":
                struct.pack_into(">I", item.raw, offset, parse_unsigned_int(raw_value, 0xFFFFFFFF))
                return

        raise ShopBinFormatError(f"Unknown item field '{field_name}'.")

    def set_string_value(self, string_offset, value):
        for string_entry in self.string_entries:
            if string_entry.offset == string_offset:
                string_entry.value = value

        for shared in self.shared_texts:
            if shared.string_offset == string_offset:
                shared.value = value

        for item in self.items:
            if item.description_offset == string_offset:
                item.description = value

    def to_bytes(self, encoding=None):
        return build_shop_bin_bytes(self, encoding=encoding or self.encoding)

    def save(self, path=None, encoding=None):
        target = path or self.file_path
        if not target:
            raise ValueError("No output path was provided.")

        Path(target).write_bytes(self.to_bytes(encoding=encoding))
        self.file_path = str(target)
        if encoding:
            self.encoding = encoding


def load_shop_bin(file_path, game=SHOP_GAME_Y0, encoding=AUTO_ENCODING):
    data = Path(file_path).read_bytes()
    return parse_shop_bin_bytes(data, game=game, encoding=encoding, file_path=str(file_path))


def parse_shop_bin_bytes(data, game=SHOP_GAME_Y0, encoding=AUTO_ENCODING, file_path=None):
    if game not in SHOP_GAME_LABELS:
        raise ShopBinFormatError(f"Unknown shop BIN game '{game}'.")

    if encoding == AUTO_ENCODING:
        last_error = None
        for candidate in ("utf-8", "cp932", "shift_jis"):
            try:
                return parse_shop_bin_bytes(
                    data,
                    game=game,
                    encoding=candidate,
                    file_path=file_path,
                )
            except (ShopBinFormatError, UnicodeDecodeError) as exc:
                last_error = exc

        raise ShopBinFormatError("Failed to decode shop BIN with UTF-8, CP932, or Shift-JIS.") from last_error

    if game == SHOP_GAME_Y3:
        return parse_y3_shop_bin_bytes(data, encoding, file_path=file_path)

    return parse_y0_shop_bin_bytes(data, encoding, file_path=file_path)


def build_shop_bin_bytes(document, encoding=None):
    selected_encoding = encoding or document.encoding
    prefix = bytearray(document.prefix)

    if document.game == SHOP_GAME_Y3:
        struct.pack_into(">I", prefix, 4, len(document.items))
    else:
        if len(document.items) > 0xFFFF:
            raise ShopBinFormatError("Y0 shop BINs cannot contain more than 65535 items.")
        struct.pack_into(">H", prefix, 6, len(document.items))

    rows = bytearray()
    new_description_slots = []
    for item_index, item in enumerate(document.items):
        if len(item.raw) != document.item_record_size:
            raise ShopBinFormatError(f"Item {item_index:03d} has an invalid record size.")

        row_start = len(prefix) + len(rows)
        rows.extend(item.raw)

        if item.description_offset is None and item.description:
            new_description_slots.append(
                (row_start + document.description_pointer_offset, item.description)
            )

    pre_strings = prefix + rows + document.middle

    if document.game == SHOP_GAME_Y3:
        struct.pack_into(">I", pre_strings, 12, len(pre_strings))

    offset_to_value = {entry.offset: entry.value for entry in document.string_entries}
    for shared in document.shared_texts:
        offset_to_value[shared.string_offset] = shared.value
    for item in document.items:
        if item.description_offset is not None:
            offset_to_value[item.description_offset] = item.description

    new_offsets = {}
    string_data = bytearray()
    for entry in document.string_entries:
        new_offsets[entry.offset] = len(pre_strings) + len(string_data)
        string_data.extend(offset_to_value[entry.offset].encode(selected_encoding))
        string_data.append(0)

    for slot_offset, description in new_description_slots:
        new_offset = len(pre_strings) + len(string_data)
        struct.pack_into(">I", pre_strings, slot_offset, new_offset)
        string_data.extend(description.encode(selected_encoding))
        string_data.append(0)

    patch_known_string_pointers(pre_strings, new_offsets)
    return bytes(pre_strings) + bytes(string_data)


def format_shop_value_for_editor(value):
    if value is None:
        return ""
    return str(value)


def parse_y0_shop_bin_bytes(data, encoding, file_path=None):
    if len(data) < 16:
        raise ShopBinFormatError("Y0 shop BIN is too small to contain a valid header.")

    unk1, yes, item_count, unk, item_table_offset = struct.unpack_from(">IHHII", data, 0)
    item_table_end = item_table_offset + item_count * Y0_ITEM_RECORD_SIZE
    validate_table_bounds(data, item_table_offset, item_table_end, "Y0 item table")

    shared_count = count_y0_shared_texts(data, item_table_offset, encoding)
    if shared_count <= 0:
        raise ShopBinFormatError("Y0 shop BIN did not contain readable shared text pointers.")

    shared_texts = read_shared_texts(data, 16, shared_count, encoding)
    items = read_items(
        data,
        item_table_offset,
        item_count,
        Y0_ITEM_RECORD_SIZE,
        Y0_DESCRIPTION_POINTER_OFFSET,
        encoding,
    )
    string_start = find_string_start(shared_texts, items)
    string_entries = read_string_table(data, string_start, encoding)

    return ShopBinDocument(
        game=SHOP_GAME_Y0,
        prefix=data[:item_table_offset],
        item_table_offset=item_table_offset,
        item_record_size=Y0_ITEM_RECORD_SIZE,
        description_pointer_offset=Y0_DESCRIPTION_POINTER_OFFSET,
        middle=data[item_table_end:string_start],
        shared_texts=shared_texts,
        items=items,
        string_entries=string_entries,
        encoding=encoding,
        file_path=file_path,
    )


def parse_y3_shop_bin_bytes(data, encoding, file_path=None):
    if len(data) < 48:
        raise ShopBinFormatError("Y3 shop BIN is too small to contain a valid header.")

    version, item_count, item_table_offset, string_table_offset = struct.unpack_from(">IIII", data, 0)
    item_table_end = item_table_offset + item_count * Y3_ITEM_RECORD_SIZE
    validate_table_bounds(data, item_table_offset, item_table_end, "Y3 item table")

    if string_table_offset < item_table_end or string_table_offset > len(data):
        raise ShopBinFormatError("Y3 string table pointer is outside the BIN.")

    shared_texts = read_shared_texts(data, 16, 8, encoding)
    items = read_items(
        data,
        item_table_offset,
        item_count,
        Y3_ITEM_RECORD_SIZE,
        Y3_DESCRIPTION_POINTER_OFFSET,
        encoding,
    )
    string_entries = read_string_table(data, string_table_offset, encoding)

    return ShopBinDocument(
        game=SHOP_GAME_Y3,
        prefix=data[:item_table_offset],
        item_table_offset=item_table_offset,
        item_record_size=Y3_ITEM_RECORD_SIZE,
        description_pointer_offset=Y3_DESCRIPTION_POINTER_OFFSET,
        middle=data[item_table_end:string_table_offset],
        shared_texts=shared_texts,
        items=items,
        string_entries=string_entries,
        encoding=encoding,
        file_path=file_path,
    )


def validate_table_bounds(data, start, end, label):
    if start < 16 or start > len(data):
        raise ShopBinFormatError(f"{label} pointer is outside the BIN.")

    if end > len(data):
        raise ShopBinFormatError(f"{label} extends past the end of the BIN.")


def count_y0_shared_texts(data, item_table_offset, encoding):
    count = 0
    offset = 16
    while offset + 4 <= item_table_offset:
        string_offset = struct.unpack_from(">I", data, offset)[0]
        try:
            read_c_string(data, string_offset, encoding)
        except (ShopBinFormatError, UnicodeDecodeError):
            break

        count += 1
        offset += 4

    return count


def read_shared_texts(data, pointer_table_offset, shared_count, encoding):
    shared_texts = []
    for shared_index in range(shared_count):
        pointer_offset = pointer_table_offset + shared_index * 4
        string_offset = struct.unpack_from(">I", data, pointer_offset)[0]
        value = read_c_string(data, string_offset, encoding)
        shared_texts.append(
            ShopSharedText(
                pointer_offset=pointer_offset,
                string_offset=string_offset,
                value=value,
            )
        )

    return shared_texts


def read_items(data, table_offset, item_count, record_size, description_pointer_offset, encoding):
    items = []
    for item_index in range(item_count):
        record_start = table_offset + item_index * record_size
        raw = bytearray(data[record_start : record_start + record_size])
        description_offset = struct.unpack_from(">I", raw, description_pointer_offset)[0]
        if 0 < description_offset < len(data):
            description = read_c_string(data, description_offset, encoding)
        else:
            description_offset = None
            description = ""

        items.append(
            ShopItem(
                raw=raw,
                description_offset=description_offset,
                description=description,
            )
        )

    return items


def find_string_start(shared_texts, items):
    offsets = [shared.string_offset for shared in shared_texts]
    offsets.extend(
        item.description_offset
        for item in items
        if item.description_offset is not None
    )
    offsets = [offset for offset in offsets if offset is not None]
    if not offsets:
        raise ShopBinFormatError("Shop BIN did not contain any readable string pointers.")
    return min(offsets)


def read_string_table(data, string_start, encoding):
    if string_start < 0 or string_start > len(data):
        raise ShopBinFormatError("String table starts outside the BIN.")

    entries = []
    offset = string_start
    while offset < len(data):
        end = data.find(b"\x00", offset)
        if end == -1:
            raise ShopBinFormatError("String table contains an unterminated string.")

        value = data[offset:end].decode(encoding)
        entries.append(ShopStringEntry(offset=offset, value=value))
        offset = end + 1

    return entries


def read_c_string(data, offset, encoding):
    if offset <= 0 or offset >= len(data):
        raise ShopBinFormatError(f"String pointer 0x{offset:X} is outside the BIN.")

    end = data.find(b"\x00", offset)
    if end == -1:
        raise ShopBinFormatError(f"String pointer 0x{offset:X} is unterminated.")

    return data[offset:end].decode(encoding)


def patch_known_string_pointers(buffer, new_offsets):
    if not new_offsets:
        return

    for offset in range(0, len(buffer) - 3, 4):
        value = struct.unpack_from(">I", buffer, offset)[0]
        if value in new_offsets:
            struct.pack_into(">I", buffer, offset, new_offsets[value])


def parse_unsigned_int(raw_value, max_value):
    cleaned = str(raw_value).strip()
    if not cleaned:
        raise ShopBinFormatError("Numeric fields cannot be empty.")

    base = 16 if cleaned.lower().startswith("0x") else 10
    try:
        value = int(cleaned, base)
    except ValueError as exc:
        raise ShopBinFormatError("Numeric fields must be decimal or 0x-prefixed hex.") from exc

    if value < 0 or value > max_value:
        raise ShopBinFormatError(f"Value must fit in {max_value.bit_length()} bits.")

    return value
