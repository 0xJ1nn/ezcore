import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';

/// "ezCORE ROMs" folder feature: the one-time offer dialog, the managed
/// folder state, and copy-into-one-place behavior wired into scans.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsRoot;

  /// State whose Documents root is a temp dir — never touches the real
  /// user Documents directory.
  AppState makeState() {
    docsRoot = Directory.systemTemp.createTempSync('ezcore_docs');
    return AppState.ephemeral(documentsProvider: () async => docsRoot);
  }

  String inFolder(String folder, String name) =>
      '$folder${Platform.pathSeparator}$name';

  GameEntry game(String id) => GameEntry(
        id: id,
        title: id,
        system: 'nes',
        filePath: '/elsewhere/$id.nes',
        extension: 'nes',
      );

  /// Temp dir for source files that live *outside* the managed folder.
  Directory makeSrcDir(String tag) {
    final d = Directory.systemTemp.createTempSync(tag);
    addTearDown(() {
      if (d.existsSync()) d.deleteSync(recursive: true);
    });
    return d;
  }

  tearDown(() {
    if (docsRoot.existsSync()) docsRoot.deleteSync(recursive: true);
  });

  group('managed folder state', () {
    test('create registers the folder, watches it, answers the prompt',
        () async {
      final state = makeState();
      expect(state.ezcoreRomsFolder, isNull);
      expect(state.romsFolderPrompted, isFalse);

      final dir = await state.createEzcoreRomsFolder();

      expect(Directory(dir).existsSync(), isTrue);
      expect(dir.endsWith('ezCORE ROMs'), isTrue);
      expect(state.ezcoreRomsFolder, dir);
      expect(state.romFolders, contains(dir));
      expect(state.romsFolderPrompted, isTrue);

      // Idempotent: no duplicate watch entries.
      await state.createEzcoreRomsFolder();
      expect(state.romFolders.where((f) => f == dir).length, 1);
    });

    test('decline answers the prompt without creating anything', () async {
      final state = makeState();
      await state.declineEzcoreRomsFolder();

      expect(state.romsFolderPrompted, isTrue);
      expect(state.ezcoreRomsFolder, isNull);
      expect(state.romFolders, isEmpty);
      expect(
        Directory(inFolder(docsRoot.path, 'ezCORE ROMs')).existsSync(),
        isFalse,
      );
    });

    test('copy is identity without an opted-in folder', () async {
      final state = makeState();
      final src = File('${makeSrcDir('ezcore_out').path}/game.nes')
        ..writeAsStringSync('bytes');

      final out = await state.copyGamesIntoRomsFolder([src.path]);

      expect(out, [src.path]);
    });

    test('copies an external file into the folder, source untouched',
        () async {
      final state = makeState();
      final folder = await state.createEzcoreRomsFolder();
      final src = File('${makeSrcDir('ezcore_ext').path}/game.nes')
        ..writeAsStringSync('game-bytes');

      final out = await state.copyGamesIntoRomsFolder([src.path]);

      expect(out.single, inFolder(folder, 'game.nes'));
      expect(File(out.single).readAsStringSync(), 'game-bytes');
      expect(src.existsSync(), isTrue); // copy, not move
    });

    test('directories and missing paths pass through untouched', () async {
      final state = makeState();
      await state.createEzcoreRomsFolder();
      final d = makeSrcDir('ezcore_pass');
      final missing = '${d.path}${Platform.pathSeparator}gone.nes';

      final out = await state.copyGamesIntoRomsFolder([d.path, missing]);

      expect(out, [d.path, missing]);
      expect(File(missing).existsSync(), isFalse);
    });

    test('re-picking the same external file reuses the existing copy',
        () async {
      final state = makeState();
      final folder = await state.createEzcoreRomsFolder();
      final src = File('${makeSrcDir('ezcore_repick').path}/game.nes')
        ..writeAsStringSync('identical-bytes');

      final first = await state.copyGamesIntoRomsFolder([src.path]);
      final second = await state.copyGamesIntoRomsFolder([src.path]);

      expect(second.single, first.single);
      expect(Directory(folder).listSync().length, 1); // no " (2)" litter
    });

    test('same name with different content gets a " (2)" suffix '
        '(SHA decides, not size)', () async {
      final state = makeState();
      final folder = await state.createEzcoreRomsFolder();
      final a =
          File('${makeSrcDir('ezcore_a').path}/game.nes')
            ..writeAsStringSync('AAAA'); // same length as BBBB
      final b = File('${makeSrcDir('ezcore_b').path}/game.nes')
        ..writeAsStringSync('BBBB');

      final first = await state.copyGamesIntoRomsFolder([a.path]);
      final second = await state.copyGamesIntoRomsFolder([b.path]);

      expect(first.single, inFolder(folder, 'game.nes'));
      expect(second.single, inFolder(folder, 'game (2).nes'));
      expect(File(first.single).readAsStringSync(), 'AAAA');
      expect(File(second.single).readAsStringSync(), 'BBBB');
    });
  });

  group('one-time offer dialog', () {
    testWidgets('shows for a loaded library; create wires folder and '
        'never asks again', (tester) async {
      final state = makeState();
      state.games.add(game('g1'));

      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('roms-folder-create')), findsOneWidget);
      expect(
        find.textContaining('copy all the ROMs there'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('roms-folder-create')));
      await tester.pumpAndSettle();

      expect(state.romsFolderPrompted, isTrue);
      expect(state.ezcoreRomsFolder, isNotNull);
      expect(state.romFolders, contains(state.ezcoreRomsFolder));
      expect(find.textContaining('folder created'), findsOneWidget);

      // A fresh ImportScreen stays dialog-free.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roms-folder-create')), findsNothing);
      expect(state.romFolders.length, 1);
    });

    testWidgets('decline records the answer and stays silent after',
        (tester) async {
      final state = makeState();
      state.games.add(game('g1'));

      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roms-folder-later')), findsOneWidget);

      await tester.tap(find.byKey(const Key('roms-folder-later')));
      await tester.pumpAndSettle();

      expect(state.romsFolderPrompted, isTrue);
      expect(state.ezcoreRomsFolder, isNull);
      expect(state.romFolders, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roms-folder-later')), findsNothing);
    });

    testWidgets('a fresh library never sees the offer', (tester) async {
      final state = makeState(); // games stay empty

      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('roms-folder-create')), findsNothing);
      expect(find.byKey(const Key('roms-folder-later')), findsNothing);
      expect(state.romsFolderPrompted, isFalse);
    });
  });

  group('scan wiring', () {
    testWidgets('with the folder active, a typed external file is copied '
        'home before import', (tester) async {
      final state = makeState();
      // load() first — it rebuilds _settings from persistence — then
      // create the managed folder so the keys survive. Real I/O must
      // run inside runAsync (widget tests fake the clock).
      late String folder;
      await tester.runAsync(() async {
        await state.load();
        folder = await state.createEzcoreRomsFolder();
      });

      // Valid GBA fixture (logo magic at 0x04, size >= 512).
      final bytes = List<int>.filled(4096, 0xFF);
      const magic = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];
      for (var i = 0; i < magic.length; i++) {
        bytes[0x04 + i] = magic[i];
      }
      final src = File(
          '${makeSrcDir('ezcore_scan').path}${Platform.pathSeparator}fixture.gba')
        ..writeAsBytesSync(bytes);

      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();
      // Prompt already answered — no dialog over the scan flow.
      expect(find.byKey(const Key('roms-folder-create')), findsNothing);

      await tester.enterText(
          find.byKey(const Key('import-path-field')), src.path);
      await tester.runAsync(() async {
        await tester.tap(find.text('Scan typed path'));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.text('Ready to import').evaluate().isNotEmpty) break;
        }
      });

      expect(find.text('Ready to import'), findsOneWidget);
      // The scan copied the file home before importing:
      expect(
        File(inFolder(folder, 'fixture.gba')).existsSync(),
        isTrue,
      );

      // The watched-folder chip (the managed folder itself) pushes the
      // import button below the fold — ListView builds lazily.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import scanned content'));
      await tester.pumpAndSettle();

      expect(state.games, hasLength(1));
      expect(state.games.single.filePath, startsWith(folder));
    });
  });
}
