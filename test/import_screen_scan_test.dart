import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/services/content_importer.dart';
import 'package:ezcore/state/app_state.dart';

/// The Scan and Review steps present the importer's outcomes: the radar
/// count, the progress line, the mono file log with its four statuses, and
/// the review list with its summary and actions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Production ships its bundled cores; a bare test state has none, so a
  /// "ready" row would read as "needs a system".
  void installCore(AppState state, String id) {
    for (final m in state.registry.catalog) {
      if (m.id != id) continue;
      state.registry.install(
        m,
        expectedSha256: m.artifacts.values.isEmpty
            ? 'test'
            : m.artifacts.values.first,
      );
      return;
    }
  }

  const mb = 1 << 20;

  GameEntry game(String path, String system, String core, int bytes) =>
      GameEntry(
        id: 'test-$path',
        title: path,
        system: system,
        filePath: path,
        extension: path.split('.').last,
        fileSize: bytes,
        coreId: core,
      );

  ImportResult ready(String path, String system, String core, int bytes) =>
      ImportResult(
        filePath: path,
        game: game(path, system, core, bytes),
      );

  ImportResult duplicate(String path) =>
      ImportResult(filePath: path, skippedReason: 'Duplicate (already in library)');

  ImportResult noCore(String path, String system) => ImportResult(
        filePath: path,
        game: game(path, system, 'not-installed', 0),
      );

  ImportResult notGame(String path) => ImportResult(
        filePath: path,
        skippedReason: 'No core for extension .txt',
      );

  final results = [
    ready('Games/GBA/ember-circuit.gba', 'gba', 'advancebit', 16 * mb),
    ready('Games/SNES/riverlight (USA).sfc', 'snes', 'superfx', 4 * mb),
    ready('Games/NDS/paper_lunar.nds', 'nds', 'dualscreen', 128 * mb),
    duplicate('Games/GBA/starfall_courier.gba'),
    noCore('Games/GC/tide-engine.iso', 'gc'),
    notGame('Games/misc/readme.txt'),
  ];

  Future<AppState> stateWithFolder(WidgetTester tester) async {
    final state = AppState.ephemeral();
    await tester.runAsync(() async {
      await state.load();
      installCore(state, 'advancebit');
      installCore(state, 'superfx');
      installCore(state, 'dualscreen');
      await state.addRomFolder('/Games');
    });
    return state;
  }

  Future<void> start(WidgetTester tester, ImportScreen screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-source-watched')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('scan shows the radar, progress and the four file statuses',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = await stateWithFolder(tester);
    await start(
      tester,
      ImportScreen(
        state: state,
        scanFixture: ImportScanFixture(
          root: '~/Games',
          pct: 0.64,
          hold: true,
          results: results,
        ),
      ),
    );

    expect(find.text('Looking for games…'), findsOneWidget);
    expect(find.text('games found'), findsOneWidget);
    // Five of the six files are games (readme.txt is not).
    expect(find.text('5'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Scanning ~/Games'), findsOneWidget);
    expect(find.text('Games/NDS/paper_lunar.nds'), findsOneWidget);
    expect(find.text('New'), findsNWidgets(3));
    expect(find.text('Already in collection'), findsOneWidget);
    expect(find.text('No system installed'), findsOneWidget);
    expect(find.text('Not a game'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('scan advances to review with the summary and actions',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = await stateWithFolder(tester);
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        state: state,
        scanFixture: ImportScanFixture(root: '~/Games', results: results),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('import-source-watched')));
    // The scan wait is the progress animation's 2.2 s.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.text('Here’s what I found'), findsOneWidget);
    expect(find.text('3 new'), findsOneWidget);
    expect(find.text('Add 3 games'), findsOneWidget);
    expect(find.text('Choose a different folder'), findsOneWidget);
    expect(find.text('Ready'), findsNWidgets(3));
    expect(find.text('Already added'), findsOneWidget);
    expect(find.text('Skipped'), findsOneWidget);
    // The region tag is metadata, not part of the title.
    expect(find.text('Riverlight'), findsOneWidget);
    expect(find.text('riverlight (USA).sfc'), findsNothing);
    expect(find.textContaining('One file was already in your collection'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
