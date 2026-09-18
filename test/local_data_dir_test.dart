import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/local_data_dir.dart';

/// A test double for [LocalDataDirProvider] that uses a temp directory.
class FakeLocalDataDirProvider implements LocalDataDirProvider {
  FakeLocalDataDirProvider(this.dir);
  final Directory dir;

  @override
  Future<Directory> localDataDir() async => dir;

  @override
  String localDataDirPath() => dir.path;
}

void main() {
  group('PlatformLocalDataDirProvider', () {
    test('creates and returns a directory on the host', () async {
      final tmp = await Directory.systemTemp.createTemp('ezcore_pfdir');
      try {
        final provider = PlatformLocalDataDirProvider(
          appName: 'ezcore_test_${DateTime.now().millisecondsSinceEpoch}',
        );
        final dir = await provider.localDataDir();
        expect(dir.existsSync(), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('FakeLocalDataDirProvider', () {
    test('returns injected directory without creating', () async {
      final dir = Directory.systemTemp;
      final provider = FakeLocalDataDirProvider(dir);
      final result = await provider.localDataDir();
      expect(result.path, dir.path);
    });
  });
}
