// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/services/backup_folder.dart';
import 'package:ezcore/services/mirrored_saves.dart';
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

void main() {
  late Directory primary;
  late Directory mirror;
  late LocalSaveSyncProvider local;
  late MirroredSaveSyncProvider provider;

  setUp(() async {
    primary = await tempDir('ezcore_mirror_primary_');
    mirror = await tempDir('ezcore_mirror_backup_');
    local = LocalSaveSyncProvider(primary);
    provider = MirroredSaveSyncProvider(
      local,
      mirror,
      appVersion: '9.9.9',
    );
  });

  tearDown(() async {
    if (primary.existsSync()) await primary.delete(recursive: true);
    if (mirror.existsSync()) await mirror.delete(recursive: true);
  });

  Future<List<dynamic>> readIndex([Directory? root]) {
    final file = File('${(root ?? mirror).path}/saves/index.json');
    return file.readAsString().then((text) => json.decode(text) as List<dynamic>);
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

    test('list unions primary and mirror, and the primary wins a conflict',
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
      expect((await provider.mirrorOnlySlots()).map((r) => r.slot), ['orphan']);
    });

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

    test('restoreFromMirror copies mirror-only saves into the primary',
        () async {
      await provider.upload('game-1', 'auto', payload([7, 8]));
      // Simulate a reinstall: the local vault is gone, the backup survives.
      await primary.delete(recursive: true);
      expect(await local.download('game-1', 'auto'), isNull);
      expect((await provider.mirrorOnlySlots()).single.slot, 'auto');

      expect(await provider.restoreFromMirror(), 1);

      expect(await local.download('game-1', 'auto'), payload([7, 8]));
      expect(await provider.mirrorOnlySlots(), isEmpty);
    });

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
  });

  group('AppState wiring', () {
    test('no backup folder keeps the plain provider and writes no mirror',
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
    });

    test('an available backup folder turns the provider into a mirror',
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
  });
}
