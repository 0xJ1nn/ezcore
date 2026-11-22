// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/backup_folder.dart';

/// A channel double: no Flutter host, just scripted replies and a call log.
class FakeBackupChannel implements BackupChannel {
  FakeBackupChannel(this.responses);

  final Map<String, Object?> responses;
  final List<String> calls = [];

  @override
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    calls.add(method);
    return responses[method] as T?;
  }
}

Future<Directory> _tempDir() => Directory.systemTemp.createTemp('ezcore_backup_');

void main() {
  group('LinuxXdgBackupFolder', () {
    test('creates a missing folder exactly once and probes writability',
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
    });

    test('falls back to HOME/.local/share without XDG_DATA_HOME', () async {
      final tmp = await _tempDir();
      try {
        final locator = LinuxXdgBackupFolder(
          environment: {'HOME': tmp.path},
        );
        final probe = await locator.locate();
        expect(
          probe.status?.path,
          '${tmp.path}/.local/share/ezCORE-backup',
        );
      } finally {
        await tmp.delete(recursive: true);
      }
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

    test('returns a reason when OneDrive is absent or the folder is missing',
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
    });
  });

  group('Apple iCloud locators', () {
    test('iOS uses the iCloud container when the channel returns one',
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
    });

    test('macOS falls back to Documents and says it is removed with the app',
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
    });
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

    test('surfaces a reason instead of throwing when no folder is found',
        () async {
      final service = BackupFolderService(
        locator: _FixedLocator(const BackupFolderProbe(null, 'No folder')),
      );
      final status = await service.resolveOnce();
      expect(status.available, isFalse);
      expect(status.confidence, BackupConfidence.unavailable);
      expect(status.reason, 'No folder');
    });

    test('marks the Android locator as needing a folder choice', () async {
      final service = BackupFolderService(
        locator: AndroidSafBackupFolder(channel: FakeBackupChannel({})),
      );
      expect(service.needsPicker, isTrue);
      final status = await service.resolveOnce();
      expect(status.reason.toLowerCase(), contains('choose a folder'));
    });

    test('applying an Android grant re-resolves and stores the grant',
        () async {
      final locator = AndroidSafBackupFolder(
        channel: FakeBackupChannel({'probeFolder': true}),
      );
      final service = BackupFolderService(locator: locator);
      final status = await service.applyAndroidGrant('tree-grant');
      expect(status.available, isTrue);
      expect(service.androidGrant, 'tree-grant');
      expect(locator.grant, 'tree-grant');
    });

    test('disabled service does no probing or folder creation', () async {
      final service = BackupFolderService.disabled();
      final status = await service.resolveOnce();
      expect(status.available, isFalse);
      expect(status.confidence, BackupConfidence.unavailable);
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
