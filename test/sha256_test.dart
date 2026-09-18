import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/sha256.dart' as sha256;

void main() {
  test('FIPS 180-4 vectors', () {
    expect(sha256.sha256String(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(sha256.sha256String('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
        sha256.sha256String('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  });

  test('chunked feeding matches one-shot', () {
    final data = List<int>.generate(100000, (i) => i % 251);
    final oneShot = sha256.sha256Hex(data);
    final sink = sha256.Sha256Sink();
    for (var off = 0; off < data.length; off += 7) {
      final end = (off + 7 < data.length) ? off + 7 : data.length;
      sink.add(data.sublist(off, end));
    }
    expect(sink.hexDigest(), oneShot);
  });

  test('file hashing matches shell tooling', () async {
    final dir = await Directory.systemTemp.createTemp('ezcore_sha');
    try {
      final file = File('${dir.path}/sample.bin');
      await file.writeAsBytes(List<int>.generate(300000, (i) => (i * 31) % 256));
      final pure = await const DartHashVerifier().sha256File(file.path);
      final platform = await const PlatformHashVerifier().sha256File(file.path);
      expect(pure, hasLength(64));
      expect(platform.toLowerCase(), pure);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
