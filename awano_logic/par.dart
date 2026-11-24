import 'dart:convert'; import 'dart:io'; import 'dart:typed_data';

const parHeaderSize = 0x20;
const parNameSize = 0x40;
const parFolderEntrySize = 0x20;
const parFileEntrySize = 0x20;

class ParFolderEntry {
  final int folderCount, folderStart, fileCount, fileStart, attributes;
  const ParFolderEntry(this.folderCount, this.folderStart, this.fileCount, this.fileStart, this.attributes);
}

class ParFileEntry {
  final String name;
  final int compressionFlag, size, compressedSize, attributes, extendedOffset, timestamp, dataOffset;
  const ParFileEntry(this.name, this.compressionFlag, this.size, this.compressedSize, this.attributes, this.extendedOffset,
      this.timestamp, this.dataOffset);
}

bool hasMagic(List<int> data, String magic) {
  if (data.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (data[i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}

String sanitizePathSegment(String rawName, String fallback) {
  final safe = rawName.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').replaceAll(RegExp(r'[. ]+$'), '');
  return safe.isEmpty ? fallback : safe;
}

String joinPath(String base, String relative) => relative.isEmpty ? base : '$base${Platform.pathSeparator}$relative';

String decodeParName(Uint8List data) {
  final end = data.indexOf(0);
  return utf8.decode(Uint8List.sublistView(data, 0, end >= 0 ? end : data.length), allowMalformed: true);
}

bool isValidRange(int start, int length, int fileLength) => start >= 0 && length >= 0 && start + length <= fileLength;

int resolveTableOffset(int stored, int count, int entrySize, int nameTableEnd, int fileLength) {
  if (count == 0) return 0;
  if (isValidRange(stored, count * entrySize, fileLength)) return stored;
  final relative = nameTableEnd + stored;
  if (isValidRange(relative, count * entrySize, fileLength)) return relative;
  throw FormatException('PAR: Could not resolve table offset 0x${stored.toRadixString(16).toUpperCase()}.');
}

class ParArchive {
  final String sourcePath;
  final Endian endian;
  final int version;
  final List<String> folderNames;
  final List<String> fileNames;
  final List<ParFolderEntry> folders;
  final List<ParFileEntry> files;
  late final List<String?> folderPaths = List<String?>.filled(folderNames.length, null);
  late final List<int?> parentFolders = buildParentFolders();
  late final List<int?> fileParents = buildFileParents();

  ParArchive(this.sourcePath, this.endian, this.version, this.folderNames, this.fileNames, this.folders, this.files);

  int get folderCount => folderNames.length;
  int get fileCount => fileNames.length;

  static ParArchive read(RandomAccessFile file, String sourcePath) {
    final length = file.lengthSync();
    if (length < parHeaderSize) throw const FormatException('PAR archive is too small to contain a header.');
    file.setPositionSync(0);
    final header = file.readSync(parHeaderSize);
    if (!hasMagic(header, 'PARC')) throw const FormatException('PAR: Bad magic id.');
    final endian = header[5] == 1 ? Endian.big : Endian.little;
    final view = ByteData.sublistView(header);
    final version = view.getUint32(8, endian);
    final folderCount = view.getUint32(16, endian);
    final folderOffsetValue = view.getUint32(20, endian);
    final fileCount = view.getUint32(24, endian);
    final fileOffsetValue = view.getUint32(28, endian);

    final nameTableSize = (folderCount + fileCount) * parNameSize;
    final nameTableEnd = parHeaderSize + nameTableSize;
    if (nameTableEnd > length) throw const FormatException('PAR: Name table exceeds archive size.');

    final folderOffset = resolveTableOffset(folderOffsetValue, folderCount, parFolderEntrySize, nameTableEnd, length);
    final fileOffset = resolveTableOffset(fileOffsetValue, fileCount, parFileEntrySize, nameTableEnd, length);

    file.setPositionSync(parHeaderSize);
    final names = file.readSync(nameTableSize);
    String nameAt(int index) => decodeParName(Uint8List.sublistView(names, index * parNameSize, (index + 1) * parNameSize));
    final folderNames = List<String>.generate(folderCount, nameAt);
    final fileNames = List<String>.generate(fileCount, (index) => nameAt(folderCount + index));

    Uint8List readTable(int offset, int count, int size) {
      if (count == 0) return Uint8List(0);
      file.setPositionSync(offset);
      return file.readSync(count * size);
    }

    final folderTable = ByteData.sublistView(readTable(folderOffset, folderCount, parFolderEntrySize));
    final folders = List<ParFolderEntry>.generate(folderCount, (index) {
      final s = index * parFolderEntrySize;
      return ParFolderEntry(
        folderTable.getUint32(s, endian),
        folderTable.getUint32(s + 4, endian),
        folderTable.getUint32(s + 8, endian),
        folderTable.getUint32(s + 12, endian),
        folderTable.getInt32(s + 16, endian),
      );
    });

    final fileTable = ByteData.sublistView(readTable(fileOffset, fileCount, parFileEntrySize));
    final files = List<ParFileEntry>.generate(fileCount, (index) {
      final s = index * parFileEntrySize;
      final compressedSize = fileTable.getUint32(s + 8, endian);
      final baseOffset = fileTable.getUint32(s + 12, endian);
      final extendedOffset = fileTable.getUint32(s + 20, endian);
      final dataOffset = baseOffset + ((extendedOffset & 0x00FFFFFF) << 32);
      if (dataOffset + compressedSize > length) {
        throw FormatException('PAR: File entry ${fileNames[index]} points outside of the archive.');
      }
      return ParFileEntry(
        fileNames[index],
        fileTable.getUint32(s, endian),
        fileTable.getUint32(s + 4, endian),
        compressedSize,
        fileTable.getInt32(s + 16, endian),
        extendedOffset,
        fileTable.getUint64(s + 24, endian),
        dataOffset,
      );
    });

    return ParArchive(sourcePath, endian, version, folderNames, fileNames, folders, files);
  }

  List<int?> buildParentFolders() {
    final parents = List<int?>.filled(folders.length, null);
    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      final folder = folders[folderIndex];
      for (var child = folder.folderStart;
          child < folder.folderStart + folder.folderCount && child < folders.length;
          child++) {
        parents[child] ??= folderIndex;
      }
    }
    return parents;
  }

  List<int?> buildFileParents() {
    final parents = List<int?>.filled(files.length, null);
    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      final folder = folders[folderIndex];
      for (var fileIndex = folder.fileStart;
          fileIndex < folder.fileStart + folder.fileCount && fileIndex < files.length;
          fileIndex++) {
        parents[fileIndex] ??= folderIndex;
      }
    }
    return parents;
  }

  String folderPath(int folderIndex, Set<int> active) {
    final cached = folderPaths[folderIndex];
    if (cached != null) return cached;
    if (!active.add(folderIndex)) throw FormatException('PAR: Folder recursion detected in $sourcePath.');
    final rawName = folderNames[folderIndex].trim();
    final safeName = sanitizePathSegment(folderNames[folderIndex], 'folder_${folderIndex.toString().padLeft(3, '0')}');
    final parent = parentFolders[folderIndex];
    String path;
    if (parent == null || parent == folderIndex) {
      path = rawName.isEmpty || rawName == '.' || safeName == '.' ? '' : safeName;
    } else {
      final parentPath = folderPath(parent, active);
      path = parentPath.isEmpty ? safeName : joinPath(parentPath, safeName);
    }
    active.remove(folderIndex);
    folderPaths[folderIndex] = path;
    return path;
  }

  String relativeFilePath(int fileIndex) {
    final safeName = sanitizePathSegment(fileNames[fileIndex], 'file_${fileIndex.toString().padLeft(3, '0')}');
    final parent = fileParents[fileIndex];
    if (parent == null) return safeName;
    final path = folderPath(parent, <int>{});
    return path.isEmpty ? safeName : joinPath(path, safeName);
  }
}

Uint8List decompressSllz(Uint8List data) {
  if (!hasMagic(data, 'SLLZ')) throw const FormatException('SLLZ: Bad magic id.');
  final endian = data[4] == 0 ? Endian.little : Endian.big;
  final version = data[5];
  final view = ByteData.sublistView(data);
  final headerSize = view.getUint16(6, endian);
  final decompressedSize = view.getUint32(8, endian);
  final compressedSize = view.getUint32(12, endian);
  if (headerSize > data.length || compressedSize > data.length) {
    throw const FormatException('SLLZ: Header exceeds input size.');
  }
  final payload = Uint8List.sublistView(data, headerSize, compressedSize);
  if (version == 1) return decompressSllzV1(payload, decompressedSize);
  if (version == 2) return decompressSllzV2(payload, decompressedSize);
  throw FormatException('SLLZ: Unknown compression version $version.');
}

Uint8List decompressSllzV1(Uint8List input, int decompressedSize) {
  final output = Uint8List(decompressedSize);
  var inPos = 0;
  var outPos = 0;
  var flag = input[inPos++];
  var flagCount = 8;
  while (outPos < decompressedSize) {
    final copy = (flag & 0x80) == 0x80;
    flag = (flag << 1) & 0xFF;
    flagCount--;
    if (flagCount == 0) {
      flag = input[inPos++];
      flagCount = 8;
    }
    if (copy) {
      final copyFlags = input[inPos] | (input[inPos + 1] << 8);
      inPos += 2;
      final distance = 1 + (copyFlags >> 4);
      final count = 3 + (copyFlags & 0x0F);
      for (var i = 0; i < count; i++) {
        output[outPos] = output[outPos - distance];
        outPos++;
      }
    } else {
      output[outPos++] = input[inPos++];
    }
  }
  return output;
}

Uint8List decompressSllzV2(Uint8List input, int decompressedSize) {
  final out = BytesBuilder(copy: false);
  var inPos = 0;
  while (out.length < decompressedSize && inPos < input.length) {
    final chunkSize = (input[inPos] << 16) | (input[inPos + 1] << 8) | input[inPos + 2];
    final decompressedChunk = ((input[inPos + 3] << 8) | input[inPos + 4]) + 1;
    if ((chunkSize & 0x00800000) == 0) {
      final decoded = ZLibDecoder().convert(Uint8List.sublistView(input, inPos + 5, inPos + chunkSize));
      if (decoded.length != decompressedChunk) throw const FormatException('SLLZ: Wrong decompressed data.');
      out.add(decoded);
      inPos += chunkSize;
    } else {
      final raw = chunkSize & 0xFF7FFFFF;
      out.add(Uint8List.sublistView(input, inPos + 5, inPos + raw));
      inPos += raw;
    }
  }
  final result = out.takeBytes();
  if (result.length != decompressedSize) {
    throw FormatException('SLLZ: Expected $decompressedSize bytes after decompress, got ${result.length}.');
  }
  return result;
}

bool setTimestamp(File file, int seconds) {
  try {
    file.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal());
    return true;
  } catch (error) {
    return false;
  }
}

