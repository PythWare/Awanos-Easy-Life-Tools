import 'dart:typed_data';
import 'codec.dart';

const binMagic = [0x20, 0x07, 0x03, 0x19];
const parameterRecordSize = 64;
const parameterNameSize = 48;
const binHeaderBaseSize = 16;

const parameterTypes = [
  'string',
  'string_tbl',
  'string_idx',
  'value',
  'value_tbl',
  'value_idx',
  'special_scenariocategory',
  'special_scenariostatus',
  'stageid',
  'special_scenariocompare',
  'special_value',
  'itemid',
  'comment',
  'BGM_ID',
  'unknown',
  'USE_COUNTER',
  'ENTITY_UID',
];

const textParameterTypes = {'string', 'string_tbl', 'string_idx', 'value', 'value_tbl', 'value_idx', 'stageid'};
const plainStringTypes = {'string', 'value', 'stageid'};
const tableParameterTypes = {'string_tbl', 'value_tbl'};
const indexParameterTypes = {'string_idx', 'value_idx'};
const fixedHexTypes = {'special_scenariocategory', 'special_scenariocompare', 'BGM_ID', 'ENTITY_UID'};
const intParameterTypes = {'special_value', 'itemid', 'USE_COUNTER'};
const unsupportedParameterTypes = {'comment', 'unknown'};

class BinFormatError implements Exception {
  final String message;
  BinFormatError(this.message);
  @override
  String toString() => message;
}

class BinParameter {
  String name;
  int typeIndex;
  int count;
  int size;
  Uint8List tailPadding;

  BinParameter(this.name, this.typeIndex, this.count, this.size) : tailPadding = Uint8List.fromList([0, 0]);

  String get typeName {
    if (typeIndex < 0 || typeIndex >= parameterTypes.length) {
      throw BinFormatError('Unknown parameter type index $typeIndex');
    }
    return parameterTypes[typeIndex];
  }

  String get safeTypeName {
    try {
      return typeName;
    } on BinFormatError {
      return 'unknown';
    }
  }
}

class BinDocument {
  List<BinParameter> parameters;
  int entryCount;
  List<Map<String, Object>> entries;
  String encoding;
  String? filePath;

  BinDocument(this.parameters, this.entryCount, this.entries, this.encoding, this.filePath);

  BinParameter getParameter(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    throw BinFormatError('Unknown parameter $name');
  }

  Object getValue(int entryIndex, String name, [Object fallback = '']) => entries[entryIndex][name] ?? fallback;

  bool hasValue(int entryIndex, String name) => entries[entryIndex].containsKey(name);

  void setValue(int entryIndex, String name, Object value) {
    final parameter = getParameter(name);
    final normalized = normalizeParameterValue(parameter.typeName, value);
    if (normalized == null) {
      entries[entryIndex].remove(name);
      return;
    }
    entries[entryIndex][name] = normalized;
  }

  void unsetValue(int entryIndex, String name) => entries[entryIndex].remove(name);

  int appendEntry(Map<String, Object>? source) {
    entries.add(source == null ? <String, Object>{} : Map<String, Object>.of(source));
    entryCount = entries.length;
    return entryCount - 1;
  }

  Uint8List toBytes([String? encodingOverride]) => buildBinBytes(this, encodingOverride ?? encoding);
}

BinDocument parseBinBytes(Uint8List data, String encoding, [String? filePath]) {
  if (encoding == autoEncoding) {
    for (final candidate in decodeCandidates) {
      try {
        return parseBinBytesWithEncoding(data, candidate, filePath);
      } on TextDecodeError {
        continue;
      }
    }
    throw BinFormatError('Failed to decode BIN with UTF-8 or CP932.');
  }
  return parseBinBytesWithEncoding(data, encoding, filePath);
}

