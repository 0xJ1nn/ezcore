import 'dart:convert';

import 'package:ezcore/main.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whole-shell responsive gate.
///
/// The screen-level tests in `library_layouts_test.dart` render screens in
/// isolation. That is not enough: the shell adds a command rail, a top bar
/// and (in portrait) a bottom bar, and it is the *combination* that
/// overflowed on a phone. These tests pump the real [Shell] at each
/// studio-plate viewport, because that composition is what users see.
void main() {
  const games = <GameEntry>[
    GameEntry(
      id: 'g1',
      title: 'Metroid Prime',
      system: 'gc',
      filePath: '/games/metroid.gcm',
      extension: 'gcm',
      coreId: 'powercube',
      fileSize: 15728640,
      lastPlayedMs: 1758500000000,
      stateCount: 3,
    ),
    GameEntry(
      id: 'g2',
      title: 'Super Mario World',
      system: 'snes',
      filePath: '/games/smw.sfc',
      extension: 'sfc',
      coreId: 'superfx',
      fileSize: 524288,
      stateCount: 1,
      favorite: true,
    ),
    GameEntry(
      id: 'g3',
      title: 'Sonic the Hedgehog',
      system: 'genesis',
      filePath: '/games/sonic.md',
      extension: 'md',
      coreId: 'blastproc',
    ),
    GameEntry(
      id: 'g4',
      title: 'The Legend of Zelda',
      system: 'snes',
      filePath: '/games/zelda.sfc',
      extension: 'sfc',
      coreId: 'superfx',
      stateCount: 2,
    ),
  ];

  const core = CoreManifest(
    id: 'powercube',
    name: 'PowerCube',
    version: '1.0.0',
    license: 'GPL-2.0-or-later',
    systems: ['gc'],
    extensions: ['gcm', 'iso'],
    cheatFamilies: [],
    cheatsSupported: false,
    delivery: {'linux': 'bundled'},
    artifacts: {'linux-x64': 'test-pin'},
  );

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    final state = AppState()..games = games;
    state.registry.loadCatalog({core.id: jsonEncode(core.toJson())});
    state.registry.install(core, expectedSha256: 'test-pin');
    state.loaded = true;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        debugShowCheckedModeBanner: false,
        home: Shell(key: UniqueKey(), state: state),
      ),
    );
    await tester.pump();
    // Let the still background and the cover-flow settle.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('tiny and short phone shells remain usable', (tester) async {
    for (final size in const [Size(320, 320), Size(360, 480), Size(390, 360)]) {
      await pumpShell(tester, size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'layout overflow at $size',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('short rail keeps accessible touch targets', (tester) async {
    await pumpShell(tester, const Size(640, 320));
    final rail = find.byType(OrbitRail);
    for (final label in [
      'Library',
      'Systems',
      'Continue',
      'Favorites',
      'Capsule',
      'Settings',
    ]) {
      final target = find.descendant(
        of: rail,
        matching: find.bySemanticsLabel(label),
      );
      expect(target, findsOneWidget, reason: label);
      expect(
        tester.getSize(target).height,
        greaterThanOrEqualTo(48),
        reason: '$label target',
      );
    }
  });

  final viewports = <String, Size>{
    'desktop': Size(1600, 1000),
    'small desktop window': Size(1280, 720),
    'tablet': Size(1024, 768),
    'phone landscape': Size(844, 390),
    'short phone landscape': Size(772, 346),
    'compact landscape window': Size(640, 360),
    'very short landscape window': Size(640, 320),
    'phone portrait': Size(390, 844),
    'small phone portrait': Size(360, 640),
  };

  for (final entry in viewports.entries) {
    testWidgets('shell composes without overflow: ${entry.key}', (
      tester,
    ) async {
      await pumpShell(tester, entry.value);
      expect(
        tester.takeException(),
        isNull,
        reason: 'layout overflow at ${entry.value}',
      );
    });
  }

  testWidgets('Settings and populated Systems fit compact landscape shells', (
    tester,
  ) async {
    for (final size in const [Size(844, 390), Size(568, 320)]) {
      await pumpShell(tester, size);
      expect(tester.takeException(), isNull, reason: 'initial shell at $size');
      final rail = find.byType(OrbitRail);
      await tester.tap(
        find.descendant(of: rail, matching: find.text('Settings')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'Settings at $size');

      await tester.tap(
        find.descendant(of: rail, matching: find.text('Systems')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'Systems at $size');
    }
  });

  testWidgets('populated shell fits the 480x320 content width', (tester) async {
    await pumpShell(tester, const Size(480, 320));
    expect(tester.takeException(), isNull, reason: 'initial Library shell');

    final rail = find.byType(OrbitRail);
    for (final label in ['Systems', 'Capsule', 'Settings']) {
      await tester.tap(find.descendant(of: rail, matching: find.text(label)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$label at 480x320');
    }
  });

  testWidgets('phone portrait uses the bottom command bar', (tester) async {
    await pumpShell(tester, const Size(390, 844));
    expect(find.byType(OrbitBottomNav), findsOneWidget);
    expect(find.byType(OrbitRail), findsNothing);
    // The bar carries the same four spaces as the rail.
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('portrait tablet keeps the rail and library hub', (tester) async {
    await pumpShell(tester, const Size(834, 1194));
    expect(tester.takeException(), isNull);
    expect(find.byType(OrbitRail), findsOneWidget);
    expect(find.byType(OrbitBottomNav), findsNothing);
    expect(find.text('Continue playing'), findsOneWidget);
  });

  testWidgets('desktop rail routes to continue and favorite collections', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1600, 1000));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Favorites'), findsWidgets);

    await tester.tap(find.text('Favorites').first);
    // The space background animates continuously, so settle is never reached.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('1 game'), findsOneWidget);
    expect(find.text('Super Mario World'), findsWidgets);
  });

  testWidgets('Library collection changes keep the shell filter in sync', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1600, 1000));
    final rail = find.byType(OrbitRail);
    final favorites = find.descendant(
      of: rail,
      matching: find.text('Favorites'),
    );

    await tester.tap(favorites);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<OrbitRail>(rail).page, 'favorites');

    await tester.tap(
      find.descendant(
        of: find.byType(LibraryScreen),
        matching: find.text('All systems'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<OrbitRail>(rail).page, 'library');

    await tester.tap(favorites);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.descendant(of: rail, matching: find.text('Library')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<OrbitRail>(rail).page, 'library');
  });

  testWidgets('Continue maps to a visible portrait collection tab', (
    tester,
  ) async {
    await pumpShell(tester, const Size(1600, 1000));
    await tester.tap(
      find.descendant(
        of: find.byType(OrbitRail),
        matching: find.text('Continue'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(tester.widget<OrbitTabs>(find.byType(OrbitTabs)).value, 'recent');
  });

  testWidgets('landscape layouts use the command rail', (tester) async {
    for (final size in const [Size(1600, 1000), Size(1024, 768)]) {
      await pumpShell(tester, size);
      expect(find.byType(OrbitRail), findsOneWidget, reason: '$size');
      expect(find.byType(OrbitBottomNav), findsNothing, reason: '$size');
    }
  });

  testWidgets('every space renders in the shell at phone portrait', (
    tester,
  ) async {
    await pumpShell(tester, const Size(390, 844));
    for (final label in ['Library', 'Systems', 'Capsule', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
