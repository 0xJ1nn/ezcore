import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'font_loading.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;

  List<GameEntry> fixtureGames() => [
    GameEntry(
      id: 'lanterns',
      title: 'Lanterns of Vell',
      system: 'nds',
      filePath: 'Games/lanterns.nds',
      extension: 'nds',
      coreId: 'dualscreen',
      favorite: true,
      lastPlayedMs: now - 7 * 3600 * 1000,
    ),
    GameEntry(
      id: 'aurora',
      title: 'Aurora Run',
      system: 'gba',
      filePath: 'Games/aurora.gba',
      extension: 'gba',
      coreId: 'advancebit',
      lastPlayedMs: now - 24 * 3600 * 1000,
    ),
    GameEntry(
      id: 'cinder',
      title: 'Cinder & Moss',
      system: 'gb',
      filePath: 'Games/cinder.gb',
      extension: 'gb',
      coreId: 'gambatte',
      lastPlayedMs: now - 7 * 24 * 3600 * 1000,
    ),
    GameEntry(
      id: 'neon',
      title: 'Neon Harbor',
      system: 'dc',
      filePath: 'Games/neon.cdi',
      extension: 'cdi',
      coreId: 'dreamarc',
    ),
  ];

  Finder resultTitle(String id) => find.byKey(Key('search-result-title-$id'));

  /// The library stays mounted behind the overlay, so scope copy that exists
  /// on both surfaces to the overlay itself.
  Finder inOverlay(Finder finder) =>
      find.descendant(of: find.byType(SearchOverlay), matching: finder);

  setUpAll(() async {
    await loadBundledFonts();
  });

  /// The caret blinks forever, so `pumpAndSettle` never goes idle. Pump a real
  /// slice of time instead; the open transition and field animation are short.
  Future<void> settleOverlay(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpLibrary(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.ephemeral()..games = fixtureGames();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('/ opens the full search overlay with its keys and recents', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);

    expect(inOverlay(find.text('FIND A GAME')), findsOneWidget);
    expect(find.byKey(const Key('search-overlay-field')), findsOneWidget);
    expect(inOverlay(find.text('Type a title or a system')), findsOneWidget);
    expect(inOverlay(find.text('RECENTLY PLAYED')), findsOneWidget);
    expect(resultTitle('lanterns'), findsOneWidget);
    expect(resultTitle('cinder'), findsOneWidget);
    expect(inOverlay(find.text('A')), findsOneWidget);
    expect(inOverlay(find.text('Space')), findsOneWidget);
    expect(
      inOverlay(
        find.text(
          'Or type on any keyboard. Titles and systems both match, so “gba” works too.',
        ),
      ),
      findsOneWidget,
    );
    expect(inOverlay(find.text('Enter')), findsOneWidget);
    expect(inOverlay(find.text('Close')), findsOneWidget);
  });

  testWidgets('typing filters titles and system names live', (tester) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);

    await tester.enterText(
      find.byKey(const Key('search-overlay-field')),
      'moss',
    );
    await settleOverlay(tester);

    expect(inOverlay(find.text('1 MATCH')), findsOneWidget);
    expect(resultTitle('cinder'), findsOneWidget);
    expect(resultTitle('lanterns'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('search-overlay-field')),
      'game boy',
    );
    await settleOverlay(tester);
    expect(resultTitle('aurora'), findsOneWidget);
    expect(resultTitle('cinder'), findsOneWidget);
    expect(resultTitle('lanterns'), findsNothing);
  });

  testWidgets('Esc closes the overlay', (tester) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);
    expect(find.text('FIND A GAME'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleOverlay(tester);
    expect(find.text('FIND A GAME'), findsNothing);
  });

  testWidgets('a letter opens search pre-filled', (tester) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settleOverlay(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('search-overlay-field')),
    );
    expect(field.controller?.text, 'm');
    expect(resultTitle('cinder'), findsOneWidget);
  });

  testWidgets('no matches shows the empty card and system suggestions', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);
    await tester.enterText(
      find.byKey(const Key('search-overlay-field')),
      'zelta',
    );
    await settleOverlay(tester);

    expect(inOverlay(find.text('Nothing called “zelta”')), findsOneWidget);
    expect(inOverlay(find.textContaining('Check the spelling')), findsOneWidget);
    expect(inOverlay(find.text('GBA')), findsOneWidget);
    expect(inOverlay(find.text('Favorites')), findsOneWidget);
  });

  testWidgets('on-screen keys type into the field', (tester) async {
    await pumpLibrary(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);

    await tester.tap(find.text('M'));
    await settleOverlay(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('search-overlay-field')),
    );
    expect(field.controller?.text, 'm');
  });

  testWidgets('phone portrait uses the system keyboard layout', (tester) async {
    await pumpLibrary(tester, size: const Size(390, 844));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await settleOverlay(tester);

    expect(inOverlay(find.text('Cancel')), findsOneWidget);
    expect(find.byKey(const Key('search-overlay-field')), findsOneWidget);
    // No on-screen grid and no keyboard legend on touch.
    expect(inOverlay(find.text('Space')), findsNothing);
    expect(inOverlay(find.text('Enter')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('search-overlay-field')),
      'zelta',
    );
    await settleOverlay(tester);
    expect(find.text('Nothing called “zelta”'), findsOneWidget);
  });

  testWidgets('choosing a result returns that game', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = ValueNotifier<GameEntry?>(null);
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked.value = await showSearchOverlay(
                  context,
                  games: fixtureGames(),
                );
              },
              child: const Text('open search'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open search'));
    await settleOverlay(tester);

    await tester.tap(resultTitle('aurora'));
    await settleOverlay(tester);
    expect(picked.value?.id, 'aurora');
  });
}