BinDocument parseBinBytesWithEncoding(Uint8List data, String encoding, [String? filePath]) {
  if (data.length < binHeaderBaseSize) throw BinFormatError('BIN file is too small to contain a valid header.');
  for (var i = 0; i < 4; i++) {
    if (data[i] != binMagic[i]) throw BinFormatError('Not a 20070319 BIN file.');
  }

  final parameterAmount = readU32(data, 4);
  final entryAmount = readU32(data, 8);
  final headerEnd = binHeaderBaseSize + parameterAmount * parameterRecordSize;
  if (headerEnd > data.length) throw BinFormatError('BIN header extends past the end of the file.');

  final parameters = <BinParameter>[];
  final entries = List<Map<String, Object>>.generate(entryAmount, (index) => <String, Object>{});
  var currentPosition = 0;

  for (var current = 0; current < parameterAmount; current++) {
    final recordStart = binHeaderBaseSize + current * parameterRecordSize;
    final rawName = Uint8List.sublistView(data, recordStart, recordStart + parameterNameSize);
    final zero = indexOfZero(rawName, 0);
    final name = decodeText(Uint8List.sublistView(rawName, 0, zero < 0 ? rawName.length : zero), encoding);
    final parameter =
        BinParameter(name, readU32(data, recordStart + 48), readU32(data, recordStart + 52), readU32(data, recordStart + 56));
    parameters.add(parameter);

    if (parameter.size == 0) continue;

    final blockStart = headerEnd + currentPosition;
    final blockEnd = blockStart + parameter.size;
    if (blockEnd > data.length) throw BinFormatError("Parameter '$name' extends past the end of the BIN.");
    final buffer = Uint8List.sublistView(data, blockStart, blockEnd);
    decodeParameterBlock(entries, parameter, buffer, entryAmount, encoding);
    parameter.tailPadding = detectParameterTailPadding(parameter, buffer, entryAmount, encoding);
    currentPosition += parameter.size;
  }

  return BinDocument(parameters, entryAmount, entries, encoding, filePath);
}

(List<String>, int) readCountedStrings(Uint8List buffer, int count, String encoding) {
  final values = <String>[];
  var position = 0;
  for (var i = 0; i < count; i++) {
    var end = indexOfZero(buffer, position);
    if (end == -1) end = buffer.length;
    values.add(decodeText(Uint8List.sublistView(buffer, position, end), encoding));
    position = end + 1 < buffer.length ? end + 1 : buffer.length;
  }
  return (values, position);
}

List<String> splitHexChunks(Uint8List buffer) {
  final hex = hexUpper(buffer);
  final chunks = <String>[];
  for (var i = 0; i < hex.length; i += 8) {
    chunks.add(hex.substring(i, i + 8 < hex.length ? i + 8 : hex.length));
  }
  return chunks;
}

List<String> decodeStatusValues(Uint8List buffer) {
  final values = <String>[];
  var current = StringBuffer();
  var hasCurrent = false;
  for (var offset = 0; offset + 4 <= buffer.length; offset += 4) {
    final chunk = hexUpper(Uint8List.sublistView(buffer, offset, offset + 4));
    if (chunk == 'FFFFFFFF') {
      values.add(current.toString());
      current = StringBuffer();
      hasCurrent = false;
    } else {
      current.write(chunk);
      hasCurrent = true;
    }
  }
  if (hasCurrent) values.add(current.toString());
  return values;
}

void decodeParameterBlock(
    List<Map<String, Object>> entries, BinParameter parameter, Uint8List buffer, int entryAmount, String encoding) {
  final name = parameter.name;
  final type = parameter.typeName;

  if (plainStringTypes.contains(type)) {
    final strings = decodeText(buffer, encoding).split('\u0000');
    for (var i = 0; i < entryAmount; i++) {
      if (i < strings.length) entries[i][name] = strings[i];
    }
    return;
  }

  if (tableParameterTypes.contains(type)) {
    final (table, tableStart) = readCountedStrings(buffer, parameter.count, encoding);
    final tableEnd = tableStart + entryAmount < buffer.length ? tableStart + entryAmount : buffer.length;
    final tableBytes = Uint8List.sublistView(buffer, tableStart, tableEnd);
    for (var i = 0; i < entryAmount; i++) {
      if (i >= tableBytes.length) continue;
      final slot = tableBytes[i];
      if (slot < table.length) entries[i][name] = table[slot];
    }
    return;
  }

  if (indexParameterTypes.contains(type)) {
    for (var i = 0; i < entryAmount; i++) {
      entries[i][name] = '';
    }
    var currentByte = 0;
    var currentWord = 0;
    while (currentWord < parameter.count && currentByte + 2 <= buffer.length) {
      final entryId = readU16(buffer, currentByte);
      currentByte += 2;
      var end = indexOfZero(buffer, currentByte);
      if (end == -1) end = buffer.length;
      final value = decodeText(Uint8List.sublistView(buffer, currentByte, end), encoding);
      if (entryId < entryAmount) entries[entryId][name] = value;
      currentByte = end + 1;
      currentWord++;
    }
    return;
  }

  if (fixedHexTypes.contains(type)) {
    final values = splitHexChunks(buffer);
    for (var i = 0; i < entryAmount; i++) {
      entries[i][name] = i < values.length ? values[i] : '';
    }
    return;
  }

  if (type == 'special_scenariostatus') {
    final values = decodeStatusValues(buffer);
    for (var i = 0; i < entryAmount; i++) {
      entries[i][name] = i < values.length ? values[i] : '';
    }
    return;
  }

  if (intParameterTypes.contains(type)) {
    final values = splitHexChunks(buffer);
    for (var i = 0; i < entryAmount; i++) {
      entries[i][name] = i < values.length ? int.parse(values[i], radix: 16) : 0;
    }
    return;
  }

  if (type == 'comment') return;

  throw BinFormatError("Unknown parameter type '$type'.");
}

