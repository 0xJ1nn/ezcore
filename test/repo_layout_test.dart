import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/repo_layout.dart';

void main() {
  test('resolves runtime and cores from an app bundle inside the repo', () async {
    final root = await Directory.systemTemp.createTemp('ezcore_layout');
    try {
      final exe = File(
        '${root.path}/build/macos/Build/Products/Debug/ezCore.app/Contents/MacOS/ezCore',
      );
      await exe.create(recursive: true);
      await File(
        '${root.path}/runtime/build/libezcore_runtime.dylib',
      ).create(recursive: true);
      await Directory('${root.path}/native/cores/mgba').create(recursive: true);
      expect(
        RepoLayout.runtimeLib(executablePath: exe.path),
        '${root.path}/runtime/build/libezcore_runtime.dylib',
      );
      expect(
        RepoLayout.coresRoot(executablePath: exe.path),
        '${root.path}/native/cores',
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('returns null outside a repo checkout so callers fail honestly', () {
    expect(RepoLayout.runtimeLib(executablePath: '/usr/bin/false'), isNull);
    expect(RepoLayout.coresRoot(executablePath: '/usr/bin/false'), isNull);
  });
}