class ParUnpackResult {
  final String source, outputDir;
  final int folderCount, fileCount, extractedFiles, decompressedFiles, version;
  final List<String> nestedContainers;
  final String endianness;
  const ParUnpackResult(this.source, this.outputDir, this.folderCount, this.fileCount, this.extractedFiles,
      this.decompressedFiles, this.nestedContainers, this.version, this.endianness);
}

ParUnpackResult unpackPar(String sourcePath, String outputPath) {
  final source = File(sourcePath);
  if (!source.existsSync()) throw FileSystemException('PAR source does not exist.', sourcePath);
  final raf = source.openSync();
  try {
    final archive = ParArchive.read(raf, sourcePath);
    final outputDirectory = Directory(outputPath)..createSync(recursive: true);
    final created = <String>{outputDirectory.path};
    final nested = <String>[];
    var decompressed = 0;

    for (var index = 0; index < archive.files.length; index++) {
      final entry = archive.files[index];
      final outputFile = File(joinPath(outputDirectory.path, archive.relativeFilePath(index)));
      final parent = outputFile.parent;
      if (created.add(parent.path)) parent.createSync(recursive: true);

      raf.setPositionSync(entry.dataOffset);
      var data = raf.readSync(entry.compressedSize);
      if (hasMagic(data, 'SLLZ')) {
        data = decompressSllz(data);
        decompressed++;
      }
      if (entry.size > 0 && data.length != entry.size) {
        throw FormatException('Entry ${entry.name} expected ${entry.size} bytes after unpack, got ${data.length}.');
      }
      outputFile.writeAsBytesSync(data);
      if (hasMagic(data, 'PARC') || outputFile.path.toLowerCase().endsWith('.par')) nested.add(outputFile.absolute.path);
      setTimestamp(outputFile, entry.timestamp);
    }

    return ParUnpackResult(
      source.absolute.path,
      outputDirectory.absolute.path,
      archive.folderCount,
      archive.fileCount,
      archive.files.length,
      decompressed,
      nested,
      archive.version,
      archive.endian == Endian.big ? 'big' : 'little',
    );
  } finally {
    raf.closeSync();
  }
}
