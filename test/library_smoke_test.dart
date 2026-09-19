import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';

void main() {
  testWidgets('library renders persisted games and filters', (tester) async {
    // Set games directly to avoid rootBundle catalog load in test env
    final state = AppState();
    state.games = const [
      GameEntry(
        id: 'g3',
        title: 'My GBA Dump',
        system: 'gba',
        filePath: '~/Games/gba/mydump.gba',
        extension: 'gba',
        coreId: 'advancebit',
      ),
      GameEntry(
        id: 'g4',
        title: 'My SNES Dump',
        system: 'snes',
        filePath: '~/Games/snes/mydump.sfc',
        extension: 'sfc',
        coreId: 'superfx',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    // Orbit CoverFlow shows titles on covers + selected title in the dock.
    expect(find.text('My GBA Dump'), findsWidgets);
    expect(find.text('My SNES Dump'), findsWidgets);
    expect(find.text('The collection'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'snes');
    await tester.pumpAndSettle();
    expect(find.text('My SNES Dump'), findsWidgets);
    expect(find.text('My GBA Dump'), findsNothing);
  });

  testWidgets('grid view toggle lists every game once per card', (tester) async {
    final state = AppState();
    state.games = const [
      GameEntry(
        id: 'g3',
        title: 'My GBA Dump',
        system: 'gba',
        filePath: '~/Games/gba/mydump.gba',
        extension: 'gba',
        coreId: 'advancebit',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    // Grid card shows the title on the cover fallback + the label below.
    expect(find.text('My GBA Dump'), findsWidgets);
  });
}
