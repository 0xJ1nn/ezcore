// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// The TV / ultrawide / handheld modifiers are measurements layered on the
// five layout families. These tests pin both the input rules (§10) and the
// numbers the chrome uses, without adding new OrbitLayout values.
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/core_manager_screen.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/main.dart';
import 'package:ezcore/theme/layout.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/cover_flow.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/library_header.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tv = Size(1920, 1080);
  const ultrawide = Size(2560, 1080);
  const handheld = Size(1280, 800);
  const desktop = Size(1440, 900);

  setUp(() => InputMode.shared.reset());
  tearDown(() => InputMode.shared.reset());

  group('InputMode', () {
    test(
      'a desktop window stays plain until a pad or a big screen says TV',
      () {
        final mode = InputMode.shared;
        expect(
          mode.resolve(desktop, Orientation.landscape),
          LayoutModifier.none,
        );
        expect(mode.resolve(tv, Orientation.landscape), LayoutModifier.tv);
        expect(
          mode.resolve(ultrawide, Orientation.landscape),
          LayoutModifier.ultrawide,
        );
        expect(
          mode.resolve(handheld, Orientation.landscape),
          LayoutModifier.handheld,
        );
      },
    );

    test('a seen pointer suppresses the TV and handheld modifiers', () {
      final mode = InputMode.shared;
      mode.notePointer();
      expect(mode.pointerSeen, isTrue);
      expect(mode.resolve(tv, Orientation.landscape), LayoutModifier.none);
      expect(mode.lastSource, OrbitInputSource.pointer);
    });

    test('a connected pad makes a desktop window a TV', () {
      final mode = InputMode.shared;
      mode.notePad('Xbox Wireless Controller');
      expect(mode.padConnected, isTrue);
      expect(mode.resolve(desktop, Orientation.landscape), LayoutModifier.tv);
      expect(mode.lastSource, OrbitInputSource.pad);
      mode.notePad(null);
      expect(mode.resolve(desktop, Orientation.landscape), LayoutModifier.none);
    });

    test('the setting forces a modifier even with a mouse in the room', () {
      final mode = InputMode.shared;
      mode.notePointer();
      mode.syncFromSettings({'ui.inputMode': 'tv'});
      expect(mode.forced, 'tv');
      expect(mode.resolve(desktop, Orientation.landscape), LayoutModifier.tv);
      mode.syncFromSettings({'ui.inputMode': 'auto'});
      expect(mode.forced, isNull);
      expect(mode.resolve(desktop, Orientation.landscape), LayoutModifier.none);
    });

    test('every input writes to one last-source owner', () {
      final mode = InputMode.shared;
      mode.notePad('DualSense');
      mode.noteKeyboard();
      expect(mode.lastSource, OrbitInputSource.keyboard);
      expect(mode.padConnected, isTrue, reason: 'a pad stays connected');
    });
  });

  group('Layout modifier measurements', () {
    test('no new layout family is needed', () {
      expect(OrbitLayout.values, hasLength(5));
      expect(
        Layout.ofSize(desktop, Orientation.landscape),
        OrbitLayout.desktop,
      );
      expect(
        Layout.ofSize(ultrawide, Orientation.landscape),
        OrbitLayout.desktop,
      );
      expect(
        Layout.ofSize(handheld, Orientation.landscape),
        OrbitLayout.desktop,
      );
    });

    test('rail, type, safe area and content cap', () {
      expect(Layout.railWidth(OrbitLayout.desktop, LayoutModifier.tv), 136);
      expect(
        Layout.railWidth(OrbitLayout.desktop, LayoutModifier.handheld),
        Tokens.railShort,
      );
      expect(
        Layout.railWidth(OrbitLayout.tablet, LayoutModifier.none),
        Tokens.rail,
      );
      expect(Layout.typeScale(LayoutModifier.tv), closeTo(1.33, 1e-9));
      expect(Layout.typeScale(LayoutModifier.handheld), 1.0);
      expect(Layout.safeArea(LayoutModifier.tv), Tokens.s8);
      expect(Layout.safeArea(LayoutModifier.none), 0);
      expect(Layout.contentMaxWidth(LayoutModifier.ultrawide), 1600);
      expect(Layout.contentMaxWidth(LayoutModifier.none), double.infinity);
    });

    test('cover size and neighbours follow the family', () {
      expect(Layout.coverExtent(LayoutModifier.tv, OrbitLayout.desktop), 360);
      expect(
        Layout.coverExtent(LayoutModifier.ultrawide, OrbitLayout.desktop),
        360,
      );
      expect(Layout.coverExtent(LayoutModifier.none, OrbitLayout.desktop), 270);
      expect(Layout.coverNeighbours(LayoutModifier.ultrawide), 7);
      expect(Layout.coverNeighbours(LayoutModifier.none), 6);
    });

    test('pad-first layouts drop hover and keep a readable text floor', () {
      for (final m in [LayoutModifier.tv, LayoutModifier.handheld]) {
        expect(Layout.showHover(m), isFalse);
        expect(Layout.showHintRow(m), isTrue);
      }
      expect(Layout.showHover(LayoutModifier.none), isTrue);
      expect(Layout.textFloor(LayoutModifier.tv), 18);
      expect(Layout.textFloor(LayoutModifier.handheld), 16);
      expect(Layout.textFloor(LayoutModifier.none), 12);
    });
  });

  group('modifier chrome', () {
    testWidgets('the hint row shows the pad glyphs, not keyboard keys', (
      t,
    ) async {
      InputMode.shared.setForced('handheld');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: const Scaffold(
            body: OrbitKeyHints(
              hints: [
                (['Enter'], 'Resume'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(OrbitHintRow), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Enter'), findsNothing);
    });

    testWidgets('a desktop hint row still lists keyboard keys', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: const Scaffold(
            body: OrbitKeyHints(
              hints: [
                (['Enter'], 'Resume'),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(OrbitHintRow), findsNothing);
      expect(find.text('Enter'), findsOneWidget);
    });

    testWidgets('the TV viewport shrinks the virtual window by 1.33', (
      t,
    ) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      Size seen = Size.zero;
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: InputAwareViewport(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.sizeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(seen.width, closeTo(tv.width / 1.33, 0.01));
      expect(seen.height, closeTo(tv.height / 1.33, 0.01));
    });

    testWidgets('nesting a viewport does not scale twice', (t) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      Size seen = Size.zero;
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: InputAwareViewport(
            child: InputAwareViewport(
              child: Builder(
                builder: (context) {
                  seen = MediaQuery.sizeOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen.width, closeTo(tv.width / 1.33, 0.01));
    });

    testWidgets('the shell widens the rail for TV and keeps its actions', (
      t,
    ) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Shell(state: AppState.ephemeral()..loaded = true),
        ),
      );
      final rail = t.widget<OrbitRail>(find.byType(OrbitRail));
      expect(rail.short, isFalse);
      for (final label in ['Library', 'Systems', 'Capsule', 'Settings']) {
        expect(find.text(label), findsWidgets);
      }
    });
  });

  group('modifier-driven screens', () {
    List<GameEntry> games() => [
      for (final id in const ['lanterns', 'aurora', 'turbo', 'cinder'])
        GameEntry(
          id: id,
          title: id,
          system: 'gba',
          filePath: '/$id.gba',
          extension: 'gba',
          coreId: 'advancebit',
          lastPlayedMs: DateTime.now().millisecondsSinceEpoch,
        ),
    ];

    Future<Shell> pumpShell(WidgetTester t, Size size, String mode) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced(mode);
      final s = AppState.ephemeral()..loaded = true;
      s.games = games();
      final shell = Shell(state: s);
      await t.pumpWidget(
        MaterialApp(theme: Tokens.theme(), home: shell),
      );
      // The ambient backdrop animates forever, so settle with one timed pump.
      await t.pump(const Duration(milliseconds: 1500));
      return shell;
    }

    testWidgets('the TV modifier survives the scaled viewport', (t) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      LayoutModifier? seen;
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: InputAwareViewport(
            child: Builder(builder: (context) {
              seen = Layout.modifierOf(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      // The MediaQuery inside the viewport is 1.33 smaller, but screens must
      // still read the outer TV modifier instead of falling back to desktop.
      expect(seen, LayoutModifier.tv);
    });

    testWidgets('the TV library shows a centred fan and a detail bar', (
      t,
    ) async {
      await pumpShell(t, tv, 'tv');
      final flow = t.widget<CoverFlow>(find.byType(CoverFlow));
      expect(flow.neighbours, 3);
      expect(find.byType(GameDock), findsOneWidget);
      expect(find.byType(LibraryChips), findsNothing);
      expect(find.byType(LibrarySearchField), findsNothing);
      expect(find.text('Add games'), findsOneWidget);
      final rail = t.widget<OrbitRail>(find.byType(OrbitRail));
      expect(rail.modifier, LayoutModifier.tv);
      expect(rail.onAddGames, isNotNull);
    });

    testWidgets('handheld uses the compact rail and a collapsed dock', (
      t,
    ) async {
      await pumpShell(t, handheld, 'handheld');
      final rail = t.widget<OrbitRail>(find.byType(OrbitRail));
      expect(rail.short, isTrue);
      expect(rail.modifier, LayoutModifier.handheld);
      expect(find.byType(LibraryChips), findsNothing);
      expect(find.byType(LibrarySearchField), findsNothing);
      expect(find.byType(OrbitHintRow), findsOneWidget);
      expect(find.text('L1△'), findsOneWidget);
      final dock = t.widget<GameDock>(find.byType(GameDock));
      expect(dock.mode, GameDockMode.oneLine);
      expect(dock.showDetails, isFalse);
      expect(dock.showFavorite, isFalse);
      expect(dock.showMore, isFalse);
    });

    testWidgets('ultrawide widens the fan and caps the content', (t) async {
      await pumpShell(t, ultrawide, 'ultrawide');
      final flow = t.widget<CoverFlow>(find.byType(CoverFlow));
      expect(flow.neighbours, 7);
      expect(flow.itemSize.width, 360);
      final dock = t.widget<GameDock>(find.byType(GameDock));
      expect(dock.showDetails, isFalse);
      // The centred content keeps the same fifth rail stop: a pointer-only
      // ultrawide window needs the visible import route too.
      expect(find.text('Add games'), findsOneWidget);
    });

    testWidgets('TV systems keeps the detail panel open on the first card', (
      t,
    ) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      final s = AppState.ephemeral()..loaded = true;
      CoreManifest c(String id, String system) => CoreManifest(
        id: id,
        name: id,
        version: '1.0',
        license: 'GPL-3.0-only',
        systems: [system],
        extensions: const ['bin'],
        cheatFamilies: const [],
        cheatsSupported: false,
        delivery: {Platform.operatingSystem: 'bundled'},
        artifacts: const {'x': 'pin'},
        biosRequired: false,
        biosFiles: const [],
      );
      final nds = c('dualscreen', 'nds');
      final nes = c('nesbyte', 'nes');
      s.registry.loadCatalog({
        for (final core in [nds, nes])
          core.id: jsonEncode(core.toJson()),
      });
      s.registry.install(nds, expectedSha256: 'pin');
      s.registry.install(nes, expectedSha256: 'pin');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: InputAwareViewport(child: CoreManagerScreen(state: s)),
        ),
      );
      await t.pump(const Duration(milliseconds: 1500));
      expect(find.text('Show games'), findsOneWidget);
      expect(find.text('Nintendo DS'), findsWidgets);
      expect(find.text('Super Nintendo'), findsWidgets);
    });

    testWidgets('TV scanning keeps Stop scan and the readout on screen', (
      t,
    ) async {
      t.view.physicalSize = tv;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      InputMode.shared.setForced('tv');
      final s = AppState.ephemeral()..loaded = true;
      await s.addRomFolder('${Platform.environment['HOME']}/Games');
      final fixture = ImportScanFixture(
        root: '~/Games',
        pct: 0.74,
        hold: true,
        results: const [],
      );
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: InputAwareViewport(
            child: ImportScreen(state: s, scanFixture: fixture),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 800));
      await t.tap(find.byKey(const Key('import-source-watched')));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Stop scan'), findsOneWidget);
      expect(find.text('74%'), findsOneWidget);
    });
  });
}
