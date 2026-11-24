import 'dart:typed_data';
import 'codec.dart';

const shopGameY0 = 'y0';
const shopGameY3 = 'y3';
const shopGameLabels = {shopGameY0: 'Y0', shopGameY3: 'Y3'};
const sharedFieldName = 'String';

const y0ItemRecordSize = 48;
const y0DescriptionPointerOffset = 32;
const y0ItemFields = [
  ('Item ID', 'u16', 0),
  ('Price 1', 'u32', 20),
  ('Price 2', 'u32', 28),
  ('Description', 'string', y0DescriptionPointerOffset),
  ('Unk 1', 'u32', 40),
];

const y3ItemRecordSize = 20;
const y3DescriptionPointerOffset = 16;
const y3ItemFields = [
  ('Item ID', 'u16', 0),
  ('Unk', 'u16', 2),
  ('Price', 'u32', 4),
  ('Unk 1', 'u32', 8),
  ('Unk 2', 'u32', 12),
  ('Description', 'string', y3DescriptionPointerOffset),
];

class ShopBinFormatError implements Exception {
  final String message;
  ShopBinFormatError(this.message);
  @override
  String toString() => message;
}

class ShopStringEntry {
  int offset;
  String value;
  ShopStringEntry(this.offset, this.value);
}

class ShopSharedText {
  int pointerOffset;
  int stringOffset;
  String value;
  ShopSharedText(this.pointerOffset, this.stringOffset, this.value);
}

class ShopItem {
  Uint8List raw;
  int? descriptionOffset;
  String description;
  ShopItem(this.raw, this.descriptionOffset, this.description);
}

class ShopBinDocument {
  String game;
  Uint8List prefix;
  int itemTableOffset;
  int itemRecordSize;
  int descriptionPointerOffset;
  Uint8List middle;
  List<ShopSharedText> sharedTexts;
  List<ShopItem> items;
  List<ShopStringEntry> stringEntries;
  String encoding;
  String? filePath;

  ShopBinDocument(this.game, this.prefix, this.itemTableOffset, this.itemRecordSize, this.descriptionPointerOffset,
      this.middle, this.sharedTexts, this.items, this.stringEntries, this.encoding, this.filePath);

  int get entryCount => sharedTexts.length + items.length;
  int get itemCount => items.length;
  int get sharedCount => sharedTexts.length;
  List<(String, String, int)> get itemFields => game == shopGameY3 ? y3ItemFields : y0ItemFields;

  (bool, int) describeEntry(int entryIndex) {
    if (entryIndex < 0 || entryIndex >= entryCount) throw RangeError.index(entryIndex, sharedTexts);
    if (entryIndex < sharedTexts.length) return (true, entryIndex);
    return (false, entryIndex - sharedTexts.length);
  }

  String entryLabel(int entryIndex) {
    final (shared, local) = describeEntry(entryIndex);
    return shared ? 'Shared ${pad3(local)}' : 'Item ${pad3(local)}';
  }

  List<String> fieldNamesForEntry(int entryIndex) {
    if (describeEntry(entryIndex).$1) return const [sharedFieldName];
    return [for (final field in itemFields) field.$1];
  }

  Object getValue(int entryIndex, String fieldName) {
    final (shared, local) = describeEntry(entryIndex);
    if (shared) {
      if (fieldName != sharedFieldName) throw ShopBinFormatError("Unknown shared field '$fieldName'.");
      return sharedTexts[local].value;
    }
    final item = items[local];
    for (final (name, type, offset) in itemFields) {
      if (name != fieldName) continue;
      if (type == 'string') return item.description;
      if (type == 'u16') return readU16(item.raw, offset);
      if (type == 'u32') return readU32(item.raw, offset);
    }
    throw ShopBinFormatError("Unknown item field '$fieldName'.");
  }

