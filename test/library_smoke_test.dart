import 'package:ezcore/widgets/collection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';

void main() {
  const games = [
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

  Future<void> pump(WidgetTester tester, AppState state) async {
    await state.setSetting(libraryViewKey, CollectionView.grid.value);
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('library renders persisted games and searches', (tester) async {
    // Set games directly to avoid rootBundle catalog load in test env
    final state = AppState.ephemeral()..games = games;
    await pump(tester, state);
    expect(find.text('My GBA Dump'), findsWidgets);
    expect(find.text('My SNES Dump'), findsWidgets);
    expect(find.text('All games'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'snes');
    await tester.pumpAndSettle();
    expect(find.text('My SNES Dump'), findsWidgets);
    expect(find.text('My GBA Dump'), findsNothing);
  });

  testWidgets('a system filter shows that system only', (tester) async {
    final state = AppState.ephemeral()..games = games;
    await pump(tester, state);
    // Test text is wide (Ahem): bring the tab into view first.
    final tab = find.text('Game Boy Advance').first; // the header's tab
    await tester.ensureVisible(tab);
    await tester.pumpAndSettle();
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(find.text('My GBA Dump'), findsWidgets);
    expect(find.text('My SNES Dump'), findsNothing);
  });
}
