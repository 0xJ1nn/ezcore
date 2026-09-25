import 'dart:convert';

import 'package:ezcore/main.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
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
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        debugShowCheckedModeBanner: false,
        home: Shell(state: state),
      ),
    );
    await tester.pump();
    // Let the still background and the cover-flow settle.
    await tester.pump(const Duration(milliseconds: 50));
  }

  final viewports = <String, Size>{
    'desktop': Size(1600, 1000),
    'small desktop window': Size(1280, 720),
    'tablet': Size(1024, 768),
    'phone landscape': Size(844, 390),
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
