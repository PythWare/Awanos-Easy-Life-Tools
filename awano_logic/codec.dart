import 'dart:convert'; import 'dart:ffi'; import 'dart:typed_data';
import 'native.dart';

const autoEncoding = 'auto';
const decodeCandidates = ['utf-8', 'cp932'];

const MB_ERR_INVALID_CHARS = 0x08;
const WC_NO_BEST_FIT_CHARS = 0x400;
const japaneseCodePage = 932;

final MultiByteToWideChar = kernel32.lookupFunction<
    Int32 Function(Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>, Int32),
    int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int)>('MultiByteToWideChar');
final WideCharToMultiByte = kernel32.lookupFunction<
    Int32 Function(Uint32, Uint32, Pointer<Uint16>, Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Pointer<Int32>),
    int Function(int, int, Pointer<Uint16>, int, Pointer<Uint8>, int, Pointer<Uint8>, Pointer<Int32>)>('WideCharToMultiByte');

class TextDecodeError implements Exception {
  final String message;
  TextDecodeError(this.message);
  @override
  String toString() => message;
}

class TextEncodeError implements Exception {
  final String message;
  TextEncodeError(this.message);
  @override
  String toString() => message;
}

bool isJapaneseEncoding(String encoding) => encoding == 'cp932' || encoding == 'shift_jis';

String encodingLabel(String encoding) => encoding.toUpperCase();

String decodeText(List<int> bytes, String encoding) {
  if (bytes.isEmpty) return '';
  if (encoding == 'utf-8') {
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw TextDecodeError("'utf-8' codec cant decode the data: ${error.message}");
    }
  }
  if (!isJapaneseEncoding(encoding)) throw TextDecodeError('Unknown encoding $encoding');
  return scoped((a) {
    final source = nativeBytes(bytes, a);
    final needed = MultiByteToWideChar(japaneseCodePage, MB_ERR_INVALID_CHARS, source, bytes.length, nullptr, 0);
    if (needed <= 0) throw TextDecodeError("'$encoding' codec cant decode the data");
    final target = a<Uint16>(needed);
    final written = MultiByteToWideChar(japaneseCodePage, MB_ERR_INVALID_CHARS, source, bytes.length, target, needed);
    if (written <= 0) throw TextDecodeError("'$encoding' codec cant decode the data");
    return String.fromCharCodes(target.asTypedList(written));
  });
}

Uint8List encodeText(String text, String encoding) {
  if (text.isEmpty) return Uint8List(0);
  if (encoding == 'utf-8') {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < text.length) {
          final next = text.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            i++;
            continue;
          }
        }
        throw TextEncodeError("'utf-8' codec cant encode a lone surrogate at position $i");
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw TextEncodeError("'utf-8' codec cant encode a lone surrogate at position $i");
      }
    }
    return Uint8List.fromList(utf8.encode(text));
  }
  if (!isJapaneseEncoding(encoding)) throw TextEncodeError('Unknown encoding $encoding');
  return scoped((a) {
    final source = wstr(text, a);
    final usedDefault = a<Int32>();
    final needed =
        WideCharToMultiByte(japaneseCodePage, WC_NO_BEST_FIT_CHARS, source, text.length, nullptr, 0, nullptr, usedDefault);
    if (needed <= 0 || usedDefault.value != 0) {
      throw TextEncodeError("'$encoding' codec cant encode some characters in this text");
    }
    final target = a<Uint8>(needed);
    final written = WideCharToMultiByte(
        japaneseCodePage, WC_NO_BEST_FIT_CHARS, source, text.length, target, needed, nullptr, usedDefault);
    if (written <= 0 || usedDefault.value != 0) {
      throw TextEncodeError("'$encoding' codec cant encode some characters in this text");
    }
    return copyBytes(target, written);
  });
}

bool canEncode(String text, String encoding) {
  try {
    encodeText(text, encoding);
    return true;
  } on TextEncodeError {
    return false;
  }
}

int indexOfZero(Uint8List data, int start) {
  for (var i = start; i < data.length; i++) {
    if (data[i] == 0) return i;
  }
  return -1;
}

int readU16(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];

int readU32(Uint8List data, int offset) =>
    (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];

void writeU16(Uint8List data, int offset, int value) {
  data[offset] = (value >> 8) & 0xFF;
  data[offset + 1] = value & 0xFF;
}

void writeU32(Uint8List data, int offset, int value) {
  data[offset] = (value >> 24) & 0xFF;
  data[offset + 1] = (value >> 16) & 0xFF;
  data[offset + 2] = (value >> 8) & 0xFF;
  data[offset + 3] = value & 0xFF;
}

String hexUpper(Uint8List data) {
  final out = StringBuffer();
  for (final b in data) {
    out.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return out.toString();
}

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String pad3(int n) => n.toString().padLeft(3, '0');
String pad4(int n) => n.toString().padLeft(4, '0');

final decimalIntPattern = RegExp(r'^[+-]?[0-9](_?[0-9])*$');
final hexIntPattern = RegExp(r'^0[xX](_?[0-9a-fA-F])+$');

BigInt? parsePythonInt(String text) {
  if (hexIntPattern.hasMatch(text)) {
    return BigInt.parse(text.substring(2).replaceAll('_', ''), radix: 16);
  }
  if (decimalIntPattern.hasMatch(text)) {
    return BigInt.parse(text.replaceAll('_', ''));
  }
  return null;
}

Object compactInt(BigInt value) => value.isValidInt ? value.toInt() : value;

int maskU32(Object value) {
  if (value is int) return value & 0xFFFFFFFF;
  if (value is BigInt) return (value & BigInt.from(0xFFFFFFFF)).toInt();
  throw ArgumentError('not an integer: $value');
}