Uint8List detectParameterTailPadding(BinParameter parameter, Uint8List buffer, int entryAmount, String encoding) {
  final type = parameter.typeName;
  final fallback = Uint8List.fromList([0, 0]);

  if (plainStringTypes.contains(type)) {
    var position = 0;
    for (var i = 0; i < parameter.count; i++) {
      final end = indexOfZero(buffer, position);
      if (end == -1) return fallback;
      position = end + 1;
    }
    return Uint8List.fromList(Uint8List.sublistView(buffer, position < buffer.length ? position : buffer.length));
  }

  if (tableParameterTypes.contains(type)) {
    final tableStart = readCountedStrings(buffer, parameter.count, encoding).$2;
    final tailStart = tableStart + entryAmount < buffer.length ? tableStart + entryAmount : buffer.length;
    return Uint8List.fromList(Uint8List.sublistView(buffer, tailStart));
  }

  if (indexParameterTypes.contains(type)) {
    var position = 0;
    for (var i = 0; i < parameter.count; i++) {
      if (position + 2 > buffer.length) return fallback;
      position += 2;
      final end = indexOfZero(buffer, position);
      if (end == -1) return fallback;
      position = end + 1;
    }
    return Uint8List.fromList(Uint8List.sublistView(buffer, position < buffer.length ? position : buffer.length));
  }

  return fallback;
}

String formatValueForEditor(String type, Object? value) => value == null ? '' : value.toString();

Object? normalizeParameterValue(String type, Object value) {
  final raw = value is String ? value : value.toString();
  if (textParameterTypes.contains(type)) return raw;
  if (type == 'special_scenariostatus') return normalizeStatusText(raw);
  if (fixedHexTypes.contains(type)) return normalizeFixedHex32(raw);
  if (intParameterTypes.contains(type)) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    return parseIntText(cleaned);
  }
  if (unsupportedParameterTypes.contains(type)) return raw;
  throw BinFormatError("Unsupported parameter type '$type'.");
}

Object? normalizeValueForWrite(String type, Object value, String name, int entryIndex) {
  try {
    return normalizeParameterValue(type, value);
  } on BinFormatError catch (error) {
    throw BinFormatError('$name entry ${pad3(entryIndex)}: ${error.message}');
  }
}

String cleanHexInput(String raw) {
  var cleaned = raw.trim().replaceAll(' ', '').replaceAll('\n', '').replaceAll('\r', '');
  if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) cleaned = cleaned.substring(2);
  return cleaned;
}

final hexDigitsPattern = RegExp(r'^[0-9a-fA-F]+$');

String? normalizeFixedHex32(String raw) {
  final cleaned = cleanHexInput(raw);
  if (cleaned.isEmpty) return null;
  if (!hexDigitsPattern.hasMatch(cleaned)) throw BinFormatError('Hex values may only contain 0-9 and A-F.');
  if (cleaned.length > 8) throw BinFormatError('Hex values must fit in 4 bytes, up to 8 hex characters.');
  return cleaned.toUpperCase().padLeft(8, '0');
}

String normalizeStatusText(String raw) {
  final stripped = raw.trim();
  if (stripped.isEmpty) return '';
  final chunks = stripped.replaceAll(',', ' ').split(RegExp(r'\s+')).where((chunk) => chunk.isNotEmpty).toList();
  if (chunks.length > 1) return chunks.map((chunk) => normalizeFixedHex32(chunk) ?? '').join();
  final cleaned = cleanHexInput(raw);
  if (cleaned.isEmpty) return '';
  if (!hexDigitsPattern.hasMatch(cleaned)) throw BinFormatError('Hex values may only contain 0-9 and A-F.');
  if (cleaned.length <= 8) return cleaned.toUpperCase().padLeft(8, '0');
  if (cleaned.length % 8 != 0) throw BinFormatError('Scenario status values must be 8 hex character groups.');
  return cleaned.toUpperCase();
}

Object parseIntText(String raw) {
  final parsed = parsePythonInt(raw);
  if (parsed == null) throw BinFormatError('Integer fields must be decimal or 0x-prefixed hex.');
  return compactInt(parsed);
}

