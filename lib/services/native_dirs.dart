import 'dart:io';

import 'package:flutter/services.dart';

import 'repo_layout.dart';

/// Serializable reference to the native runtime library.
///
/// The worker isolate cannot receive a [DynamicLibrary] handle, so the
/// host resolves *where* the runtime lives and the isolate opens it:
/// - `path` — dlopen/LoadLibrary an absolute path (desktop, Android .so);
/// - `process` — symbols are linked into the process (iOS static link).
class NativeRuntimeRef {
  const NativeRuntimeRef.path(this.path) : kind = 'path';
  const NativeRuntimeRef.process()
      : kind = 'process',
        path = null;

  final String kind;
  final String? path;

  Map<String, String?> toMessage() => {'kind': kind, 'path': path};

  factory NativeRuntimeRef.fromMessage(Map message) {
    if (message['kind'] == 'process') return const NativeRuntimeRef.process();
    final p = message['path'] as String?;
    if (p == null || p.isEmpty) {
      throw StateError('Runtime ref has no path');
    }
    return NativeRuntimeRef.path(p);
  }
}

/// Platform-packaged native locations (bundled cores dir, runtime ref).
/// Desktop dev checkouts resolve through [RepoLayout] instead; mobile
/// runners answer over the `ezcore/native` channel.
abstract class NativeDirs {
  /// Directory containing bundled `<id>/<id>_libretro.{so,dylib}` trees,
  /// or null when the platform ships none (desktop dev, tests).
  Future<String?> bundledCoresDir();

  /// Where the runtime library lives for this install.
  Future<NativeRuntimeRef> runtimeRef();
}

/// Channel implementation (Android/iOS runners). Degrades to nulls when
/// the host has no channel (unit tests, desktop): callers treat that as
/// "no bundled natives" and fall back to dev/release-filesystem roots.
class MethodChannelNativeDirs implements NativeDirs {
  MethodChannelNativeDirs({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ezcore/native');
  final MethodChannel _channel;

  @override
  Future<String?> bundledCoresDir() async {
    try {
      return await _channel.invokeMethod<String>('bundledCoresDir');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NativeRuntimeRef> runtimeRef() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('runtimeRef');
      if (raw != null) return NativeRuntimeRef.fromMessage(raw);
    } catch (_) {}
    throw StateError('No bundled runtime on this host');
  }
}

/// No bundled natives (unit tests, non-bundle runs).
class FallbackNativeDirs implements NativeDirs {
  const FallbackNativeDirs();

  @override
  Future<String?> bundledCoresDir() async => null;

  @override
  Future<NativeRuntimeRef> runtimeRef() async {
    throw StateError('No bundled runtime on this host');
  }
}

/// Desktop installs: cores ship inside the release bundle — macOS
/// `<app>/Contents/Resources/ezcore/cores`, Windows/Linux `<exeDir>/cores`
/// (populated by `scripts/release.sh`) — and the runtime sits next to the
/// executable. Without this, a downloaded release found no cores at all:
/// the staging service's only sources were mobile channels and the dev
/// checkout, and discovery fell through to a dev-relative path.
class DesktopNativeDirs implements NativeDirs {
  const DesktopNativeDirs();

  @override
  Future<String?> bundledCoresDir() async {
    final roots = RepoLayout.bundledCoreRoots(
      executablePath: Platform.resolvedExecutable,
    );
    return roots.isEmpty ? null : roots.first;
  }

  @override
  Future<NativeRuntimeRef> runtimeRef() async {
    final suffix = Platform.isMacOS
        ? 'dylib'
        : Platform.isWindows
            ? 'dll'
            : 'so';
    final path = RepoLayout.bundledRuntimeLib(
          executablePath: Platform.resolvedExecutable,
          suffix: suffix,
        ) ??
        RepoLayout.bundledRuntimeLib(suffix: suffix);
    if (path == null) throw StateError('No bundled runtime on this host');
    return NativeRuntimeRef.path(path);
  }
}

/// Platform factory: channel-backed on Android/iOS, bundle-backed on
/// desktop.
NativeDirs createNativeDirs() => (Platform.isAndroid || Platform.isIOS)
    ? MethodChannelNativeDirs()
    : const DesktopNativeDirs();