  void setValue(int entryIndex, String fieldName, Object rawValue) {
    final (shared, local) = describeEntry(entryIndex);
    if (shared) {
      if (fieldName != sharedFieldName) throw ShopBinFormatError("Unknown shared field '$fieldName'.");
      setStringValue(sharedTexts[local].stringOffset, rawValue.toString());
      return;
    }
    final item = items[local];
    for (final (name, type, offset) in itemFields) {
      if (name != fieldName) continue;
      if (type == 'string') {
        final value = rawValue.toString();
        item.description = value;
        final descriptionOffset = item.descriptionOffset;
        if (descriptionOffset != null) setStringValue(descriptionOffset, value);
        return;
      }
      if (type == 'u16') {
        writeU16(item.raw, offset, parseUnsignedInt(rawValue, 0xFFFF, 16));
        return;
      }
      if (type == 'u32') {
        writeU32(item.raw, offset, parseUnsignedInt(rawValue, 0xFFFFFFFF, 32));
        return;
      }
    }
    throw ShopBinFormatError("Unknown item field '$fieldName'.");
  }

  void setStringValue(int stringOffset, String value) {
    for (final entry in stringEntries) {
      if (entry.offset == stringOffset) entry.value = value;
    }
    for (final shared in sharedTexts) {
      if (shared.stringOffset == stringOffset) shared.value = value;
    }
    for (final item in items) {
      if (item.descriptionOffset == stringOffset) item.description = value;
    }
  }

  Uint8List toBytes([String? encodingOverride]) => buildShopBinBytes(this, encodingOverride ?? encoding);
}

ShopBinDocument parseShopBinBytes(Uint8List data, String game, String encoding, [String? filePath]) {
  if (!shopGameLabels.containsKey(game)) throw ShopBinFormatError("Unknown shop BIN game '$game'.");
  if (encoding == autoEncoding) {
    Object? lastError;
    for (final candidate in decodeCandidates) {
      try {
        return parseShopBinBytes(data, game, candidate, filePath);
      } on ShopBinFormatError catch (error) {
        lastError = error;
      } on TextDecodeError catch (error) {
        lastError = error;
      }
    }
    throw ShopBinFormatError('Failed to read the shop BIN with UTF-8 or CP932: $lastError');
  }
  if (game == shopGameY3) return parseY3ShopBinBytes(data, encoding, filePath);
  return parseY0ShopBinBytes(data, encoding, filePath);
}

Uint8List sliceBytes(Uint8List data, int start, int end) {
  final s = start.clamp(0, data.length);
  final e = end.clamp(0, data.length);
  return e <= s ? Uint8List(0) : Uint8List.fromList(Uint8List.sublistView(data, s, e));
}

ShopBinDocument parseY0ShopBinBytes(Uint8List data, String encoding, String? filePath) {
  if (data.length < 16) throw ShopBinFormatError('Y0 shop BIN is too small to contain a valid header.');
  final itemCount = readU16(data, 6);
  final itemTableOffset = readU32(data, 12);
  final itemTableEnd = itemTableOffset + itemCount * y0ItemRecordSize;
  validateTableBounds(data, itemTableOffset, itemTableEnd, 'Y0 item table');

  final sharedCount = countY0SharedTexts(data, itemTableOffset, encoding);
  if (sharedCount <= 0) throw ShopBinFormatError('Y0 shop BIN did not contain readable shared text pointers.');

  final sharedTexts = readSharedTexts(data, 16, sharedCount, encoding);
  final items = readItems(data, itemTableOffset, itemCount, y0ItemRecordSize, y0DescriptionPointerOffset, encoding);
  final stringStart = findStringStart(sharedTexts, items);
  final stringEntries = readStringTable(data, stringStart, encoding);

  return ShopBinDocument(
    shopGameY0,
    sliceBytes(data, 0, itemTableOffset),
    itemTableOffset,
    y0ItemRecordSize,
    y0DescriptionPointerOffset,
    sliceBytes(data, itemTableEnd, stringStart),
    sharedTexts,
    items,
    stringEntries,
    encoding,
    filePath,
  );
}

