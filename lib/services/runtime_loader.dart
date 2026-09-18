import 'dart:io';

import 'native_dirs.dart';
import 'repo_layout.dart';

/// Resolves *where* the native runtime lives and returns an isolate-safe
/// marker for it (see [NativeRuntimeRef]). The worker isolate opens the
/// library itself; a [DynamicLibrary] handle can never cross isolates.
///
/// Order: `EZCORE_RUNTIME_LIB` env → platform bundle (mobile channel,
/// desktop release bundle) → dev-checkout `runtime/build`. Throws an
/// honest [StateError] when nothing resolves.
Future<Map<String, String?>> resolveRuntimeRef({NativeDirs? native}) async {
  final env = Platform.environment['EZCORE_RUNTIME_LIB'];
  if (env != null && env.isNotEmpty) {
    return NativeRuntimeRef.path(env).toMessage();
  }
  if (Platform.isAndroid || Platform.isIOS) {
    return (await (native ?? createNativeDirs()).runtimeRef()).toMessage();
  }
  final suffix = Platform.isMacOS
      ? 'dylib'
      : Platform.isWindows
          ? 'dll'
          : 'so';
  final exe = Platform.resolvedExecutable;
  final bundled =
      RepoLayout.bundledRuntimeLib(executablePath: exe, suffix: suffix) ??
          RepoLayout.bundledRuntimeLib(suffix: suffix);
  if (bundled != null) {
    return NativeRuntimeRef.path(File(bundled).absolute.path).toMessage();
  }
  final dev = RepoLayout.runtimeLib(executablePath: exe, suffix: suffix) ??
      RepoLayout.runtimeLib(suffix: suffix);
  if (dev != null) {
    return NativeRuntimeRef.path(File(dev).absolute.path).toMessage();
  }
  throw StateError(
      'Native runtime not found. Build it (scripts/build_runtime.sh) or set EZCORE_RUNTIME_LIB.');
}
