import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The platform channel the native pass implements for save backups.
///
/// Method names are stable so native code can be added without touching the
/// app layer:
///   `icloudContainer` — returns the app's iCloud ubiquity container path.
///   `pickTree`        — opens the system folder picker, returns a grant.
///   `probeFolder`     — writes and deletes a throwaway file at the granted
///                       folder (`{'folder': grant}`), returns a bool. Where
///                       no channel exists the locators degrade to local-only
///                       behavior and never throw.
const backupChannelName = 'ezcore/backup';

/// How much confidence the app has that a location really is durable.
enum BackupConfidence {
  verified,
  bestEffort,
  unavailable;

  String get label => switch (this) {
    BackupConfidence.verified => 'Verified',
    BackupConfidence.bestEffort => 'Best effort',
    BackupConfidence.unavailable => 'Unavailable',
  };
}

/// The resolved per-device backup location shown in Settings.
class BackupFolderStatus {
  const BackupFolderStatus({
    required this.path,
    required this.provider,
    required this.survivesReinstall,
    required this.confidence,
    required this.reason,
  });

  /// Folder path (or the SAF tree grant on Android). Empty when unavailable.
  final String path;

  /// Human-readable source, for example `OneDrive` or `iCloud`.
  final String provider;

  /// True when removing the app leaves this folder in place.
  final bool survivesReinstall;

  final BackupConfidence confidence;

  /// Why a location is unavailable, or an honest caveat about a fallback.
  final String reason;

  bool get available => path.isNotEmpty;

  BackupFolderStatus copyWith({
    String? path,
    String? provider,
    bool? survivesReinstall,
    BackupConfidence? confidence,
    String? reason,
  }) {
    return BackupFolderStatus(
      path: path ?? this.path,
      provider: provider ?? this.provider,
      survivesReinstall: survivesReinstall ?? this.survivesReinstall,
      confidence: confidence ?? this.confidence,
      reason: reason ?? this.reason,
    );
  }
}

/// What a locator found: either a confirmed folder, or a reason why not.
class BackupFolderProbe {
  const BackupFolderProbe(this.status, [this.reason = '']);

  final BackupFolderStatus? status;
  final String reason;
}

/// Small seam over the platform channel so probes are testable without a host.
abstract class BackupChannel {
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]);
}

/// The real channel bridge. Missing-platform exceptions are swallowed by the
/// locators, so a device with no native implementation simply gets no folder.
class MethodChannelBackupChannel implements BackupChannel {
  MethodChannelBackupChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(backupChannelName);

  final MethodChannel _channel;

  @override
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) =>
      _channel.invokeMethod<T>(method, arguments);
}

/// Creates [path] when it is missing. Returns false when it cannot be made
/// writable. Idempotent: an existing folder is never recreated.
Future<bool> ensureBackupFolder(String path) async {
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.existsSync();
  } catch (_) {
    return false;
  }
}

Future<String> _defaultDocumentsPath() async {
  try {
    return (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    return '${Platform.environment['HOME'] ?? '.'}/Documents';
  }
}

/// Default write-and-delete probe used by filesystem locators.
Future<bool> _writeProbeFile(String path) async {
  final probe = File('$path/.ezcore_backup_probe');
  try {
    await probe.writeAsString('ok');
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      if (probe.existsSync()) await probe.delete();
    } catch (_) {}
  }
}

/// Finds one candidate backup location. Every implementation probes what it
/// returns and reports a reason instead of throwing when nothing is writable.
abstract class BackupFolderLocator {
  BackupFolderLocator({
    Map<String, String>? environment,
    this.channel,
    Future<bool> Function(String path)? ensureFolder,
    Future<bool> Function(String path)? probeFolder,
  }) : environment = environment ?? Platform.environment,
       ensureFolder = ensureFolder ?? ensureBackupFolder,
       probeFolder = probeFolder ?? _writeProbeFile;