ShopBinDocument parseY3ShopBinBytes(Uint8List data, String encoding, String? filePath) {
  if (data.length < 48) throw ShopBinFormatError('Y3 shop BIN is too small to contain a valid header.');
  final itemCount = readU32(data, 4);
  final itemTableOffset = readU32(data, 8);
  final stringTableOffset = readU32(data, 12);
  final itemTableEnd = itemTableOffset + itemCount * y3ItemRecordSize;
  validateTableBounds(data, itemTableOffset, itemTableEnd, 'Y3 item table');

  if (stringTableOffset < itemTableEnd || stringTableOffset > data.length) {
    throw ShopBinFormatError('Y3 string table pointer is outside the BIN.');
  }

  final sharedTexts = readSharedTexts(data, 16, 8, encoding);
  final items = readItems(data, itemTableOffset, itemCount, y3ItemRecordSize, y3DescriptionPointerOffset, encoding);
  final stringEntries = readStringTable(data, stringTableOffset, encoding);

  return ShopBinDocument(
    shopGameY3,
    sliceBytes(data, 0, itemTableOffset),
    itemTableOffset,
    y3ItemRecordSize,
    y3DescriptionPointerOffset,
    sliceBytes(data, itemTableEnd, stringTableOffset),
    sharedTexts,
    items,
    stringEntries,
    encoding,
    filePath,
  );
}

void validateTableBounds(Uint8List data, int start, int end, String label) {
  if (start < 16 || start > data.length) throw ShopBinFormatError('$label pointer is outside the BIN.');
  if (end > data.length) throw ShopBinFormatError('$label extends past the end of the BIN.');
}

int countY0SharedTexts(Uint8List data, int itemTableOffset, String encoding) {
  var count = 0;
  var offset = 16;
  while (offset + 4 <= itemTableOffset) {
    try {
      readCString(data, readU32(data, offset), encoding);
    } on ShopBinFormatError {
      break;
    } on TextDecodeError {
      break;
    }
    count++;
    offset += 4;
  }
  return count;
}

List<ShopSharedText> readSharedTexts(Uint8List data, int tableOffset, int count, String encoding) {
  return [
    for (var i = 0; i < count; i++)
      () {
        final pointerOffset = tableOffset + i * 4;
        final stringOffset = readU32(data, pointerOffset);
        return ShopSharedText(pointerOffset, stringOffset, readCString(data, stringOffset, encoding));
      }(),
  ];
}

List<ShopItem> readItems(
    Uint8List data, int tableOffset, int count, int recordSize, int descriptionPointerOffset, String encoding) {
  final items = <ShopItem>[];
  for (var i = 0; i < count; i++) {
    final start = tableOffset + i * recordSize;
    final raw = sliceBytes(data, start, start + recordSize);
    final offset = readU32(raw, descriptionPointerOffset);
    if (offset > 0 && offset < data.length) {
      items.add(ShopItem(raw, offset, readCString(data, offset, encoding)));
    } else {
      items.add(ShopItem(raw, null, ''));
    }
  }
  return items;
}

int findStringStart(List<ShopSharedText> sharedTexts, List<ShopItem> items) {
  final offsets = <int>[
    for (final shared in sharedTexts) shared.stringOffset,
    for (final item in items)
      if (item.descriptionOffset != null) item.descriptionOffset!,
  ];
  if (offsets.isEmpty) throw ShopBinFormatError('Shop BIN didnt contain any readable string pointers.');
  return offsets.reduce((a, b) => a < b ? a : b);
}

List<ShopStringEntry> readStringTable(Uint8List data, int start, String encoding) {
  if (start < 0 || start > data.length) throw ShopBinFormatError('String table starts outside the BIN.');
  final entries = <ShopStringEntry>[];
  var offset = start;
  while (offset < data.length) {
    final end = indexOfZero(data, offset);
    if (end == -1) throw ShopBinFormatError('String table contains an unterminated string.');
    entries.add(ShopStringEntry(offset, decodeText(Uint8List.sublistView(data, offset, end), encoding)));
    offset = end + 1;
  }
  return entries;
}

