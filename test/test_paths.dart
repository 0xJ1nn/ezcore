/// Single policy for native-artifact paths in tests.
///
/// Host artifacts live under `runtime/build*` (legacy `runtime/build` or
/// per-platform `runtime/build-<os>` from scripts/build_runtime.sh) and
/// `native/cores*` (dev checkout or `native/cores-<platform>-<arch>` from
/// scripts/build_core.sh). Every resolver returns null when absent so
/// tests skip instead of failing on fresh clones or foreign platforms.
library;

import 'dart:io';

String get hostLibExt => Platform.isWindows
    ? 'dll'
    : (Platform.isMacOS || Platform.isIOS)
        ? 'dylib'
        : 'so';

String? firstExisting(Iterable<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync() || Directory(path).existsSync()) {
      return path;
    }
  }
  return null;
}

/// Directory holding the built runtime + synth core + CTest harness.
String? runtimeBuildDir() => firstExisting([
      'runtime/build-macos',
      'runtime/build-linux',
      'runtime/build-windows',
      'runtime/build',
    ]);

String? _join(String? dir, String file) =>
    dir == null ? null : '$dir/$file';

/// Absolute-or-relative path to the built runtime library, if present.
String? bridgeLib() =>
    _join(runtimeBuildDir(), 'libezcore_runtime.$hostLibExt');

/// Path to the built synthetic test core, if present.
String? synthLib() =>
    _join(runtimeBuildDir(), 'libsynth_libretro.$hostLibExt');

/// Staged core artifact for [id] (dev checkout or platform matrix output).
String? stagedCoreLib(String id) {
  final roots = <String>['native/cores'];
  final native = Directory('native');
  if (native.existsSync()) {
    for (final entity in native.listSync()) {
      if (entity is Directory &&
          entity.path.startsWith('native/cores-')) {
        roots.add(entity.path);
      }
    }
  }
  for (final root in roots) {
    final hit = '$root/$id/${id}_libretro.$hostLibExt';
    if (File(hit).existsSync()) return hit;
  }
  return null;
}

/// Test fixture ROM by filename, if present.
String? fixture(String name) {
  const path = 'native/test-roms';
  final hit = '$path/$name';
  return File(hit).existsSync() ? hit : null;
}