  /// Injected in tests so environment-dependent paths are deterministic.
  final Map<String, String> environment;
  final BackupChannel? channel;
  final Future<bool> Function(String path) ensureFolder;
  final Future<bool> Function(String path) probeFolder;

  String get provider;
  bool get survivesReinstall;

  /// Confirms a filesystem candidate: create when missing, then write and
  /// delete a throwaway file. Never throws.
  Future<BackupFolderProbe> confirm(
    String path, {
    String notWritable = 'The backup folder is not writable',
  }) async {
    if (!await ensureFolder(path)) {
      return const BackupFolderProbe(
        null,
        'The backup folder could not be created',
      );
    }
    if (!await probeWritable(path)) {
      return BackupFolderProbe(null, notWritable);
    }
    return BackupFolderProbe(
      BackupFolderStatus(
        path: path,
        provider: provider,
        survivesReinstall: survivesReinstall,
        confidence: BackupConfidence.verified,
        reason: '',
      ),
    );
  }

  /// Writes and deletes a probe file inside a real directory. Injectable so
  /// an unwritable folder is testable without host permissions.
  Future<bool> probeWritable(String path) => probeFolder(path);

  Future<BackupFolderProbe> locate();
}

/// Shared behavior for Apple platforms: use the iCloud container when the
/// native channel provides one, otherwise fall back to the app's Documents
/// folder and say plainly that it does not survive deleting the app.
abstract class _AppleIcloudBackupFolder extends BackupFolderLocator {
  _AppleIcloudBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
    Future<String> Function()? documentsPath,
  }) : documentsPath = documentsPath ?? _defaultDocumentsPath;

  final Future<String> Function() documentsPath;

  @override
  Future<BackupFolderProbe> locate() async {
    String? container;
    var containerFailed = false;
    try {
      container = await channel?.invoke<String>('icloudContainer');
    } catch (_) {
      container = null;
      containerFailed = true;
    }

    if (container != null && container.isNotEmpty) {
      return confirm(
        container,
        notWritable: 'The iCloud backup folder is not writable',
      );
    }

    String documents;
    try {
      documents = await documentsPath();
    } catch (_) {
      documents = '${environment['HOME'] ?? '.'}/Documents';
    }
    final fallback = await confirm(
      '$documents/ezCORE Backup',
      notWritable: 'The documents folder is not writable',
    );
    final status = fallback.status;
    if (status == null) return fallback;
    final reason = containerFailed
        ? 'iCloud could not be checked on this device; saves go to a folder '
              'that is removed when the app is deleted.'
        : 'iCloud is not available here; this folder is removed when the app '
              'is deleted.';
    return BackupFolderProbe(
      status.copyWith(
        provider: 'Documents',
        survivesReinstall: false,
        confidence: BackupConfidence.bestEffort,
        reason: reason,
      ),
      fallback.reason,
    );
  }
}

/// iOS backup locator over the `ezcore/backup` channel.
class IosIcloudBackupFolder extends _AppleIcloudBackupFolder {
  IosIcloudBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
    super.documentsPath,
  });

  @override
  String get provider => 'iCloud';

  @override
  bool get survivesReinstall => true;
}

/// macOS backup locator over the same channel as iOS.
class MacosIcloudBackupFolder extends _AppleIcloudBackupFolder {
  MacosIcloudBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
    super.documentsPath,
  });

  @override
  String get provider => 'iCloud';

  @override
  bool get survivesReinstall => true;
}

