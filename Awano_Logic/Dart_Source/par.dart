import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int headerSize = 0x20;
const int nameSize = 0x40;
const int folderEntrySize = 0x20;
const int fileEntrySize = 0x20;

void main(List<String> args) {
  if (args.length != 3 || args[0] != 'unpack') {
    stderr.writeln('Usage: par.dart unpack <source_par> <output_dir>');
    exitCode = 64;
    return;
  }

  final sourceFile = File(args[1]);
  final outputDirectory = Directory(args[2]);

  try {
    final result = unpackPar(sourceFile, outputDirectory);
    stdout.writeln(jsonEncode(result));
  } catch (error) {
    stderr.writeln(error.toString());
    exitCode = 1;
  }
}

Map<String, Object> unpackPar(File sourceFile, Directory outputDirectory) {
  if (!sourceFile.existsSync()) {
    throw FileSystemException('PAR source does not exist.', sourceFile.path);
  }

  final archiveBytes = sourceFile.readAsBytesSync();
  final archive = ParsedParArchive.parse(archiveBytes, sourceFile.path);

  outputDirectory.createSync(recursive: true);

  final nestedContainers = <String>[];
  var decompressedFiles = 0;

  for (var fileIndex = 0; fileIndex < archive.files.length; fileIndex++) {
    final fileEntry = archive.files[fileIndex];
    final relativePath = archive.relativeFilePath(fileIndex);
    final outputPath = joinPath(outputDirectory.path, relativePath);
    final outputFile = File(outputPath);
    outputFile.parent.createSync(recursive: true);

    var fileData = fileEntry.payload;
    if (hasMagic(fileData, 'SLLZ')) {
      fileData = decompressSllz(fileData);
      decompressedFiles += 1;
    }

    if (fileEntry.size > 0 && fileData.length != fileEntry.size) {
      throw FormatException(
        'Entry ${fileEntry.name} expected ${fileEntry.size} bytes after unpack, got ${fileData.length}.',
      );
    }

    outputFile.writeAsBytesSync(fileData, flush: false);

    try {
      outputFile.setLastModifiedSync(
        DateTime.fromMillisecondsSinceEpoch(fileEntry.timestamp * 1000, isUtc: true).toLocal(),
      );
    } catch (_) {
      // Some timestamps are invalid or unsupported on the local filesystem.
    }

    if (hasMagic(fileData, 'PARC')) {
      nestedContainers.add(outputFile.absolute.path);
    }
  }

  return <String, Object>{
    'source': sourceFile.absolute.path,
    'output_dir': outputDirectory.absolute.path,
    'folder_count': archive.folderCount,
    'file_count': archive.fileCount,
    'extracted_files': archive.files.length,
    'decompressed_files': decompressedFiles,
    'nested_containers': nestedContainers,
    'version': archive.version,
    'endianness': archive.endian == Endian.big ? 'big' : 'little',
  };
}

Uint8List decompressSllz(Uint8List data) {
  if (!hasMagic(data, 'SLLZ')) {
    throw const FormatException('SLLZ: Bad magic id.');
  }

  final endiannessByte = data[4];
  final version = data[5];
  final endian = endiannessByte == 0 ? Endian.little : Endian.big;
  final view = ByteData.sublistView(data);
  final headerSize = view.getUint16(6, endian);
  final decompressedSize = view.getUint32(8, endian);
  final compressedSize = view.getUint32(12, endian);

  if (headerSize > data.length || compressedSize > data.length) {
    throw const FormatException('SLLZ: Header exceeds input size.');
  }

  final payload = Uint8List.sublistView(data, headerSize, compressedSize);
  if (version == 1) {
    return decompressSllzV1(payload, decompressedSize);
  }

  if (version == 2) {
    return decompressSllzV2(payload, decompressedSize);
  }

  throw FormatException('SLLZ: Unknown compression version $version.');
}

