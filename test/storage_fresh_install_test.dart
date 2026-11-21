import 'dart:io';

import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/services/backup_folder.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings → Storage on a first run: no games, no folders, nothing chosen.
///
/// The rows are the only place a new player learns what ezCORE stores and
/// where. Each one has to say "not set yet" rather than invent a folder, a
/// provider or a count, and the art actions have to work with an empty library
/// instead of claiming it is already covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory data;

  setUp(() {
    data = Directory.systemTemp.createTempSync('ezcore-storage-fresh-');
    PlatformLocalDataDirProvider.pinStartupDir(data.path);
  });

  tearDown(() {
    if (data.existsSync()) data.deleteSync(recursive: true);
  });

  Future<void> pumpStorage(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: SettingsScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage').first);
    await tester.pumpAndSettle();
  }

  AppState freshState() =>
      AppState.ephemeral(backupFolder: BackupFolderService.disabled());

  testWidgets('every Storage row is empty, not invented, on a first run', (
    tester,
  ) async {
    final state = freshState();
    // A real first run resolves the backup folder at boot; do the same here so
    // the row is measured in its settled state, not mid-probe.
    await state.resolveBackupFolder();
    await pumpStorage(tester, state);

    expect(find.text('Games folder'), findsOneWidget);
    expect(find.text('Core directory'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Game art folder'), findsOneWidget);

    // Three "Not set" pills: games folder, art folder and the backup folder.
    // No row invents a path or a provider the player never chose.
    expect(find.text('Not set'), findsNWidgets(3));

    // Lookup is off until the player turns it on, and nothing is uploaded.
    expect(find.text('Look up missing art'), findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any(
            (s) =>
                s.properties.label == 'Look up missing art' &&
                s.properties.toggled == false,
          ),
      isTrue,
      reason: 'art lookup ships off',
    );

    // The backup row explains this session has no folder; it does not name a
    // provider it never found.
    expect(find.text('Save backup folder'), findsOneWidget);
    expect(
      find.textContaining('Backup folders are not used in this session'),
      findsOneWidget,
      reason: 'the row must give the real reason, not a fake provider',
    );

    // Restore only appears when a save exists only in the backup.
    expect(find.text('Restore from backup'), findsNothing);
    expect(find.text('Content policy'), findsOneWidget);
    expect(state.games, isEmpty);
    expect(state.romFolders, isEmpty);
  });

  testWidgets(
    'Find cover art on an empty library says there is nothing to do',
    (tester) async {
      final state = freshState();
      await pumpStorage(tester, state);

      // With lookup off the action refuses and points at the switch.
      await tester.tap(find.text('Find cover art now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Turn on Look up missing art first'), findsOneWidget);

      // Turn lookup on, then run it: an empty library is "No games", which is
      // the opposite of "Every game already has art".
      await tester.tap(find.text('Look up missing art'));
      await tester.pumpAndSettle();
      expect(state.settings['artLookup'], isTrue);

      await tester.tap(find.text('Find cover art now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No games in the library yet'), findsOneWidget);
      expect(find.text('Every game already has art'), findsNothing);
    },
  );

  testWidgets('an unset art folder is not reported as a folder with images', (
    tester,
  ) async {
    final state = freshState();
    await pumpStorage(tester, state);

    expect(
      find.textContaining('Without one, each game shows a generated cover'),
      findsOneWidget,
    );
    expect(state.settings['artFolder'], isNull);
  });

  testWidgets('a library with a game but no art still offers to find it', (
    tester,
  ) async {
    final state = freshState();
    state.addGame(
      const GameEntry(
        id: 'fresh-one',
        title: 'Lanterns of Vell',
        system: 'nes',
        filePath: '/nonexistent/lanterns.nes',
        extension: 'nes',
      ),
    );
    await pumpStorage(tester, state);

    await tester.tap(find.text('Look up missing art'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find cover art now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // One game needs art, so neither empty-library message may appear.
    expect(find.text('No games in the library yet'), findsNothing);
    expect(find.text('Every game already has art'), findsNothing);
  });
}