/// Android backup locator. A Storage Access Framework tree grant is required;
/// until one exists the locator reports that a folder must be chosen. The
/// grant is validated by writing and deleting a probe file through the channel.
class AndroidSafBackupFolder extends BackupFolderLocator {
  AndroidSafBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
    this.grant = '',
  });

  /// Persisted tree grant, applied again on each launch.
  String grant;

  @override
  String get provider => 'Device folder';

  @override
  bool get survivesReinstall => true;

  /// Opens the system picker. Returns null when the person cancels or the
  /// channel is missing.
  Future<String?> pickTree() async {
    try {
      final value = await channel?.invoke<String>('pickTree');
      return value != null && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BackupFolderProbe> locate() async {
    if (grant.isEmpty) {
      return const BackupFolderProbe(null, 'Choose a folder to back up saves');
    }
    bool writable = false;
    var checkFailed = false;
    try {
      writable =
          await channel?.invoke<bool>('probeFolder', {'folder': grant}) ??
          false;
      checkFailed = channel == null;
    } catch (_) {
      writable = false;
      checkFailed = true;
    }
    if (!writable) {
      final reason = checkFailed
          ? 'The permission for the chosen folder could not be checked. '
                'Choose the folder again.'
          : 'The chosen folder can no longer be written to. Choose the folder '
                'again.';
      return BackupFolderProbe(null, reason);
    }
    return BackupFolderProbe(
      BackupFolderStatus(
        path: grant,
        provider: provider,
        survivesReinstall: true,
        confidence: BackupConfidence.verified,
        reason: '',
      ),
    );
  }
}

/// Windows backup locator. Uses the first OneDrive environment variable that
/// is set, and only accepts `<OneDrive>/ezCORE` when that folder already
/// exists and a probe write succeeds.
class WindowsOneDriveBackupFolder extends BackupFolderLocator {
  WindowsOneDriveBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
  });

  static const _envKeys = <String>[
    'OneDrive',
    'OneDriveConsumer',
    'OneDriveCommercial',
  ];

  @override
  String get provider => 'OneDrive';

  @override
  bool get survivesReinstall => true;

  @override
  Future<BackupFolderProbe> locate() async {
    String? base;
    for (final key in _envKeys) {
      final value = environment[key];
      if (value != null && value.isNotEmpty) {
        base = value;
        break;
      }
    }
    if (base == null) {
      return const BackupFolderProbe(
        null,
        'OneDrive is not set up on this device',
      );
    }
    final path = '$base/ezCORE';
    if (!Directory(path).existsSync()) {
      return const BackupFolderProbe(
        null,
        'Create an ezCORE folder in OneDrive to back up saves there',
      );
    }
    return confirm(path, notWritable: 'The OneDrive folder is not writable');
  }
}

/// Linux backup locator: `$XDG_DATA_HOME/ezCORE-backup`, or
/// `~/.local/share/ezCORE-backup` when XDG_DATA_HOME is unset.
class LinuxXdgBackupFolder extends BackupFolderLocator {
  LinuxXdgBackupFolder({
    super.environment,
    super.channel,
    super.ensureFolder,
    super.probeFolder,
  });

  @override
  String get provider => 'This device';

  @override
  bool get survivesReinstall => true;

  @override
  Future<BackupFolderProbe> locate() async {
    final xdg = environment['XDG_DATA_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : '${environment['HOME'] ?? '.'}/.local/share';
    return confirm(
      '$base/ezCORE-backup',
      notWritable: 'The backup folder is not writable',
    );
  }
}

class _UnavailableLocator extends BackupFolderLocator {
  @override
  String get provider => 'Not set';

  @override
  bool get survivesReinstall => false;

  @override
  Future<BackupFolderProbe> locate() async => const BackupFolderProbe(
    null,
    'Backup folders are not used in this session',
  );
}

/// Resolves the backup folder once and caches the result for the session.
/// Every failure becomes a reason in [status]; the app keeps using local saves.
class BackupFolderService {
  BackupFolderService({
    BackupFolderLocator? locator,
    BackupChannel? channel,
    Map<String, String>? environment,
    Future<String> Function()? documentsPath,
    this.androidGrant = '',
  }) : _locator =
           locator ??
           _platformLocator(channel, environment, documentsPath, androidGrant);

  /// No probing and no folder creation — for sessions without persistence.
  factory BackupFolderService.disabled() =>
      BackupFolderService(locator: _UnavailableLocator());