Uint8List decompressSllzV1(Uint8List inputData, int decompressedSize) {
  final outputData = Uint8List(decompressedSize);

  var inputPosition = 0;
  var outputPosition = 0;

  var flag = inputData[inputPosition];
  inputPosition += 1;
  var flagCount = 8;

  while (outputPosition < decompressedSize) {
    if ((flag & 0x80) == 0x80) {
      flag = (flag << 1) & 0xFF;
      flagCount -= 1;
      if (flagCount == 0) {
        flag = inputData[inputPosition];
        inputPosition += 1;
        flagCount = 8;
      }

      final copyFlags = inputData[inputPosition] | (inputData[inputPosition + 1] << 8);
      inputPosition += 2;

      final copyDistance = 1 + (copyFlags >> 4);
      final copyCount = 3 + (copyFlags & 0x0F);

      for (var i = 0; i < copyCount; i++) {
        outputData[outputPosition] = outputData[outputPosition - copyDistance];
        outputPosition += 1;
      }
    } else {
      flag = (flag << 1) & 0xFF;
      flagCount -= 1;
      if (flagCount == 0) {
        flag = inputData[inputPosition];
        inputPosition += 1;
        flagCount = 8;
      }

      outputData[outputPosition] = inputData[inputPosition];
      inputPosition += 1;
      outputPosition += 1;
    }
  }

  return outputData;
}

Uint8List decompressSllzV2(Uint8List inputData, int decompressedSize) {
  final outputBuffer = BytesBuilder(copy: false);
  var inputPosition = 0;

  while (outputBuffer.length < decompressedSize && inputPosition < inputData.length) {
    final compressedChunkSize =
        (inputData[inputPosition] << 16) | (inputData[inputPosition + 1] << 8) | inputData[inputPosition + 2];
    final chunkSizeFlagged = compressedChunkSize;
    final decompressedChunkSize =
        (((inputData[inputPosition + 3] << 8) | inputData[inputPosition + 4])) + 1;

    final isCompressed = (chunkSizeFlagged & 0x00800000) == 0;
    if (isCompressed) {
      final zlibData = Uint8List.sublistView(
        inputData,
        inputPosition + 5,
        inputPosition + compressedChunkSize,
      );
      final decoded = ZLibDecoder().convert(zlibData);
      if (decoded.length != decompressedChunkSize) {
        throw const FormatException('SLLZ: Wrong decompressed data.');
      }
      outputBuffer.add(decoded);
      inputPosition += compressedChunkSize;
    } else {
      final rawChunkSize = chunkSizeFlagged & 0xFF7FFFFF;
      final rawData = Uint8List.sublistView(
        inputData,
        inputPosition + 5,
        inputPosition + rawChunkSize,
      );
      outputBuffer.add(rawData);
      inputPosition += rawChunkSize;
    }
  }

  final outputData = outputBuffer.takeBytes();
  if (outputData.length != decompressedSize) {
    throw FormatException(
      'SLLZ: Expected $decompressedSize bytes after decompress, got ${outputData.length}.',
    );
  }

  return outputData;
}

bool hasMagic(List<int> data, String magicText) {
  final magic = ascii.encode(magicText);
  if (data.length < magic.length) {
    return false;
  }

  for (var index = 0; index < magic.length; index++) {
    if (data[index] != magic[index]) {
      return false;
    }
  }

  return true;
}

String joinPath(String base, String relative) {
  if (relative.isEmpty) {
    return base;
  }

  return '$base${Platform.pathSeparator}$relative';
}

String sanitizePathSegment(String rawName, {String fallback = 'entry'}) {
  final trimmed = rawName.trim();
  final safe = trimmed
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');

  return safe.isEmpty ? fallback : safe;
}

String decodeName(Uint8List data) {
  final endIndex = data.indexOf(0);
  final usedLength = endIndex >= 0 ? endIndex : data.length;
  final nameBytes = Uint8List.sublistView(data, 0, usedLength);
  return utf8.decode(nameBytes, allowMalformed: true);
}

