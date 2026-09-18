import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Provides the local data directory for persistence.
///
/// Abstracted so tests inject a temp directory while production resolves
/// the OS application-support directory. The resolved directory is never
/// the app bundle — it lives under Application Support (macOS), AppData
/// (Windows), `~/.local/share` (Linux), or the app-support sandbox
/// directory on Android/iOS (resolved once at startup, see [resolve]).
abstract class LocalDataDirProvider {
  Future<Directory> localDataDir();

  /// Synchronous path resolution without creating the directory.
  /// Use this when you need the path string eagerly (e.g. in constructors).
  String localDataDirPath();
}

/// Resolves the platform-specific application data directory.
///
/// macOS:  `~/Library/Application Support/<appName>`
/// Windows: `%APPDATA%\<appName>`
/// Linux:  `~/.local/share/<appName>`
/// Android/iOS: app-support directory via path_provider, pinned by
/// [resolve] during startup (plain [path] cannot be synchronous there).
class PlatformLocalDataDirProvider implements LocalDataDirProvider {
  PlatformLocalDataDirProvider({this.appName = 'ezcore'});
  final String appName;

  static String? _startupOverride;

  /// Pins the resolved directory for the whole process. Called once from
  /// `main()` on Android/iOS; no-op elsewhere.
  static void pinStartupDir(String path) => _startupOverride = path;

  /// Async startup resolution. Desktop returns immediately; mobile awaits
  /// path_provider, pins the result, and returns the provider.
  static Future<PlatformLocalDataDirProvider> resolve(
      {String appName = 'ezcore'}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationSupportDirectory();
      pinStartupDir('${dir.path}/$appName');
    }
    return PlatformLocalDataDirProvider(appName: appName);
  }

  /// Returns the platform data directory path without creating it.
  /// Uses the same resolution logic as [localDataDir].
  static String path({String appName = 'ezcore'}) {
    final pinned = _startupOverride;
    if (pinned != null) return pinned;
    if (Platform.isMacOS) {
      final base = Platform.environment['HOME'] ?? '.';
      return '$base/Library/Application Support/$appName';
    } else if (Platform.isWindows) {
      final base = Platform.environment['APPDATA'] ?? '.';
      return '$base/$appName';
    } else if (Platform.isLinux) {
      final base = Platform.environment['HOME'] ?? '.';
      return '$base/.local/share/$appName';
    } else {
      return './.$appName';
    }
  }

  @override
  String localDataDirPath() => path(appName: appName);

  @override
  Future<Directory> localDataDir() async {
    final dir = Directory(localDataDirPath());
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