String readCString(Uint8List data, int offset, String encoding) {
  final hex = offset.toRadixString(16).toUpperCase();
  if (offset <= 0 || offset >= data.length) throw ShopBinFormatError('String pointer 0x$hex is outside the BIN.');
  final end = indexOfZero(data, offset);
  if (end == -1) throw ShopBinFormatError('String pointer 0x$hex is unterminated.');
  return decodeText(Uint8List.sublistView(data, offset, end), encoding);
}

void patchKnownStringPointers(Uint8List buffer, Map<int, int> newOffsets) {
  if (newOffsets.isEmpty) return;
  final wordCount = buffer.length ~/ 4;
  final words = [for (var i = 0; i < wordCount; i++) readU32(buffer, i * 4)];
  for (var i = 0; i < wordCount; i++) {
    final replacement = newOffsets[words[i]];
    if (replacement != null) writeU32(buffer, i * 4, replacement);
  }
}

Uint8List buildShopBinBytes(ShopBinDocument document, String encoding) {
  final prefix = Uint8List.fromList(document.prefix);
  if (document.game == shopGameY3) {
    writeU32(prefix, 4, document.items.length);
  } else {
    if (document.items.length > 0xFFFF) throw ShopBinFormatError('Y0 shop BINs cant contain more than 65535 items.');
    writeU16(prefix, 6, document.items.length);
  }

  final rows = BytesBuilder(copy: false);
  final newSlots = <(int, String)>[];
  for (var i = 0; i < document.items.length; i++) {
    final item = document.items[i];
    if (item.raw.length != document.itemRecordSize) {
      throw ShopBinFormatError('Item ${pad3(i)} has an invalid record size.');
    }
    final rowStart = prefix.length + rows.length;
    rows.add(item.raw);
    if (item.descriptionOffset == null && item.description.isNotEmpty) {
      newSlots.add((rowStart + document.descriptionPointerOffset, item.description));
    }
  }

  final preBuilder = BytesBuilder(copy: false)
    ..add(prefix)
    ..add(rows.takeBytes())
    ..add(document.middle);
  final preStrings = preBuilder.takeBytes();

  if (document.game == shopGameY3) writeU32(preStrings, 12, preStrings.length);

  final offsetToValue = <int, String>{for (final entry in document.stringEntries) entry.offset: entry.value};
  for (final shared in document.sharedTexts) {
    offsetToValue[shared.stringOffset] = shared.value;
  }
  for (final item in document.items) {
    final offset = item.descriptionOffset;
    if (offset != null) offsetToValue[offset] = item.description;
  }

  final newOffsets = <int, int>{};
  final stringData = BytesBuilder(copy: false);
  for (final entry in document.stringEntries) {
    newOffsets[entry.offset] = preStrings.length + stringData.length;
    stringData.add(encodeText(offsetToValue[entry.offset]!, encoding));
    stringData.addByte(0);
  }
  for (final (slotOffset, description) in newSlots) {
    writeU32(preStrings, slotOffset, preStrings.length + stringData.length);
    stringData.add(encodeText(description, encoding));
    stringData.addByte(0);
  }

  patchKnownStringPointers(preStrings, newOffsets);
  return (BytesBuilder(copy: false)
        ..add(preStrings)
        ..add(stringData.takeBytes()))
      .takeBytes();
}

String formatShopValueForEditor(Object? value) => value == null ? '' : value.toString();

int parseUnsignedInt(Object rawValue, int maxValue, int bits) {
  final cleaned = rawValue.toString().trim();
  if (cleaned.isEmpty) throw ShopBinFormatError('Numeric fields cant be empty.');
  final parsed = parsePythonInt(cleaned);
  if (parsed == null) throw ShopBinFormatError('Numeric fields must be decimal or 0x-prefixed hex.');
  if (parsed < BigInt.zero || parsed > BigInt.from(maxValue)) throw ShopBinFormatError('Value must fit in $bits bits.');
  return parsed.toInt();
}
