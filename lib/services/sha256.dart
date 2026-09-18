import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Pure-Dart SHA-256 (FIPS 180-4). Zero dependencies.
///
/// Exists because mobile platforms have no shell: iOS forbids `Process`,
/// so content hashing and core-pin verification must not depend on
/// `shasum`/`sha256sum`/`certutil` there. Desktop callers prefer native
/// tools for speed and use this as the fallback (see [HashVerifier]).
int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

const _k = [
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

/// Digests [bytes] and returns the 32-byte SHA-256 hash.
Uint8List sha256Bytes(List<int> bytes) {
  final sink = Sha256Sink();
  sink.add(bytes);
  return sink.close();
}

/// Lowercase hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) =>
    sha256Bytes(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Lowercase hex SHA-256 of the file at [path], streamed in 1 MiB chunks
/// so multi-hundred-MB dumps never sit fully in memory.
Future<String> sha256File(String path) async {
  final sink = Sha256Sink();
  final raf = await File(path).open();
  try {
    const chunk = 1 << 20;
    while (true) {
      final bytes = await raf.read(chunk);
      if (bytes.isEmpty) break;
      sink.add(bytes);
    }
  } finally {
    await raf.close();
  }
  return sink.hexDigest();
}

/// UTF-8 convenience for golden tests.
String sha256String(String input) => sha256Hex(utf8.encode(input));

/// Incremental SHA-256 sink: feed arbitrary chunks, then [close].
/// Operates on a [Uint8List] cursor (no per-block list surgery) to stay
/// usable in debug/JIT as well as release builds.
class Sha256Sink {
  int _h0 = 0x6a09e667;
  int _h1 = 0xbb67ae85;
  int _h2 = 0x3c6ef372;
  int _h3 = 0xa54ff53a;
  int _h4 = 0x510e527f;
  int _h5 = 0x9b05688c;
  int _h6 = 0x1f83d9ab;
  int _h7 = 0x5be0cd19;
  final _pending = Uint8List(128);
  int _pendingLength = 0;
  int _length = 0;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) throw StateError('Sha256Sink already closed');
    var off = 0;
    var remaining = bytes.length;
    _length += remaining;
    // Fill the pending buffer to a full block first.
    if (_pendingLength > 0) {
      final take = 64 - _pendingLength < remaining
          ? 64 - _pendingLength
          : remaining;
      _pending.setRange(_pendingLength, _pendingLength + take, bytes, off);
      _pendingLength += take;
      off += take;
      remaining -= take;
      if (_pendingLength == 64) {
        _compressBlock(_pending, 0);
        _pendingLength = 0;
      }
    }
    // Whole blocks straight from the input.
    while (remaining >= 64) {
      if (bytes is Uint8List) {
        _compressBlock(bytes, off);
      } else {
        _pending.setRange(0, 64, bytes, off);
        _compressBlock(_pending, 0);
      }
      off += 64;
      remaining -= 64;
    }
    // Tail.
    if (remaining > 0) {
      _pending.setRange(0, remaining, bytes, off);
      _pendingLength = remaining;
    }
  }

  Uint8List close() {
    if (_closed) throw StateError('Sha256Sink already closed');
    _closed = true;
    final ml = _length * 8;
    final total = _pendingLength + 1 + 8;
    final paddedLen = ((total + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, _pendingLength, _pending);
    padded[_pendingLength] = 0x80;
    final lenView = ByteData.sublistView(padded, paddedLen - 8, paddedLen);
    // setUint64 may not exist on older SDKs; compose manually.
    lenView.setUint32(0, (ml ~/ 0x100000000) & 0xFFFFFFFF);
    lenView.setUint32(4, ml & 0xFFFFFFFF);
    for (var off = 0; off < paddedLen; off += 64) {
      _compressBlock(padded, off);
    }
    final out = ByteData(32);
    out.setUint32(0, _h0);
    out.setUint32(4, _h1);
    out.setUint32(8, _h2);
    out.setUint32(12, _h3);
    out.setUint32(16, _h4);
    out.setUint32(20, _h5);
    out.setUint32(24, _h6);
    out.setUint32(28, _h7);
    return out.buffer.asUint8List();
  }

  String hexDigest() =>
      close().map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  void _compressBlock(List<int> msg, int off) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] =
          (msg[off + i * 4] << 24) |
          (msg[off + i * 4 + 1] << 16) |
          (msg[off + i * 4 + 2] << 8) |
          msg[off + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
    }
    var a = _h0, b = _h1, c = _h2, d = _h3;
    var e = _h4, f = _h5, g = _h6, h = _h7;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xFFFFFFFF;
    }
    _h0 = (_h0 + a) & 0xFFFFFFFF;
    _h1 = (_h1 + b) & 0xFFFFFFFF;
    _h2 = (_h2 + c) & 0xFFFFFFFF;
    _h3 = (_h3 + d) & 0xFFFFFFFF;
    _h4 = (_h4 + e) & 0xFFFFFFFF;
    _h5 = (_h5 + f) & 0xFFFFFFFF;
    _h6 = (_h6 + g) & 0xFFFFFFFF;
    _h7 = (_h7 + h) & 0xFFFFFFFF;
  }
}