(int, Uint8List) encodeParameterBlock(BinDocument document, BinParameter parameter, String encoding) {
  final name = parameter.name;
  final type = parameter.typeName;
  final entries = document.entries;
  final present = <int>[
    for (var i = 0; i < entries.length; i++)
      if (entries[i].containsKey(name)) i,
  ];
  final body = BytesBuilder(copy: false);

  if (plainStringTypes.contains(type)) {
    if (present.isEmpty) return (0, Uint8List(0));
    for (final i in present) {
      body.add(encodeText(entries[i][name].toString(), encoding));
      body.addByte(0);
    }
    body.add(parameter.tailPadding);
    return (present.length, body.takeBytes());
  }

  if (tableParameterTypes.contains(type)) {
    if (present.isEmpty) return (0, Uint8List(0));
    final values = [for (final entry in entries) (entry[name] ?? '').toString()];
    final slots = <String, int>{};
    for (final value in values) {
      slots.putIfAbsent(value, () => slots.length);
    }
    if (slots.length > 256) throw BinFormatError("Parameter '$name' uses more than 256 table values.");
    for (final value in slots.keys) {
      body.add(encodeText(value, encoding));
      body.addByte(0);
    }
    for (final value in values) {
      body.addByte(slots[value]!);
    }
    body.add(parameter.tailPadding);
    return (slots.length, body.takeBytes());
  }

  if (indexParameterTypes.contains(type)) {
    if (present.isEmpty) return (0, Uint8List(0));
    var count = 0;
    for (final i in present) {
      final value = entries[i][name].toString();
      if (value.isEmpty) continue;
      if (i > 0xFFFF) throw BinFormatError("Parameter '$name' entry $i is past the 65535 index limit.");
      body.add([(i >> 8) & 0xFF, i & 0xFF]);
      body.add(encodeText(value, encoding));
      body.addByte(0);
      count++;
    }
    body.add(parameter.tailPadding);
    return (count, body.takeBytes());
  }

  if (type == 'special_scenariostatus') {
    if (present.isEmpty) return (0, Uint8List(0));
    for (final i in present) {
      final normalized = normalizeValueForWrite(type, entries[i][name]!, name, i) as String;
      if (normalized.isNotEmpty) body.add(hexToBytes(normalized));
      body.add([0xFF, 0xFF, 0xFF, 0xFF]);
    }
    return (present.length, body.takeBytes());
  }

  if (fixedHexTypes.contains(type)) {
    if (present.isEmpty) return (0, Uint8List(0));
    for (final i in present) {
      final normalized = normalizeValueForWrite(type, entries[i][name]!, name, i);
      if (normalized == null) throw BinFormatError('$name entry ${pad3(i)}: Hex value is empty.');
      body.add(hexToBytes(normalized as String));
    }
    return (present.length, body.takeBytes());
  }

  if (intParameterTypes.contains(type)) {
    if (present.isEmpty) return (0, Uint8List(0));
    for (final i in present) {
      final numeric = normalizeValueForWrite(type, entries[i][name]!, name, i);
      if (numeric == null) throw BinFormatError('$name entry ${pad3(i)}: Integer value is empty.');
      final word = maskU32(numeric);
      body.add([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF]);
    }
    return (present.length, body.takeBytes());
  }

  if (type == 'comment') return (0, Uint8List(0));

  throw BinFormatError("Unknown parameter type '$type'.");
}

Uint8List buildBinBytes(BinDocument document, String encoding) {
  final parameterCount = document.parameters.length;
  final header = Uint8List(binHeaderBaseSize + parameterRecordSize * parameterCount);
  header.setRange(0, 4, binMagic);
  writeU32(header, 4, parameterCount);
  writeU32(header, 8, document.entryCount);

  final chunks = <Uint8List>[];
  for (var index = 0; index < parameterCount; index++) {
    final parameter = document.parameters[index];
    final (count, body) = encodeParameterBlock(document, parameter, encoding);
    final nameBytes = encodeText(parameter.name, encoding);
    if (nameBytes.length > parameterNameSize) {
      throw BinFormatError("Parameter name '${parameter.name}' is too long for the BIN header.");
    }
    final recordStart = binHeaderBaseSize + index * parameterRecordSize;
    header.setRange(recordStart, recordStart + nameBytes.length, nameBytes);
    writeU32(header, recordStart + 48, parameter.typeIndex);
    writeU32(header, recordStart + 52, count);
    writeU32(header, recordStart + 56, body.length);
    chunks.add(body);
  }

  final out = BytesBuilder(copy: false)..add(header);
  for (final chunk in chunks) {
    out.add(chunk);
  }
  return out.takeBytes();
}
