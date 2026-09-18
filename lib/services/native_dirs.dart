import 'dart:io';

import 'package:flutter/services.dart';

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

/// No bundled natives (desktop dev runs, unit tests).
class FallbackNativeDirs implements NativeDirs {
  const FallbackNativeDirs();

  @override
  Future<String?> bundledCoresDir() async => null;

  @override
  Future<NativeRuntimeRef> runtimeRef() async {
    throw StateError('No bundled runtime on this host');
  }
}

/// Platform factory: channel-backed on Android/iOS, fallback elsewhere.
NativeDirs createNativeDirs() => (Platform.isAndroid || Platform.isIOS)
    ? MethodChannelNativeDirs()
    : const FallbackNativeDirs();
