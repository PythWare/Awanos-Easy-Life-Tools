import 'dart:typed_data';
import 'codec.dart';

const stringTableHeaderSize = 8;
const groupRecordSize = 8;
const pointerSize = 4;
const entryPreviewLimit = 60;
const fieldPreviewLimit = 160;

class StringTableFormatError implements Exception {
  final String message;
  StringTableFormatError(this.message);
  @override
  String toString() => message;
}

class StringTableDocument {
  List<List<String?>> groups;
  int tableOffset;
  Uint8List tailPadding;
  String encoding;
  String? filePath;

  StringTableDocument(this.groups, this.tableOffset, this.tailPadding, this.encoding, this.filePath);

  int get entryCount => groups.length;
  int get stringCount => groups.fold(0, (sum, group) => sum + group.length);

  String entryLabel(int entryIndex) {
    final preview = groups[entryIndex].firstWhere((value) => value != null && value.isNotEmpty, orElse: () => '') ?? '';
    return '${pad4(entryIndex)} ${previewText(preview, entryPreviewLimit)}';
  }

  String fieldLabel(int entryIndex, int stringIndex) {
    final value = groups[entryIndex][stringIndex];
    return '${pad3(stringIndex)} ${value == null ? '(null)' : previewText(value, fieldPreviewLimit)}';
  }

  String? getValue(int entryIndex, int stringIndex) => groups[entryIndex][stringIndex];

  void setValue(int entryIndex, int stringIndex, String? value) {
    final group = groups[entryIndex];
    if (value == null || (group[stringIndex] == null && value.isEmpty)) {
      group[stringIndex] = null;
      return;
    }
    group[stringIndex] = value;
  }

  Uint8List toBytes([String? encodingOverride]) => buildStringTableBytes(this, encodingOverride ?? encoding);
}

StringTableDocument parseStringTableBytes(Uint8List data, String encoding, [String? filePath]) {
  if (encoding == autoEncoding) {
    for (final candidate in decodeCandidates) {
      try {
        return parseStringTableBytes(data, candidate, filePath);
      } on TextDecodeError {
        continue;
      }
    }
    throw StringTableFormatError('Failed to decode string table with UTF-8 or CP932.');
  }

  if (data.length < stringTableHeaderSize) throw StringTableFormatError('String table is too small to contain a header.');
  final groupCount = readU32(data, 0);
  final tableOffset = readU32(data, 4);
  final tableEnd = tableOffset + groupCount * groupRecordSize;
  if (tableOffset < stringTableHeaderSize || tableEnd > data.length) {
    throw StringTableFormatError('Group table doesnt fit inside the file.');
  }

  final groups = <List<String?>>[];
  var contentEnd = tableEnd;

  for (var groupIndex = 0; groupIndex < groupCount; groupIndex++) {
    final record = tableOffset + groupIndex * groupRecordSize;
    final stringCount = readU32(data, record);
    final pointerOffset = readU32(data, record + 4);
    final pointerEnd = pointerOffset + stringCount * pointerSize;
    if (stringCount > 0 && (pointerOffset < tableEnd || pointerEnd > data.length)) {
      throw StringTableFormatError('Group ${pad4(groupIndex)} points outside the file.');
    }
    if (pointerEnd > contentEnd) contentEnd = pointerEnd;

    final group = <String?>[];
    for (var stringIndex = 0; stringIndex < stringCount; stringIndex++) {
      final stringOffset = readU32(data, pointerOffset + stringIndex * pointerSize);
      if (stringOffset == 0) {
        group.add(null);
        continue;
      }
      if (stringOffset < tableEnd || stringOffset >= data.length) {
        throw StringTableFormatError('Group ${pad4(groupIndex)} string ${pad3(stringIndex)} points outside the file.');
      }
      final stringEnd = indexOfZero(data, stringOffset);
      if (stringEnd == -1) {
        throw StringTableFormatError('Group ${pad4(groupIndex)} string ${pad3(stringIndex)} is unterminated.');
      }
      group.add(decodeText(Uint8List.sublistView(data, stringOffset, stringEnd), encoding));
      if (stringEnd + 1 > contentEnd) contentEnd = stringEnd + 1;
    }
    groups.add(group);
  }

  final tail = contentEnd < data.length ? Uint8List.fromList(Uint8List.sublistView(data, contentEnd)) : Uint8List(0);
  return StringTableDocument(groups, tableOffset, tail, encoding, filePath);
}

Uint8List buildStringTableBytes(StringTableDocument document, String encoding) {
  final groupCount = document.groups.length;
  final tableEnd = document.tableOffset + groupCount * groupRecordSize;
  final stringsStart = tableEnd + document.stringCount * pointerSize;

  final head = Uint8List(stringsStart);
  writeU32(head, 0, groupCount);
  writeU32(head, 4, document.tableOffset);

  final strings = BytesBuilder(copy: false);
  var pointerOffset = tableEnd;
  for (var groupIndex = 0; groupIndex < groupCount; groupIndex++) {
    final group = document.groups[groupIndex];
    writeU32(head, document.tableOffset + groupIndex * groupRecordSize, group.length);
    writeU32(head, document.tableOffset + groupIndex * groupRecordSize + 4, pointerOffset);
    for (final value in group) {
      if (value != null) {
        writeU32(head, pointerOffset, stringsStart + strings.length);
        strings.add(encodeText(value, encoding));
        strings.addByte(0);
      }
      pointerOffset += pointerSize;
    }
  }

  return (BytesBuilder(copy: false)
        ..add(head)
        ..add(strings.takeBytes())
        ..add(document.tailPadding))
      .takeBytes();
}

String formatStringTableValueForEditor(String? value) => value ?? '';

String previewText(String value, [int limit = 40]) {
  final flattened = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join(' ');
  return flattened.length <= limit ? flattened : '${flattened.substring(0, limit - 3)}...';
}
