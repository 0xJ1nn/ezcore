// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:ezcore/brand/brand_mark.dart';
import 'package:ezcore/main.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/screens/onboarding_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/collection_view.dart' show libraryViewKey;
import 'package:ezcore/widgets/library_header.dart' show LibraryLook;
import 'package:ezcore/widgets/onboarding_look_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Tokens.theme(),
  home: home,
);

/// The gate the app uses: once loading finishes, first run replaces the shell
/// only while the library is empty and the answer has not been saved.
Widget _gated(AppState state) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: Tokens.theme(),
  home: ListenableBuilder(
    listenable: state,
    builder: (context, _) => FirstRunGate(
      state: state,
      shell: (_) => const Scaffold(body: Center(child: Text('Library'))),
    ),
  ),
);

void main() {
  group('first-run gate', () {
    test('is due with an empty library and no saved answer', () {
      final state = AppState.ephemeral();
      expect(OnboardingScreen.shouldShow(state), isTrue);
    });

    test('a finished first run keeps the empty library', () async {
      final state = AppState.ephemeral();
      await state.setSetting(OnboardingScreen.completeKey, true);
      expect(OnboardingScreen.shouldShow(state), isFalse);
    });

    test('an existing collection skips first run', () {
      final state = AppState.ephemeral()
        ..games = const [
          GameEntry(
            id: 'lanterns',
            title: 'Lanterns of Vell',
            system: 'nds',
            filePath: '/Games/lanterns.nds',
            extension: 'nds',
          ),
        ];
      expect(OnboardingScreen.shouldShow(state), isFalse);
    });

    testWidgets('does not flash before loading finishes', (tester) async {
      final state = AppState.ephemeral();
      await tester.pumpWidget(_gated(state));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      // Loading itself belongs to app startup; a loaded state makes the
      // gate's decision, so rebuild with the flag set.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_gated(AppState.ephemeral()..loaded = true));
      await tester.pump();
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });

  testWidgets('welcome shows the mark and advances to the input step', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await tester.pumpWidget(_app(OnboardingScreen(state: state)));

    expect(find.byType(BrandMark), findsWidgets);
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Controller connected'), findsOneWidget);
    expect(find.textContaining('Ready when you are.'), findsOneWidget);
    expect(
      find.textContaining('Everything in ezCORE works from here.'),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.sportsEsports), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('the look step previews every look and remembers the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState.ephemeral();
    await tester.pumpWidget(
      _app(OnboardingScreen(state: state, initialStep: 2)),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Pick a look for your collection'), findsOneWidget);
    expect(find.byType(OnboardingLookPicker), findsOneWidget);
    for (final look in LibraryLook.values) {
      expect(find.byKey(Key('look-card-${look.value}')), findsOneWidget);
    }
    expect(find.byKey(const Key('look-check-3d')), findsOneWidget);
    expect(find.byKey(const Key('look-check-shelf')), findsNothing);

    // The chosen look gets the full-width card; the rest are compact.
    expect(
      tester.getSize(find.byKey(const Key('look-card-3d'))),
      const Size(358, 170),
    );
    expect(
      tester.getSize(find.byKey(const Key('look-card-shelf'))),
      const Size(174, 128),
    );

    await tester.tap(find.byKey(const Key('look-card-shelf')));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('look-check-shelf')), findsOneWidget);
    expect(find.byKey(const Key('look-check-3d')), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(state.settings[libraryViewKey], 'shelf');
    expect(find.text('Where are your games?'), findsOneWidget);
  });

  testWidgets('the active dot is the 24 px step marker', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(OnboardingScreen(state: AppState.ephemeral(), initialStep: 2)),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.getSize(find.byKey(const Key('step-dot-2'))).width, 24);
    expect(tester.getSize(find.byKey(const Key('step-dot-0'))).width, 6);
    expect(tester.getSize(find.byKey(const Key('step-dot-3'))).width, 6);
  });

  testWidgets('Not now finishes first run and lands on the library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState.ephemeral()..loaded = true;
    await tester.pumpWidget(_gated(state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Where are your games?'), findsOneWidget);
    expect(find.text('Choose a folder'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(state.settings[OnboardingScreen.completeKey], isTrue);
    expect(OnboardingScreen.shouldShow(state), isFalse);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });

  testWidgets('Choose a folder opens Import and records the answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState.ephemeral();
    await tester.pumpWidget(
      _app(OnboardingScreen(state: state, initialStep: 3)),
    );
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.text('Choose a folder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ImportScreen), findsOneWidget);
    expect(state.settings[OnboardingScreen.completeKey], isTrue);
  });

  testWidgets('the look cards keep five 200 px previews in one row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 1160,
              child: OnboardingLookPicker(
                selected: LibraryLook.grid,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final look in LibraryLook.values) {
      expect(find.byKey(Key('look-card-${look.value}')), findsOneWidget);
    }
    expect(tester.getSize(find.byKey(const Key('look-card-grid'))).width, 200);
    expect(find.byKey(const Key('look-check-grid')), findsOneWidget);
  });
}
