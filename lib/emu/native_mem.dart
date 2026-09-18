import 'dart:convert';
import 'dart:ffi';

/// Minimal native-memory helpers without package:ffi.
///
/// The repo keeps native interop dependency-free (see the hand-rolled
/// UTF-8 helpers in lib/runtime); these cover what the desktop PCM sinks
/// need: allocation, C strings, and error-string decoding.
final Pointer<Void> Function(int) cMalloc = DynamicLibrary.process()
    .lookupFunction<Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)>('malloc');

final void Function(Pointer<Void>) cFree = DynamicLibrary.process()
    .lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');

Pointer<Uint8> mallocBytes(int bytes) {
  final ptr = cMalloc(bytes).cast<Uint8>();
  if (ptr.address == 0) throw StateError('Out of native memory');
  for (var i = 0; i < bytes; i++) {
    ptr[i] = 0;
  }
  return ptr;
}

void freeBytes(Pointer ptr) => cFree(ptr.cast());

Pointer<Uint8> toNativeUtf8(String s) {
  final encoded = utf8.encode(s);
  final ptr = mallocBytes(encoded.length + 1);
  for (var i = 0; i < encoded.length; i++) {
    ptr[i] = encoded[i];
  }
  ptr[encoded.length] = 0;
  return ptr;
}

String fromNativeUtf8(Pointer<Uint8> ptr, [int max = 512]) {
  if (ptr.address == 0) return '';
  final bytes = <int>[];
  for (var i = 0; i < max && ptr[i] != 0; i++) {
    bytes.add(ptr[i]);
  }
  return utf8.decode(bytes, allowMalformed: true);
}
