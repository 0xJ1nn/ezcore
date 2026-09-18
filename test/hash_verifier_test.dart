import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/hash_verifier.dart';

void main() {
  group('PlatformHashVerifier', () {
    test('computes SHA-256 of a known file', () async {
      final tmp = await Directory.systemTemp.createTemp('ezcore_hash');
      try {
        final file = File('${tmp.path}/sample.txt');
        await file.writeAsString('hello world');
        const verifier = PlatformHashVerifier();
        final hash = await verifier.sha256File(file.path);
        expect(hash.length, 64);
        expect(RegExp(r'^[0-9a-fA-F]+$').hasMatch(hash), isTrue);

      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
