import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/core_path_resolver.dart';
import 'package:ezcore/services/core_staging.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/native_dirs.dart';
import 'package:ezcore/services/repo_layout.dart';
import 'package:ezcore/services/runtime_loader.dart';

class _TempDirs implements LocalDataDirProvider {
  _TempDirs(this.root);
  final Directory root;
  @override
  Future<Directory> localDataDir() async => root;
  @override
  String localDataDirPath() => root.path;
}

CoreManifest _manifest(String pin) => CoreManifest(
      id: 'probe',
      name: 'Probe',
      version: '1',
      license: 'MIT',
      systems: const ['gb'],
      extensions: const ['gb'],
      cheatFamilies: const [],
      cheatsSupported: false,
      delivery: const {},
      artifacts: {CorePathResolver.currentPlatformKey(): pin},
    );

void main() {
  test('staging copies and pin-verifies into the vault', () async {
    final tmp =
        await Directory.systemTemp.createTemp('ezcore_staging');
    try {
      final ext = Platform.isWindows
          ? 'dll'
          : (Platform.isMacOS || Platform.isIOS)
              ? 'dylib'
              : 'so';
      final src = Directory('${tmp.path}/src/probe')..createSync(recursive: true);
      final artifact = File('${src.path}/probe_libretro.$ext')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final pin = await const DartHashVerifier().sha256File(artifact.path);
      final staging = CoreStagingService(
        dirs: _TempDirs(Directory('${tmp.path}/vault')),
        native: _FixedSources([Directory('${tmp.path}/src')]),
      );
      final staged = await staging.ensureStaged(
          catalog: [_manifest(pin)]);
      expect(staged, ['probe']);
      expect(
          File('${tmp.path}/vault/cores/probe/probe.$ext').existsSync(),
          isTrue);
      expect(staging.errors, isEmpty);
      // Second run is a verified no-op.
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]),
          ['probe']);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('staging finds flat jniLibs-style layouts too', () async {    final tmp =
        await Directory.systemTemp.createTemp('ezcore_staging_flat');
    try {
      final ext = Platform.isWindows
          ? 'dll'
          : (Platform.isMacOS || Platform.isIOS)
              ? 'dylib'
              : 'so';
      final artifact = File('${tmp.path}/src/probe_libretro.$ext')
        ..createSync(recursive: true)
        ..writeAsBytesSync([7, 7, 7]);
      final pin = await const DartHashVerifier().sha256File(artifact.path);
      final staging = CoreStagingService(
        dirs: _TempDirs(Directory('${tmp.path}/vault')),
        native: _FixedSources([Directory('${tmp.path}/src')]),
      );
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]),
          ['probe']);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('staging records (never installs) pin mismatches', () async {    final tmp =
        await Directory.systemTemp.createTemp('ezcore_staging_bad');
    try {
      final ext = Platform.isWindows
          ? 'dll'
          : (Platform.isMacOS || Platform.isIOS)
              ? 'dylib'
              : 'so';
      final src = Directory('${tmp.path}/src/probe')..createSync(recursive: true);
      File('${src.path}/probe_libretro.$ext').writeAsBytesSync([9, 9, 9]);
      final staging = CoreStagingService(
        dirs: _TempDirs(Directory('${tmp.path}/vault')),
        native: _FixedSources([Directory('${tmp.path}/src')]),
      );
      final staged = await staging.ensureStaged(
          catalog: [_manifest('0' * 64)]);
      expect(staged, isEmpty);
      expect(staging.errors['probe'], contains('pin check'));
      expect(
          File('${tmp.path}/vault/cores/probe/probe.$ext').existsSync(),
          isFalse);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('native dirs degrade without a host', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const fallback = FallbackNativeDirs();
    expect(await fallback.bundledCoresDir(), isNull);
    await expectLater(fallback.runtimeRef(), throwsStateError);
    final channel = MethodChannelNativeDirs();
    expect(await channel.bundledCoresDir(), isNull);
    await expectLater(channel.runtimeRef(), throwsStateError);
  });

  test('release-bundle core roots resolve from the executable path', () async {
    // Regression: the release bundle ships cores at
    // macOS `<app>/Contents/Resources/ezcore/cores` (and `<exeDir>/cores`
    // on Windows/Linux). Nothing consulted these roots, so a downloaded
    // release found zero cores.
    final tmp = await Directory.systemTemp.createTemp('ezcore_bundle');
    try {
      final exeDir = Directory('${tmp.path}/ezCore.app/Contents/MacOS')
        ..createSync(recursive: true);
      final exe = File('${exeDir.path}/ezCore')..writeAsBytesSync([0]);
      // macOS bundle layout
      final bundled = Directory(
          '${tmp.path}/ezCore.app/Contents/Resources/ezcore/cores/probe')
        ..createSync(recursive: true);
      File('${bundled.path}/probe_libretro.dylib').writeAsBytesSync([1]);
      // Windows/Linux layout
      final flat = Directory('${exeDir.path}/cores/probe')
        ..createSync(recursive: true);
      File('${flat.path}/probe_libretro.so').writeAsBytesSync([1]);

      final roots = RepoLayout.bundledCoreRoots(executablePath: exe.path);
      expect(roots, isNotEmpty);
      final coresDir = Directory(roots.first);
      expect(coresDir.existsSync(), isTrue);
      expect(
        coresDir
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path.split('/').last),
        contains('probe'),
      );
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('runtime ref round-trips through messages', () {
    const ref = NativeRuntimeRef.path('/tmp/libezcore_runtime.dylib');
    final back = NativeRuntimeRef.fromMessage(ref.toMessage());
    expect(back.kind, 'path');
    expect(back.path, '/tmp/libezcore_runtime.dylib');
    expect(
        () => NativeRuntimeRef.fromMessage({'kind': 'path'}),
        throwsStateError);
  });

  test('sidecar hit skips re-hashing; change re-verifies', () async {
    final tmp =
        await Directory.systemTemp.createTemp('ezcore_sidecar');
    try {
      final ext = Platform.isWindows
          ? 'dll'
          : (Platform.isMacOS || Platform.isIOS)
              ? 'dylib'
              : 'so';
      final srcDir = Directory('${tmp.path}/src/probe')
        ..createSync(recursive: true);
      final src = File('${srcDir.path}/probe_libretro.$ext')
        ..writeAsBytesSync(List<int>.generate(200000, (i) => i % 251));
      final pin = await const DartHashVerifier().sha256File(src.path);
      final counting = _CountingVerifier();
      final staging = CoreStagingService(
        dirs: _TempDirs(Directory('${tmp.path}/vault')),
        hashes: counting,
        native: _FixedSources([Directory('${tmp.path}/src')]),
      );
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]),
          ['probe']);
      final firstHashes = counting.calls;
      expect(firstHashes, greaterThan(0));
      // Steady state: sidecar hit, no hashing at all.
      counting.calls = 0;
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]),
          ['probe']);
      expect(counting.calls, 0);
      // Tamper with deterministic mtimes (filesystem granularity is
      // unreliable — APFS reports whole seconds here): backdate the
      // staged copy, then rewrite the source with new bytes.
      final ancient = DateTime(2020, 1, 1);
      final modern = DateTime(2026, 6, 1);
      final dest =
          File('${tmp.path}/vault/cores/probe/probe.$ext');
      dest.setLastModifiedSync(ancient);
      // NOTE: dest sidecar still records the old mtime; touch it stale by
      // rewriting (sidecar tracks the stat at stage time).
      src.writeAsBytesSync(List<int>.generate(200000, (i) => (i + 1) % 251));
      src.setLastModifiedSync(modern);
      counting.calls = 0;
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]), isEmpty);
      expect(counting.calls, greaterThan(0));
      expect(staging.errors['probe'], contains('pin check'));
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('runtime loader resolves on dev hosts, fails honestly elsewhere',
      () async {
    // Dev host = the runtime lib exists under any runtime/build* dir.
    final suffix = Platform.isMacOS
        ? 'dylib'
        : Platform.isWindows
            ? 'dll'
            : 'so';
    final devCandidates = [
      File('runtime/build/libezcore_runtime.$suffix'),
      File('runtime/build-macos/libezcore_runtime.$suffix'),
      File('runtime/build-linux/libezcore_runtime.$suffix'),
      File('runtime/build-windows/libezcore_runtime.$suffix'),
    ];
    final hasDevRuntime = devCandidates.any((f) => f.existsSync());
    if (hasDevRuntime) {
      final ref = await resolveRuntimeRef(native: const FallbackNativeDirs());
      expect(ref['kind'], 'path');
      expect(ref['path'], isNotNull);
    } else {
      await expectLater(
          resolveRuntimeRef(native: const FallbackNativeDirs()),
          throwsStateError);
    }
  });

  test('a rebuilt (newer) source invalidates the staged copy', () async {    final tmp =
        await Directory.systemTemp.createTemp('ezcore_staging_mtime');
    try {
      final ext = Platform.isWindows
          ? 'dll'
          : (Platform.isMacOS || Platform.isIOS)
              ? 'dylib'
              : 'so';
      final srcDir = Directory('${tmp.path}/src/probe')
        ..createSync(recursive: true);
      final src = File('${srcDir.path}/probe_libretro.$ext')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final pin = await const DartHashVerifier().sha256File(src.path);
      final staging = CoreStagingService(
        dirs: _TempDirs(Directory('${tmp.path}/vault')),
        native: _FixedSources([Directory('${tmp.path}/src')]),
      );
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]),
          ['probe']);
      final dest = File('${tmp.path}/vault/cores/probe/probe.$ext');
      // Simulate a dev rebuild: new bytes + explicit mtime (filesystem
      // granularity is unreliable here — APFS reports whole seconds).
      src.writeAsBytesSync([5, 6, 7, 8]);
      src.setLastModifiedSync(DateTime(2026, 6, 1));
      final pin2 = await const DartHashVerifier().sha256File(src.path);
      // Old pin no longer matches anything: nothing stages, dest removed.
      expect(await staging.ensureStaged(catalog: [_manifest(pin)]), isEmpty);
      expect(dest.existsSync(), isFalse);
      expect(staging.errors['probe'], contains('pin check'));
      // New pin stages the rebuild.
      expect(await staging.ensureStaged(catalog: [_manifest(pin2)]),
          ['probe']);
      expect(dest.existsSync(), isTrue);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}

class _FixedSources implements NativeDirs {
  _FixedSources(this.dirs);
  final List<Directory> dirs;
  @override
  Future<String?> bundledCoresDir() async =>
      dirs.isEmpty ? null : dirs.first.path;
  @override
  Future<NativeRuntimeRef> runtimeRef() async {
    throw StateError('no runtime in staging tests');
  }
}

class _CountingVerifier implements HashVerifier {
  int calls = 0;
  final _inner = const DartHashVerifier();

  @override
  Future<String> sha256File(String path) async {
    calls++;
    return _inner.sha256File(path);
  }
}
