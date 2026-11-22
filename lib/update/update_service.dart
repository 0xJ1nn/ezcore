// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/local_data_dir.dart';
import 'update_checker.dart';

/// What happened after a file was downloaded, verified and opened.
class UpdateInstallResult {
  const UpdateInstallResult({required this.restartRequired, this.path = ''});

  /// True on Linux when the running AppImage was replaced in place.
  final bool restartRequired;
  final String path;
}

/// Holds the updater state for the app and the About screen.
///
/// The service does nothing until [initialize] is called from startup, and it
/// never makes a request in a store build. Widgets only read the result and
/// call [checkNow] in response to a person's action.
class UpdateService extends ChangeNotifier {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  UpdateResult _result = UpdateResult.skipped();
  UpdateResult get result => _result;

  bool _autoCheck = true;
  bool get autoCheck => _autoCheck;

  String? _lastCheckIso;
  String? get lastCheckIso => _lastCheckIso;

  String? _error;
  String? get error => _error;

  bool _busy = false;
  bool get busy => _busy;

  bool _restartRequired = false;
  bool get restartRequired => _restartRequired;

  DownloadPlatform? _platform;
  String? _prefsPath;
  Timer? _dailyTimer;

  bool get supported => !isStoreBuild && currentDownloadPlatform() != null;

  Future<void> initialize() async {
    if (_prefsPath != null) return;
    if (!supported) return;
    _platform = currentDownloadPlatform();
    final dir = await PlatformLocalDataDirProvider().localDataDir();
    _prefsPath = '${dir.path}${Platform.pathSeparator}update_prefs.json';
    final file = File(_prefsPath!);
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['autoCheck'] is bool) _autoCheck = decoded['autoCheck'] as bool;
      if (decoded['lastCheck'] is String) {
        _lastCheckIso = decoded['lastCheck'] as String;
      }
    } catch (_) {
      // A broken preference file falls back to the defaults.
    }
    _dailyTimer ??= Timer.periodic(const Duration(hours: 24), (_) {
      maybeCheckAtStartup();
    });
  }

  @override
  void dispose() {
    _dailyTimer?.cancel();
    super.dispose();
  }

  UpdateChecker? _makeChecker() {
    final platform = _platform;
    if (platform == null) return null;
    return UpdateChecker(
      client: const IoUpdateHttpClient(),
      platform: platform,
      autoCheckEnabled: _autoCheck,
    );
  }

  /// Called once at startup. Checks only when due and switched on.
  Future<void> maybeCheckAtStartup() async {
    await initialize();
    final checker = _makeChecker();
    if (checker == null || !checker.autoCheckEnabled) return;
    if (!checker.isDue(_lastCheckIso, DateTime.now().toUtc())) return;
    await _runCheck(manual: false);
  }

  /// The person asked to check now. Bypasses the switch, not the store rule.
  Future<void> checkNow() async {
    await initialize();
    if (_makeChecker() == null) return;
    await _runCheck(manual: true);
  }

  Future<void> _runCheck({required bool manual}) async {
    final checker = _makeChecker();
    if (checker == null) return;
    _busy = true;
    _error = null;
    _restartRequired = false;
    notifyListeners();
    final result = await checker.check(manual: manual);
    _busy = false;
    if (result.wasAttempted) {
      _lastCheckIso = DateTime.now().toUtc().toIso8601String();
      await _persist();
    }
    _result = result;
    if (result.isError) _error = result.message;
    notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    _autoCheck = value;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final path = _prefsPath;
    if (path == null) return;
    final file = File(path);
    if (!file.parent.existsSync()) await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'autoCheck': _autoCheck, 'lastCheck': _lastCheckIso}),
    );
  }

  /// Downloads this platform's file, verifies it and opens it.
  ///
  /// Returns null when there is nothing to install or the verification fails;
  /// in the latter case an error is shown on the About screen.
  Future<UpdateInstallResult?> install() async {
    final release = _result.release;
    final platform = _platform;
    if (release == null || platform == null) return null;
    _busy = true;
    _error = null;
    _restartRequired = false;
    notifyListeners();
    try {
      final downloader = UpdateDownloader(
        client: const IoUpdateHttpClient(),
        platform: platform,
      );
      final downloaded = await downloader.download(release);
      final result = await _writeAndOpen(downloaded, platform);
      _restartRequired = result.restartRequired;
      _busy = false;
      notifyListeners();
      return result;
    } catch (e) {
      _busy = false;
      _error = e.toString();
      _result = UpdateResult.error(_error!);
      notifyListeners();
      return null;
    }
  }

  Future<UpdateInstallResult> _writeAndOpen(
    DownloadedUpdate update,
    DownloadPlatform platform,
  ) async {
    final dir = await PlatformLocalDataDirProvider().localDataDir();
    final updates = Directory('${dir.path}${Platform.pathSeparator}updates');
    if (!updates.existsSync()) await updates.create(recursive: true);
    final file = File('${updates.path}${Platform.pathSeparator}${update.asset.name}');
    await file.writeAsBytes(update.bytes, flush: true);

    if (platform == DownloadPlatform.linux &&
        update.asset.name.toLowerCase().endsWith('.appimage')) {
      final running = Platform.resolvedExecutable;
      if (running.toLowerCase().endsWith('.appimage')) {
        final target = File(running);
        final backup = File('$running.previous');
        if (target.existsSync()) await target.copy(backup.path);
        await file.copy(target.path);
        return const UpdateInstallResult(restartRequired: true);
      }
    }

    switch (platform) {
      case DownloadPlatform.windows:
        await Process.run('cmd', ['/c', 'start', '', file.path]);
      case DownloadPlatform.macos:
        await Process.run('open', [file.path]);
      case DownloadPlatform.linux:
        await Process.run('xdg-open', [file.path]);
    }
    return UpdateInstallResult(restartRequired: false, path: file.path);
  }

  /// Opens the release page in the platform's browser.
  Future<void> openReleaseNotes() async {
    final url = _result.release?.pageUrl;
    if (url == null || url.isEmpty) return;
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }

  /// Starts a fresh copy of the app after an in-place Linux update.
  Future<void> restart() async {
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
