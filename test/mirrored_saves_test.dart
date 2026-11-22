// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/services/backup_folder.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/mirrored_saves.dart';
import 'package:ezcore/services/persistence_service.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List payload(List<int> values) => Uint8List.fromList(values);

Future<Directory> tempDir(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

/// A locator that resolves to a real, writable folder on this host.
class _AvailableLocator extends BackupFolderLocator {
  _AvailableLocator(this.path);

  final String path;

  @override
  String get provider => 'Test backup';

  @override
  bool get survivesReinstall => true;

  @override
  Future<BackupFolderProbe> locate() async {
    if (!Directory(path).existsSync()) {
      await Directory(path).create(recursive: true);
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
}

class _FixedDataDirProvider implements LocalDataDirProvider {
  _FixedDataDirProvider(this.path);

  final String path;

  @override
  Future<Directory> localDataDir() async =>
      Directory(path)..createSync(recursive: true);

  @override
  String localDataDirPath() => path;
}

void main() {
  late Directory primary;
  late Directory mirror;
  late LocalSaveSyncProvider local;
  late MirroredSaveSyncProvider provider;

  setUp(() async {
    primary = await tempDir('ezcore_mirror_primary_');
    mirror = await tempDir('ezcore_mirror_backup_');
    local = LocalSaveSyncProvider(primary);
    provider = MirroredSaveSyncProvider(local, mirror, appVersion: '9.9.9');
  });

  tearDown(() async {
    if (primary.existsSync()) await primary.delete(recursive: true);
    if (mirror.existsSync()) await mirror.delete(recursive: true);
  });

  Future<List<dynamic>> readIndex([Directory? root]) {
    final file = File('${(root ?? mirror).path}/saves/index.json');
    return file.readAsString().then(
      (text) => json.decode(text) as List<dynamic>,
    );
  }

  group('MirroredSaveSyncProvider', () {
    test('upload mirrors bytes and records metadata in the index', () async {
      await provider.upload('game-1', 'auto', payload([1, 2, 3, 4]));

      expect(
        await File('${primary.path}/game-1/auto.bin').readAsBytes(),
        payload([1, 2, 3, 4]),
      );
      expect(
        await File('${mirror.path}/saves/game-1/auto.bin').readAsBytes(),
        payload([1, 2, 3, 4]),
      );

      final index = await readIndex();
      expect(index, hasLength(1));
      final entry = index.single as Map<String, dynamic>;
      expect(entry['gameId'], 'game-1');
      expect(entry['slot'], 'auto');
      expect(entry['size'], 4);
      expect(DateTime.tryParse(entry['modified'] as String), isNotNull);
      expect(entry['appVersion'], '9.9.9');
    });

    test(
      'list unions primary and mirror, and the primary wins a conflict',
      () async {
        await provider.upload('game-1', 'auto', payload([1]));
        await provider.upload('game-1', 'orphan', payload([2]));
        // Overwrite one primary copy and lose the other, as a reinstall would.
        await local.upload('game-1', 'auto', payload([9, 9]));
        await File('${primary.path}/game-1/orphan.bin').delete();

        final slots = await provider.list('game-1');
        expect(slots.map((s) => s.id).toSet(), {'auto', 'orphan'});
        expect(await provider.download('game-1', 'auto'), payload([9, 9]));
        expect(await provider.download('game-1', 'orphan'), payload([2]));
        expect((await provider.mirrorOnlySlots()).map((r) => r.slot), [
          'orphan',
        ]);
      },
    );

    test('a delete tombstones the mirror and cannot be resurrected', () async {
      final survival = File('${mirror.path}/saves/game-1/auto.bin');
      await provider.upload('game-1', 'auto', payload([1, 2, 3]));
      expect(survival.existsSync(), isTrue);

      await provider.remove('game-1', 'auto');

      expect(survival.existsSync(), isTrue, reason: 'the survival copy stays');
      expect(await local.download('game-1', 'auto'), isNull);
      expect(await provider.list('game-1'), isEmpty);
      expect(await provider.download('game-1', 'auto'), isNull);
      expect(await provider.mirrorOnlySlots(), isEmpty);
      expect(
        ((await readIndex()).single as Map<String, dynamic>)['deleted'],
        isTrue,
      );

      expect(await provider.restoreFromMirror(), 0);
      expect(await local.download('game-1', 'auto'), isNull);
    });

    test(
      'restoreFromMirror copies mirror-only saves into the primary',
      () async {
        await provider.upload('game-1', 'auto', payload([7, 8]));
        // Simulate a reinstall: the local vault is gone, the backup survives.
        await primary.delete(recursive: true);
        expect(await local.download('game-1', 'auto'), isNull);
        expect((await provider.mirrorOnlySlots()).single.slot, 'auto');

        expect(await provider.restoreFromMirror(), 1);

        expect(await local.download('game-1', 'auto'), payload([7, 8]));
        expect(await provider.mirrorOnlySlots(), isEmpty);
      },
    );

    test('a failed mirror write never fails the save itself', () async {
      final blocked = File('${primary.path}/blocked');
      await blocked.writeAsString('a file, not a folder');
      final failing = MirroredSaveSyncProvider(
        local,
        Directory(blocked.path),
        appVersion: '9.9.9',
      );

      await failing.upload('game-1', 'auto', payload([5, 6]));

      expect(await local.download('game-1', 'auto'), payload([5, 6]));
      expect(File('${blocked.path}/saves/index.json').existsSync(), isFalse);
    });

    test('a later upload clears the tombstone for the same slot', () async {
      await provider.upload('game-1', 'auto', payload([1]));
      await provider.remove('game-1', 'auto');
      expect(await provider.mirrorOnlySlots(), isEmpty);

      await provider.upload('game-1', 'auto', payload([2]));
      expect(
        ((await readIndex()).single as Map<String, dynamic>)['deleted'],
        isNull,
      );

      // Lose the primary again: the fresh mirror copy is now restorable.
      await File('${primary.path}/game-1/auto.bin').delete();
      expect((await provider.mirrorOnlySlots()).single.slot, 'auto');
      expect(await provider.restoreFromMirror(), 1);
      expect(await local.download('game-1', 'auto'), payload([2]));
    });

    test('another app\'s files in the chosen folder are never offered as '
        'saves', () async {
      final foreign = Directory('${mirror.path}/foreign/saves/other-game')
        ..createSync(recursive: true);
      await File('${foreign.path}/slot.bin').writeAsBytes(payload([9, 9]));
      final unindexed = Directory('${mirror.path}/saves/unindexed-game')
        ..createSync(recursive: true);
      await File('${unindexed.path}/slot.bin').writeAsBytes(payload([8]));
      await File('${mirror.path}/notes.txt').writeAsString('not a save');
      final orphan = MirroredSaveSyncProvider(local, Directory(mirror.path));

      expect((await orphan.mirrorOnlySlots()).map((r) => r.gameId), isEmpty);
      expect(await orphan.list('other-game'), isEmpty);
      expect(await orphan.download('other-game', 'slot'), isNull);
      expect(await orphan.restoreFromMirror(), 0);
    });

    test('two devices sharing one folder keep each other\'s saves after a '
        'delete', () async {
      final phoneVault = await tempDir('ezcore_phone_');
      final tabletVault = await tempDir('ezcore_tablet_');
      final visitorVault = await tempDir('ezcore_visitor_');
      try {
        final phone = MirroredSaveSyncProvider(
          LocalSaveSyncProvider(phoneVault),
          mirror,
          deviceId: 'phone',
        );
        final tablet = MirroredSaveSyncProvider(
          LocalSaveSyncProvider(tabletVault),
          mirror,
          deviceId: 'tablet',
        );

        await phone.upload('game-1', 'auto', payload([1, 2]));
        // The tablet has only the backup: it sees the save as mirror-only.
        expect((await tablet.mirrorOnlySlots()).single.slot, 'auto');
        expect(await tablet.restoreFromMirror(), 1);
        expect(await tablet.download('game-1', 'auto'), payload([1, 2]));

        // A delete on the phone must not erase the tablet's mirrored copy.
        await phone.remove('game-1', 'auto');
        await File('${tabletVault.path}/game-1/auto.bin').delete();

        final visitor = MirroredSaveSyncProvider(
          LocalSaveSyncProvider(visitorVault),
          mirror,
          deviceId: 'visitor',
        );
        expect((await visitor.mirrorOnlySlots()).single.slot, 'auto');
        expect(await visitor.download('game-1', 'auto'), payload([1, 2]));
        expect(await visitor.restoreFromMirror(), 1);
      } finally {
        await phoneVault.delete(recursive: true);
        await tabletVault.delete(recursive: true);
        await visitorVault.delete(recursive: true);
      }
    });

    test('deleting a local-only save cannot tombstone another device\'s '
        'mirrored save', () async {
      final otherVault = await tempDir('ezcore_other_');
      try {
        await provider.upload('game-1', 'auto', payload([4]));
        await File('${primary.path}/game-1/auto.bin').delete();

        final other = MirroredSaveSyncProvider(
          LocalSaveSyncProvider(otherVault),
          mirror,
          deviceId: 'other-device',
        );
        final otherFile = File('${otherVault.path}/game-1/auto.bin');
        otherFile.parent.createSync(recursive: true);
        await otherFile.writeAsBytes(payload([7]));
        await other.remove('game-1', 'auto');

        expect((await provider.mirrorOnlySlots()).single.slot, 'auto');
        expect(await provider.download('game-1', 'auto'), payload([4]));
      } finally {
        await otherVault.delete(recursive: true);
      }
    });
  });

  group('AppState wiring', () {
    test(
      'no backup folder keeps the plain provider and writes no mirror',
      () async {
        final saves = LocalSaveSyncProvider(primary);
        final state = AppState.internal(
          persistence: null,
          saves: saves,
          backupFolder: BackupFolderService.disabled(),
        );

        await state.resolveBackupFolder();

        expect(state.saves, same(saves));
        expect(state.saves, isNot(isA<MirroredSaveSyncProvider>()));
        await state.saves.upload('game-1', 'auto', payload([3]));
        expect(
          await File('${primary.path}/game-1/auto.bin').readAsBytes(),
          payload([3]),
        );
        expect(Directory('${primary.path}/saves').existsSync(), isFalse);
        state.dispose();
      },
    );

    test(
      'an available backup folder turns the provider into a mirror',
      () async {
        final backup = '${mirror.path}/backup';
        final state = AppState.internal(
          persistence: null,
          saves: local,
          backupFolder: BackupFolderService(locator: _AvailableLocator(backup)),
        );

        await state.resolveBackupFolder();

        expect(state.saves, isA<MirroredSaveSyncProvider>());
        await state.saves.upload('game-1', 'auto', payload([4, 5]));
        expect(
          await File('$backup/saves/game-1/auto.bin').readAsBytes(),
          payload([4, 5]),
        );
        state.dispose();
      },
    );

    test('delete and reinstall: local data is gone but saves come back from '
        'a folder outside it', () async {
      final root = await tempDir('ezcore_reinstall_');
      try {
        final appData = Directory('${root.path}/app-data');
        final backup = '${root.path}/outside-app-data/backup';
        final dataProvider = _FixedDataDirProvider(appData.path);

        final first = AppState.internal(
          persistence: PersistenceService(dataProvider),
          saves: LocalSaveSyncProvider(appData),
          backupFolder: BackupFolderService(locator: _AvailableLocator(backup)),
        );
        await first.resolveBackupFolder();
        await first.saves.upload('mario', 'auto', payload([10, 20, 30]));
        await first.persist();

        expect(File('${appData.path}/mario/auto.bin').existsSync(), isTrue);
        expect(File('$backup/saves/mario/auto.bin').existsSync(), isTrue);
        expect(appData.path == backup, isFalse);
        expect(
          backup.startsWith('${appData.path}${Platform.pathSeparator}'),
          isFalse,
          reason: 'the mirror must live outside the app data directory',
        );

        // Uninstall: only the app's own data directory is removed.
        await appData.delete(recursive: true);
        expect(File('${appData.path}/state.json').existsSync(), isFalse);
        expect(File('$backup/saves/mario/auto.bin').existsSync(), isTrue);
        first.dispose();

        // Reinstall: a new state, a new empty local vault, same backup folder.
        final second = AppState.internal(
          persistence: PersistenceService(dataProvider),
          saves: LocalSaveSyncProvider(appData),
          backupFolder: BackupFolderService(locator: _AvailableLocator(backup)),
        );
        await second.resolveBackupFolder();

        expect(second.mirrorOnlySaveCount, 1);
        expect(await second.saves.list('mario'), isNotEmpty);
        expect(
          await second.saves.download('mario', 'auto'),
          payload([10, 20, 30]),
        );

        expect(await second.restoreFromBackup(), 1);
        expect(second.mirrorOnlySaveCount, 0);
        expect(
          await File('${appData.path}/mario/auto.bin').readAsBytes(),
          payload([10, 20, 30]),
        );
        expect(
          await second.saves.download('mario', 'auto'),
          payload([10, 20, 30]),
        );
        second.dispose();
      } finally {
        await root.delete(recursive: true);
      }
    });

    test(
      'a backup folder deleted after being chosen stops claiming to work',
      () async {
        final backup = '${mirror.path}/chosen';
        final service = BackupFolderService(locator: _AvailableLocator(backup));
        final state = AppState.internal(
          persistence: null,
          saves: local,
          backupFolder: service,
        );
        await state.resolveBackupFolder();
        expect(service.status.available, isTrue);
        await state.saves.upload('game-1', 'auto', payload([1]));

        await Directory(backup).delete(recursive: true);
        await state.saves.upload('game-1', 'again', payload([2]));

        expect(service.status.available, isFalse);
        expect(service.status.reason, contains('no longer on this device'));
        expect(
          Directory(backup).existsSync(),
          isFalse,
          reason: 'a lost folder must not be silently recreated as empty',
        );
        expect(await state.saves.download('game-1', 'again'), payload([2]));
        state.dispose();
      },
    );

    test('an unwritable backup folder is reported instead of hidden', () async {
      final backup = '${mirror.path}/chosen';
      final service = BackupFolderService(locator: _AvailableLocator(backup));
      final state = AppState.internal(
        persistence: null,
        saves: local,
        backupFolder: service,
      );
      await state.resolveBackupFolder();
      await state.saves.upload('game-1', 'auto', payload([1]));

      await Directory('$backup/saves').delete(recursive: true);
      await File('$backup/saves').writeAsString('not a folder');
      await state.saves.upload('game-1', 'again', payload([2]));

      expect(service.status.available, isFalse);
      expect(service.status.reason, contains('writable'));
      expect(await state.saves.download('game-1', 'again'), payload([2]));
      state.dispose();
    });

    testWidgets('the app boots and can save with no backup folder at all', (
      tester,
    ) async {
      final state = AppState.internal(
        persistence: null,
        saves: LocalSaveSyncProvider(primary),
        backupFolder: BackupFolderService.disabled(),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: SettingsScreen(state: state, initialTab: 'Storage'),
        ),
      );

      await tester.runAsync(() => state.load());
      await tester.pump();
      await tester.runAsync(() => state.resolveBackupFolder());
      await tester.pump();

      expect(state.loaded, isTrue);
      expect(state.saves, isNot(isA<MirroredSaveSyncProvider>()));
      await tester.runAsync(
        () => state.saves.upload('game-1', 'auto', payload([1, 2, 3])),
      );
      final saved = await tester.runAsync(
        () => state.saves.download('game-1', 'auto'),
      );
      expect(saved, payload([1, 2, 3]));
      expect(find.text('Save backup folder'), findsOneWidget);
      state.dispose();
    });
  });

  group('Storage settings', () {
    testWidgets('reports mirroring and offers restore for backup-only saves', (
      tester,
    ) async {
      final backup = '${mirror.path}/backup';
      // Leave one save in the backup but not in the primary vault.
      final orphan = MirroredSaveSyncProvider(local, Directory(backup));
      await tester.runAsync(
        () => orphan.upload('game-1', 'auto', payload([6, 7])),
      );
      await tester.runAsync(() => primary.delete(recursive: true));

      final state = AppState.internal(
        persistence: null,
        saves: local,
        backupFolder: BackupFolderService(locator: _AvailableLocator(backup)),
      );
      await tester.runAsync(() => state.resolveBackupFolder());
      expect(state.mirrorOnlySaveCount, 1);

      await tester.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: SettingsScreen(state: state, initialTab: 'Storage'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Saves are mirrored here'), findsOneWidget);
      expect(
        find.textContaining('1 save found only in the backup'),
        findsOneWidget,
      );
      expect(find.text('Restore from backup'), findsOneWidget);

      await tester.runAsync(() => state.restoreFromBackup());
      await tester.pump();
      expect(state.mirrorOnlySaveCount, 0);
      final restored = await tester.runAsync(
        () => local.download('game-1', 'auto'),
      );
      expect(restored, payload([6, 7]));
      expect(find.text('Restore from backup'), findsNothing);
      state.dispose();
    });

    testWidgets('a folder that stops working says Unavailable, a session with '
        'no backup source keeps saying Not set', (tester) async {
      final backup = '${mirror.path}/backup';
      final service = BackupFolderService(locator: _AvailableLocator(backup));
      final broken = AppState.internal(
        persistence: null,
        saves: local,
        backupFolder: service,
      );
      await tester.runAsync(() => broken.resolveBackupFolder());
      expect(service.status.available, isTrue);
      await tester.runAsync(
        () => broken.saves.upload('game-1', 'auto', payload([8])),
      );

      // The folder disappears after it was chosen; the next save reports it.
      await tester.runAsync(() => Directory(backup).delete(recursive: true));
      await tester.runAsync(
        () => broken.saves.upload('game-1', 'again', payload([9])),
      );
      expect(service.status.available, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: SettingsScreen(state: broken, initialTab: 'Storage'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.textContaining('no longer on this device'), findsOneWidget);
      broken.dispose();

      // A session with no backup source never had a folder to lose, so its
      // row must not borrow the failure wording.
      final disabled = AppState.internal(
        persistence: null,
        saves: local,
        backupFolder: BackupFolderService.disabled(),
      );
      await tester.runAsync(() => disabled.resolveBackupFolder());
      await tester.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: SettingsScreen(state: disabled, initialTab: 'Storage'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Unavailable'),
        findsNothing,
        reason: 'no backup source is "not set", not "unavailable"',
      );
      expect(
        find.textContaining('Backup folders are not used'),
        findsOneWidget,
      );
      disabled.dispose();
    });
  });
}
