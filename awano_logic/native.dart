import 'dart:ffi'; import 'dart:typed_data';

final kernel32 = DynamicLibrary.open('kernel32.dll');

final GetProcessHeap = kernel32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap', isLeaf: true);
final HeapAlloc = kernel32
    .lookupFunction<Pointer Function(IntPtr, Uint32, IntPtr), Pointer Function(int, int, int)>('HeapAlloc', isLeaf: true);
final HeapFree =
    kernel32.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer), int Function(int, int, Pointer)>('HeapFree', isLeaf: true);
final int heapHandle = GetProcessHeap();

const HEAP_ZERO_MEMORY = 0x08;

final class NativeHeap implements Allocator {
  const NativeHeap();

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = HeapAlloc(heapHandle, HEAP_ZERO_MEMORY, byteCount < 1 ? 1 : byteCount);
    if (p.address == 0) throw StateError('out of native memory ($byteCount bytes)');
    return p.cast<T>();
  }

  @override
  void free(Pointer pointer) {
    if (pointer.address != 0) HeapFree(heapHandle, 0, pointer);
  }
}

const heap = NativeHeap();

Pointer<Uint8> allocRaw(int bytes) {
  final p = HeapAlloc(heapHandle, 0, bytes < 1 ? 1 : bytes);
  if (p.address == 0) throw StateError('out of native memory ($bytes bytes)');
  return p.cast<Uint8>();
}

final class Arena implements Allocator {
  final owned = <Pointer>[];

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final p = heap.allocate<T>(byteCount);
    owned.add(p);
    return p;
  }

  @override
  void free(Pointer pointer) {}

  void releaseAll() {
    for (final p in owned) {
      heap.free(p);
    }
    owned.clear();
  }
}

R scoped<R>(R Function(Arena a) body) {
  final arena = Arena();
  try {
    return body(arena);
  } finally {
    arena.releaseAll();
  }
}

Pointer<Uint16> wstr(String s, [Allocator alloc = heap]) {
  final p = alloc<Uint16>(s.length + 1);
  final view = p.asTypedList(s.length + 1);
  view.setAll(0, s.codeUnits);
  view[s.length] = 0;
  return p;
}

String fromWstr(Pointer<Uint16> p, [int maxLength = 1 << 20]) {
  if (p.address == 0) return '';
  var n = 0;
  while (n < maxLength && (p + n).value != 0) {
    n++;
  }
  return String.fromCharCodes(p.asTypedList(n));
}

Pointer<Uint8> nativeBytes(List<int> bytes, Allocator alloc) {
  final p = alloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) p.asTypedList(bytes.length).setAll(0, bytes);
  return p;
}

Uint8List copyBytes(Pointer<Uint8> p, int length) => Uint8List.fromList(p.asTypedList(length));