  static BackupFolderLocator _platformLocator(
    BackupChannel? channel,
    Map<String, String>? environment,
    Future<String> Function()? documentsPath,
    String grant,
  ) {
    if (Platform.isIOS) {
      return IosIcloudBackupFolder(
        channel: channel,
        environment: environment,
        documentsPath: documentsPath,
      );
    }
    if (Platform.isMacOS) {
      return MacosIcloudBackupFolder(
        channel: channel,
        environment: environment,
        documentsPath: documentsPath,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSafBackupFolder(channel: channel, grant: grant);
    }
    if (Platform.isWindows) {
      return WindowsOneDriveBackupFolder(
        channel: channel,
        environment: environment,
      );
    }
    return LinuxXdgBackupFolder(channel: channel, environment: environment);
  }

  final BackupFolderLocator _locator;

  /// The last persisted Android tree grant.
  String androidGrant;

  BackupFolderStatus? _cached;
  bool _resolved = false;
  Future<BackupFolderStatus>? _resolveFuture;

  /// True when this platform needs the person to pick a folder.
  bool get needsPicker => _locator is AndroidSafBackupFolder;

  /// False for [BackupFolderService.disabled]: a session with no backup
  /// source has nothing to resolve, so an empty [status] means "not set"
  /// rather than a folder that stopped working.
  bool get hasBackupSource => _locator is! _UnavailableLocator;

  /// Always readable; an unresolved or failed lookup has an empty path.
  BackupFolderStatus get status =>
      _cached ??
      const BackupFolderStatus(
        path: '',
        provider: 'Not set',
        survivesReinstall: false,
        confidence: BackupConfidence.unavailable,
        reason: 'Not checked yet',
      );

  /// Resolves at most once unless a new grant is applied. Concurrent callers
  /// (boot plus an explicit refresh) share the same probe instead of one
  /// seeing the placeholder "Not checked yet" status.
  Future<BackupFolderStatus> resolveOnce() {
    final pending = _resolveFuture;
    if (pending != null) return pending;
    if (_resolved) return Future.value(status);
    final future = resolve();
    _resolveFuture = future;
    return future;
  }

  /// Re-runs the probe (used after a folder is chosen).
  Future<BackupFolderStatus> resolve() async {
    _resolved = true;
    try {
      BackupFolderProbe probe;
      try {
        probe = await _locator.locate();
      } catch (_) {
        probe = const BackupFolderProbe(
          null,
          'The backup folder could not be checked',
        );
      }
      final candidate = probe.status;
      if (candidate == null) {
        final unavailable = BackupFolderStatus(
          path: '',
          provider: _locator.provider,
          survivesReinstall: false,
          confidence: BackupConfidence.unavailable,
          reason: probe.reason,
        );
        _cached = unavailable;
        return unavailable;
      }
      _cached = candidate;
      return candidate;
    } finally {
      _resolveFuture = null;
    }
  }

  /// The save layer found the folder broken after it was resolved. Drop the
  /// claim that saves are backed up, and allow a later resolve to re-probe.
  void reportMirrorFailure(String reason) {
    if (reason.isEmpty) return;
    _cached = BackupFolderStatus(
      path: '',
      provider: _cached?.provider ?? _locator.provider,
      survivesReinstall: false,
      confidence: BackupConfidence.unavailable,
      reason: reason,
    );
    _resolved = false;
    _resolveFuture = null;
  }

  /// Opens the native folder picker where one is needed.
  Future<String?> pickTree() async {
    final locator = _locator;
    return locator is AndroidSafBackupFolder ? locator.pickTree() : null;
  }

  /// Applies a freshly granted (or restored) Android tree and re-resolves.
  Future<BackupFolderStatus> applyAndroidGrant(String grant) async {
    androidGrant = grant;
    final locator = _locator;
    if (locator is AndroidSafBackupFolder) locator.grant = grant;
    return resolve();
  }
}