class ParsedParArchive {
  ParsedParArchive({
    required this.sourcePath,
    required this.endian,
    required this.version,
    required this.folderNames,
    required this.fileNames,
    required this.folders,
    required this.files,
  }) : folderRelativePaths = List<String?>.filled(folderNames.length, null);

  final String sourcePath;
  final Endian endian;
  final int version;
  final List<String> folderNames;
  final List<String> fileNames;
  final List<ParFolderEntry> folders;
  final List<ParFileEntry> files;
  final List<String?> folderRelativePaths;

  int get folderCount => folderNames.length;
  int get fileCount => fileNames.length;

  factory ParsedParArchive.parse(Uint8List data, String sourcePath) {
    if (data.length < headerSize) {
      throw const FormatException('PAR archive is too small to contain a header.');
    }

    if (!hasMagic(data, 'PARC')) {
      throw const FormatException('PAR: Bad magic id.');
    }

    final endian = data[5] == 1 ? Endian.big : Endian.little;
    final view = ByteData.sublistView(data);

    final version = view.getUint32(8, endian);
    final folderCount = view.getUint32(16, endian);
    final folderOffsetValue = view.getUint32(20, endian);
    final fileCount = view.getUint32(24, endian);
    final fileOffsetValue = view.getUint32(28, endian);

    final nameTableStart = headerSize;
    final nameTableSize = (folderCount + fileCount) * nameSize;
    final nameTableEnd = nameTableStart + nameTableSize;
    if (nameTableEnd > data.length) {
      throw const FormatException('PAR: Name table exceeds archive size.');
    }

    final folderOffset = resolveTableOffset(
      folderOffsetValue,
      folderCount,
      folderEntrySize,
      nameTableEnd,
      data.length,
    );
    final fileOffset = resolveTableOffset(
      fileOffsetValue,
      fileCount,
      fileEntrySize,
      nameTableEnd,
      data.length,
    );

    final folderNames = List<String>.generate(folderCount, (index) {
      final start = nameTableStart + (index * nameSize);
      return decodeName(Uint8List.sublistView(data, start, start + nameSize));
    });

    final fileNames = List<String>.generate(fileCount, (index) {
      final start = nameTableStart + ((folderCount + index) * nameSize);
      return decodeName(Uint8List.sublistView(data, start, start + nameSize));
    });

    final folders = List<ParFolderEntry>.generate(folderCount, (index) {
      final start = folderOffset + (index * folderEntrySize);
      return ParFolderEntry(
        folderCount: view.getUint32(start + 0x00, endian),
        folderStart: view.getUint32(start + 0x04, endian),
        fileCount: view.getUint32(start + 0x08, endian),
        fileStart: view.getUint32(start + 0x0C, endian),
        attributes: view.getInt32(start + 0x10, endian),
      );
    });

    final files = List<ParFileEntry>.generate(fileCount, (index) {
      final start = fileOffset + (index * fileEntrySize);
      final compressionFlag = view.getUint32(start + 0x00, endian);
      final size = view.getUint32(start + 0x04, endian);
      final compressedSize = view.getUint32(start + 0x08, endian);
      final baseOffset = view.getUint32(start + 0x0C, endian);
      final attributes = view.getInt32(start + 0x10, endian);
      final extendedOffset = view.getUint32(start + 0x14, endian);
      final timestamp = view.getUint64(start + 0x18, endian);

      final dataOffset = baseOffset + ((extendedOffset & 0x00FFFFFF) << 32);
      final payloadEnd = dataOffset + compressedSize;
      if (payloadEnd > data.length) {
        throw FormatException(
          'PAR: File entry ${fileNames[index]} points outside of the archive.',
        );
      }

      return ParFileEntry(
        name: fileNames[index],
        compressionFlag: compressionFlag,
        size: size,
        compressedSize: compressedSize,
        attributes: attributes,
        extendedOffset: extendedOffset,
        timestamp: timestamp,
        payload: Uint8List.sublistView(data, dataOffset, payloadEnd),
      );
    });

    return ParsedParArchive(
      sourcePath: sourcePath,
      endian: endian,
      version: version,
      folderNames: folderNames,
      fileNames: fileNames,
      folders: folders,
      files: files,
    );
  }

