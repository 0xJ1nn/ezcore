import 'dart:io';

/// Dev-checkout layout resolution. Production launches outside the repo have
/// no CWD-relative paths; callers surface null as an honest launch failure.
class RepoLayout {
  /// Walks from [executablePath] upward looking for [relative] as an existing
  /// path. Returns the absolute path when found, null otherwise.
  static String? _findAncestor(String? executablePath, String relative) {
    var dir = executablePath == null
        ? Directory.current
        : File(executablePath).parent;
    for (var i = 0; i < 12; i++) {
      final candidate = '${dir.path}/$relative';
      if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
        return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  static String? runtimeLib({
    String? executablePath,
    String suffix = 'dylib',
  }) {
    // Per-platform build dirs first (scripts/build_runtime.sh), then the
    // legacy shared dir, so dev launches keep working after the migration.
    const buildDirs = [
      'runtime/build-macos',
      'runtime/build-linux',
      'runtime/build-windows',
      'runtime/build',
    ];
    for (final dir in buildDirs) {
      final hit = _findAncestor(
          executablePath, '$dir/libezcore_runtime.$suffix');
      if (hit != null) return hit;
    }
    return null;
  }

  static String? coresRoot({String? executablePath}) =>
      _findAncestor(executablePath, 'native/cores');

  /// The platform-specific staged cores tree for dev checkouts:
  /// `native/cores` on macOS-arm64 (host default), `native/cores-<plat>-<arch>`
  /// elsewhere — mirroring core_platform.sh's OUT_DIR. Prefers a tree that
  /// actually contains core subdirs, so Linux dev checkouts stage
  /// cores-linux-x64 instead of falling into an empty native/cores.
  static String? stagedCoresRoot({String? executablePath}) {
    final candidates = <String>[
      if (Platform.isMacOS) ...['native/cores-macos-arm64', 'native/cores'],
      if (Platform.isWindows) ...['native/cores-windows-x64', 'native/cores'],
      if (!Platform.isMacOS && !Platform.isWindows) ...[
        'native/cores-linux-x64',
        'native/cores',
      ],
    ];
    var dir = executablePath == null
        ? Directory.current
        : File(executablePath).parent;
    // Per ancestor: first candidate tree that holds core subdirs wins.
    // (An empty native/cores must not shadow a populated platform tree.)
    for (var i = 0; i < 12; i++) {
      for (final rel in candidates) {
        final root = Directory('${dir.path}/$rel');
        if (!root.existsSync()) continue;
        try {
          final hasSubdirs =
              root.listSync(followLinks: false).whereType<Directory>().isNotEmpty;
          if (hasSubdirs) return root.path;
        } catch (_) {}
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Release-bundle core roots, searched before the dev checkout.
  /// macOS: `<app>/Contents/Resources/ezcore/cores` (populated by
  /// scripts/release.sh). Windows/Linux: `<exeDir>/cores`.
  static List<String> bundledCoreRoots({String? executablePath}) {
    final exe = executablePath == null
        ? null
        : File(executablePath).parent.path;
    final relatives = Platform.isMacOS
        ? ['../Resources/ezcore/cores']
        : ['cores'];
    final out = <String>[];
    if (exe != null) {
      for (final rel in relatives) {
        final candidate = '$exe/$rel';
        if (Directory(candidate).existsSync()) out.add(candidate);
      }
    }
    return out;
  }

  /// Release-bundle runtime library next to the executable.
  /// macOS: `Contents/Frameworks/libezcore_runtime.dylib`;
  /// Windows/Linux: `<exeDir>/libezcore_runtime.{dll,so}`.
  static String? bundledRuntimeLib({
    String? executablePath,
    String? suffix,
  }) {
    final sfx = suffix ??
        (Platform.isMacOS
            ? 'dylib'
            : Platform.isWindows
                ? 'dll'
                : 'so');
    final exe = executablePath == null
        ? null
        : File(executablePath).parent.path;
    if (exe == null) return null;
    final relatives = Platform.isMacOS
        ? ['../Frameworks/libezcore_runtime.$sfx']
        : ['libezcore_runtime.$sfx'];
    for (final rel in relatives) {
      final candidate = '$exe/$rel';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
