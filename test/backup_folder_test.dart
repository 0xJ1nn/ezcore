// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/backup_folder.dart';

/// A channel double: no Flutter host, just scripted replies and a call log.
class FakeBackupChannel implements BackupChannel {
  FakeBackupChannel(this.responses, [this.errors = const {}]);

  final Map<String, Object?> responses;
  final Map<String, Object> errors;
  final List<String> calls = [];

  @override
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    calls.add(method);
    if (errors.containsKey(method)) throw errors[method]!;
    return responses[method] as T?;
  }
}

class _SlowFixedLocator extends BackupFolderLocator {
  _SlowFixedLocator(this.probe);

  final BackupFolderProbe probe;
  int calls = 0;

  @override
  String get provider => 'Slow';

  @override
  bool get survivesReinstall => true;

  @override
  Future<BackupFolderProbe> locate() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    calls++;
    return probe;
  }
}

Future<Directory> _tempDir() =>
    Directory.systemTemp.createTemp('ezcore_backup_');

void main() {
  group('LinuxXdgBackupFolder', () {
    test(
      'creates a missing folder exactly once and probes writability',
      () async {
        final tmp = await _tempDir();
        try {
          final base = '${tmp.path}/xdg';
          var creates = 0;
          Future<bool> countingEnsure(String path) async {
            if (!Directory(path).existsSync()) creates++;
            return ensureBackupFolder(path);
          }

          final locator = LinuxXdgBackupFolder(
            environment: {'XDG_DATA_HOME': base, 'HOME': tmp.path},
            ensureFolder: countingEnsure,
          );
          final first = await locator.locate();
          final status = first.status;
          expect(status, isNotNull);
          expect(status!.path, '$base/ezCORE-backup');
          expect(status.confidence, BackupConfidence.verified);
          expect(status.survivesReinstall, isTrue);
          expect(Directory('$base/ezCORE-backup').existsSync(), isTrue);
          expect(creates, 1);
          expect(
            File('$base/ezCORE-backup/.ezcore_backup_probe').existsSync(),
            isFalse,
          );

          await locator.locate();
          expect(creates, 1);
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test('falls back to HOME/.local/share without XDG_DATA_HOME', () async {
      final tmp = await _tempDir();
      try {
        final locator = LinuxXdgBackupFolder(environment: {'HOME': tmp.path});
        final probe = await locator.locate();
        expect(probe.status?.path, '${tmp.path}/.local/share/ezCORE-backup');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('an unwritable folder is unavailable with a real reason', () async {
      final probe = await LinuxXdgBackupFolder(
        environment: const {'XDG_DATA_HOME': '/tmp/unused', 'HOME': '/tmp'},
        probeFolder: (_) async => false,
      ).locate();
      expect(probe.status, isNull);
      expect(probe.reason, 'The backup folder is not writable');
    });
  });

  group('WindowsOneDriveBackupFolder', () {
    test('accepts an existing writable ezCORE folder in OneDrive', () async {
      final tmp = await _tempDir();
      try {
        final oneDrive = Directory('${tmp.path}/OneDrive')..createSync();
        Directory('${oneDrive.path}/ezCORE').createSync();
        final probe = await WindowsOneDriveBackupFolder(
          environment: {'OneDrive': oneDrive.path},
        ).locate();
        expect(probe.status?.path, '${oneDrive.path}/ezCORE');
        expect(probe.status?.provider, 'OneDrive');
        expect(probe.status?.confidence, BackupConfidence.verified);
        expect(probe.status?.survivesReinstall, isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('reads each supported OneDrive environment variable', () async {
      final tmp = await _tempDir();
      try {
        for (final key in const [
          'OneDrive',
          'OneDriveConsumer',
          'OneDriveCommercial',
        ]) {
          final root = Directory('${tmp.path}/$key')..createSync();
          Directory('${root.path}/ezCORE').createSync();
          final probe = await WindowsOneDriveBackupFolder(
            environment: {key: root.path},
          ).locate();
          expect(probe.status?.path, '${root.path}/ezCORE', reason: key);
        }
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
      'returns a reason when OneDrive is absent or the folder is missing',
      () async {
        final tmp = await _tempDir();
        try {
          final none = await WindowsOneDriveBackupFolder(
            environment: const {},
          ).locate();
          expect(none.status, isNull);
          expect(none.reason, contains('OneDrive'));

          final missing = await WindowsOneDriveBackupFolder(
            environment: {'OneDrive': tmp.path},
          ).locate();
          expect(missing.status, isNull);
          expect(missing.reason, contains('ezCORE'));
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test(
      'an existing but unreadable OneDrive folder is reported honestly',
      () async {
        final tmp = await _tempDir();
        try {
          Directory('${tmp.path}/ezCORE').createSync();
          final probe = await WindowsOneDriveBackupFolder(
            environment: {'OneDrive': tmp.path},
            probeFolder: (_) async => false,
          ).locate();
          expect(probe.status, isNull);
          expect(probe.reason, 'The OneDrive folder is not writable');
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );
  });

  group('Apple iCloud locators', () {
    test(
      'iOS uses the iCloud container when the channel returns one',
      () async {
        final tmp = await _tempDir();
        try {
          final container = '${tmp.path}/container';
          final channel = FakeBackupChannel({'icloudContainer': container});
          final probe = await IosIcloudBackupFolder(
            channel: channel,
            environment: const {},
            documentsPath: () async => '${tmp.path}/docs',
          ).locate();
          expect(probe.status?.path, container);
          expect(probe.status?.survivesReinstall, isTrue);
          expect(probe.status?.confidence, BackupConfidence.verified);
          expect(channel.calls, contains('icloudContainer'));
          expect(Directory(container).existsSync(), isTrue);
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test(
      'macOS falls back to Documents and says it is removed with the app',
      () async {
        final tmp = await _tempDir();
        try {
          final docs = '${tmp.path}/docs';
          final probe = await MacosIcloudBackupFolder(
            channel: FakeBackupChannel({}),
            environment: const {},
            documentsPath: () async => docs,
          ).locate();
          expect(probe.status?.path, '$docs/ezCORE Backup');
          expect(probe.status?.survivesReinstall, isFalse);
          expect(probe.status?.confidence, BackupConfidence.bestEffort);
          expect(probe.status!.reason.toLowerCase(), contains('deleted'));
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test(
      'iOS says iCloud is unavailable when no container is returned',
      () async {
        final tmp = await _tempDir();
        try {
          final probe = await IosIcloudBackupFolder(
            channel: FakeBackupChannel({'icloudContainer': null}),
            environment: const {},
            documentsPath: () async => '${tmp.path}/docs',
          ).locate();
          expect(probe.status?.provider, 'Documents');
          expect(probe.status?.survivesReinstall, isFalse);
          expect(probe.status?.confidence, BackupConfidence.bestEffort);
          expect(probe.status!.reason, contains('not available'));
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test(
      'a throwing iCloud check degrades to a clearly labelled fallback',
      () async {
        final tmp = await _tempDir();
        try {
          final probe = await IosIcloudBackupFolder(
            channel: FakeBackupChannel({}, {
              'icloudContainer': StateError('no capability'),
            }),
            environment: const {},
            documentsPath: () async => '${tmp.path}/docs',
          ).locate();
          expect(probe.status?.provider, 'Documents');
          expect(probe.status?.survivesReinstall, isFalse);
          expect(probe.status?.confidence, BackupConfidence.bestEffort);
          expect(probe.status!.reason, contains('could not be checked'));
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );

    test('an iCloud container that will not take writes is not presented as '
        'a backup', () async {
      final tmp = await _tempDir();
      try {
        final container = '${tmp.path}/container';
        Directory(container).createSync(recursive: true);
        final probe = await IosIcloudBackupFolder(
          channel: FakeBackupChannel({'icloudContainer': container}),
          environment: const {},
          probeFolder: (_) async => false,
          documentsPath: () async => '${tmp.path}/docs',
        ).locate();
        expect(probe.status, isNull);
        expect(probe.reason, 'The iCloud backup folder is not writable');
        expect(
          Directory('${tmp.path}/docs/ezCORE Backup').existsSync(),
          isFalse,
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
      'macOS uses the iCloud container when the channel returns one',
      () async {
        final tmp = await _tempDir();
        try {
          final container = '${tmp.path}/mac-container';
          final probe = await MacosIcloudBackupFolder(
            channel: FakeBackupChannel({'icloudContainer': container}),
            environment: const {},
            documentsPath: () async => '${tmp.path}/docs',
          ).locate();
          expect(probe.status?.path, container);
          expect(probe.status?.provider, 'iCloud');
          expect(probe.status?.survivesReinstall, isTrue);
          expect(probe.status?.confidence, BackupConfidence.verified);
        } finally {
          await tmp.delete(recursive: true);
        }
      },
    );
  });

  group('AndroidSafBackupFolder', () {
    test('is unavailable with a reason until a folder is chosen', () async {
      final probe = await AndroidSafBackupFolder(
        channel: FakeBackupChannel({'probeFolder': true}),
      ).locate();
      expect(probe.status, isNull);
      expect(probe.reason.toLowerCase(), contains('choose a folder'));
    });

    test('picks a tree and validates it with a channel probe', () async {
      final channel = FakeBackupChannel({
        'pickTree': 'tree-grant',
        'probeFolder': true,
      });
      final locator = AndroidSafBackupFolder(channel: channel);
      final grant = await locator.pickTree();
      expect(grant, 'tree-grant');
      expect(channel.calls, contains('pickTree'));

      locator.grant = grant!;
      final probe = await locator.locate();
      expect(probe.status?.path, 'tree-grant');
      expect(probe.status?.survivesReinstall, isTrue);
      expect(channel.calls, contains('probeFolder'));
    });

    test('rejects a grant whose probe fails', () async {
      final probe = await AndroidSafBackupFolder(
        channel: FakeBackupChannel({'probeFolder': false}),
        grant: 'tree-grant',
      ).locate();
      expect(probe.status, isNull);
      expect(probe.reason, isNotEmpty);
    });

    test(
      'a revoked grant tells the player to choose the folder again',
      () async {
        final probe = await AndroidSafBackupFolder(
          channel: FakeBackupChannel({'probeFolder': false}),
          grant: 'stale-tree',
        ).locate();
        expect(probe.status, isNull);
        expect(probe.reason, contains('Choose the folder again'));
      },
    );

    test('a stale grant whose permission check throws is not claimed as '
        'working', () async {
      final probe = await AndroidSafBackupFolder(
        channel: FakeBackupChannel({}, {
          'probeFolder': StateError('permission revoked'),
        }),
        grant: 'stale-tree',
      ).locate();
      expect(probe.status, isNull);
      expect(probe.reason, contains('could not be checked'));
    });
  });

  group('BackupFolderService', () {
    test('resolves once and caches the status', () async {
      final locator = _FixedLocator(
        BackupFolderProbe(
          BackupFolderStatus(
            path: '/backup',
            provider: 'Fixed',
            survivesReinstall: true,
            confidence: BackupConfidence.verified,
            reason: '',
          ),
        ),
      );
      final service = BackupFolderService(locator: locator);
      final first = await service.resolveOnce();
      final second = await service.resolveOnce();
      expect(locator.calls, 1);
      expect(identical(first, second), isTrue);
      expect(service.status.available, isTrue);
      expect(service.needsPicker, isFalse);
    });

    test(
      'surfaces a reason instead of throwing when no folder is found',
      () async {
        final service = BackupFolderService(
          locator: _FixedLocator(const BackupFolderProbe(null, 'No folder')),
        );
        final status = await service.resolveOnce();
        expect(status.available, isFalse);
        expect(status.confidence, BackupConfidence.unavailable);
        expect(status.reason, 'No folder');
      },
    );

    test('marks the Android locator as needing a folder choice', () async {
      final service = BackupFolderService(
        locator: AndroidSafBackupFolder(channel: FakeBackupChannel({})),
      );
      expect(service.needsPicker, isTrue);
      final status = await service.resolveOnce();
      expect(status.reason.toLowerCase(), contains('choose a folder'));
    });

    test(
      'applying an Android grant re-resolves and stores the grant',
      () async {
        final locator = AndroidSafBackupFolder(
          channel: FakeBackupChannel({'probeFolder': true}),
        );
        final service = BackupFolderService(locator: locator);
        final status = await service.applyAndroidGrant('tree-grant');
        expect(status.available, isTrue);
        expect(service.androidGrant, 'tree-grant');
        expect(locator.grant, 'tree-grant');
      },
    );

    test('disabled service does no probing or folder creation', () async {
      final service = BackupFolderService.disabled();
      final status = await service.resolveOnce();
      expect(status.available, isFalse);
      expect(status.confidence, BackupConfidence.unavailable);
    });

    test('concurrent resolveOnce calls share one probe and never return a '
        'placeholder', () async {
      final locator = _SlowFixedLocator(
        BackupFolderProbe(
          BackupFolderStatus(
            path: '/backup',
            provider: 'Slow',
            survivesReinstall: true,
            confidence: BackupConfidence.verified,
            reason: '',
          ),
        ),
      );
      final service = BackupFolderService(locator: locator);
      final results = await Future.wait([
        service.resolveOnce(),
        service.resolveOnce(),
        service.resolveOnce(),
      ]);
      expect(locator.calls, 1);
      expect(results.map((s) => s.path).toSet(), {'/backup'});
    });

    test('a reported mirror failure is an honest unavailable status and '
        'allows a later re-probe', () async {
      final locator = _FixedLocator(
        BackupFolderProbe(
          BackupFolderStatus(
            path: '/backup',
            provider: 'Fixed',
            survivesReinstall: true,
            confidence: BackupConfidence.verified,
            reason: '',
          ),
        ),
      );
      final service = BackupFolderService(locator: locator);
      await service.resolveOnce();

      service.reportMirrorFailure(
        'The backup folder is no longer on this device.',
      );

      expect(service.status.available, isFalse);
      expect(service.status.provider, 'Fixed');
      expect(service.status.survivesReinstall, isFalse);
      expect(service.status.confidence, BackupConfidence.unavailable);
      expect(service.status.reason, contains('no longer'));

      final again = await service.resolveOnce();
      expect(locator.calls, 2);
      expect(again.available, isTrue);
    });
  });
}

class _FixedLocator extends BackupFolderLocator {
  _FixedLocator(this.probe);

  final BackupFolderProbe probe;
  int calls = 0;

  @override
  String get provider => 'Fixed';

  @override
  bool get survivesReinstall => true;

  @override
  Future<BackupFolderProbe> locate() async {
    calls++;
    return probe;
  }
}