  String relativeFilePath(int fileIndex) {
    final parentFolders = buildParentFolderMap();
    final fileParents = buildParentFileMap();
    final parentFolderIndex = fileParents[fileIndex];
    final safeName = sanitizePathSegment(
      fileNames[fileIndex],
      fallback: 'file_${fileIndex.toString().padLeft(3, '0')}',
    );

    if (parentFolderIndex == null) {
      return safeName;
    }

    final folderPath = buildFolderRelativePath(parentFolderIndex, parentFolders, <int>{});
    if (folderPath.isEmpty) {
      return safeName;
    }

    return joinPath(folderPath, safeName);
  }

  List<int?> buildParentFolderMap() {
    final parents = List<int?>.filled(folders.length, null);

    for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
      final folder = folders[folderIndex];
      for (var childIndex = folder.folderStart;
          childIndex < folder.folderStart + folder.folderCount && childIndex < folders.length;
          childIndex++) {
        parents[childIndex] ??= folderIndex;
      }
    }

    return parents;
  }

  List<int?> buildParentFileMap() {
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

  String buildFolderRelativePath(int folderIndex, List<int?> parents, Set<int> active) {
    final cached = folderRelativePaths[folderIndex];
    if (cached != null) {
      return cached;
    }

    if (!active.add(folderIndex)) {
      throw FormatException('PAR: Folder recursion detected in $sourcePath.');
    }

    final rawName = folderNames[folderIndex].trim();
    final safeName = sanitizePathSegment(
      folderNames[folderIndex],
      fallback: 'folder_${folderIndex.toString().padLeft(3, '0')}',
    );
    final parentIndex = parents[folderIndex];

    String relativePath;
    if (parentIndex == null || parentIndex == folderIndex) {
      relativePath = rawName.isEmpty || rawName == '.' || safeName == '.' ? '' : safeName;
    } else {
      final parentPath = buildFolderRelativePath(parentIndex, parents, active);
      relativePath = parentPath.isEmpty ? safeName : joinPath(parentPath, safeName);
    }

    active.remove(folderIndex);
    folderRelativePaths[folderIndex] = relativePath;
    return relativePath;
  }
}

int resolveTableOffset(int storedOffset, int count, int entrySize, int nameTableEnd, int fileLength) {
  if (count == 0) {
    return 0;
  }

  final absoluteCandidate = storedOffset;
  if (isValidRange(absoluteCandidate, count * entrySize, fileLength)) {
    return absoluteCandidate;
  }

  final relativeCandidate = nameTableEnd + storedOffset;
  if (isValidRange(relativeCandidate, count * entrySize, fileLength)) {
    return relativeCandidate;
  }

  throw FormatException(
    'PAR: Could not resolve table offset 0x${storedOffset.toRadixString(16).toUpperCase()}.',
  );
}

bool isValidRange(int start, int length, int fileLength) {
  return start >= 0 && length >= 0 && start + length <= fileLength;
}

class ParFolderEntry {
  const ParFolderEntry({
    required this.folderCount,
    required this.folderStart,
    required this.fileCount,
    required this.fileStart,
    required this.attributes,
  });

  final int folderCount;
  final int folderStart;
  final int fileCount;
  final int fileStart;
  final int attributes;
}

class ParFileEntry {
  const ParFileEntry({
    required this.name,
    required this.compressionFlag,
    required this.size,
    required this.compressedSize,
    required this.attributes,
    required this.extendedOffset,
    required this.timestamp,
    required this.payload,
  });

  final String name;
  final int compressionFlag;
  final int size;
  final int compressedSize;
  final int attributes;
  final int extendedOffset;
  final int timestamp;
  final Uint8List payload;
}
