import 'dart:convert';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/core_manager_screen.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/screens/vault_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const games = [
    GameEntry(
      id: 'g1',
      title: 'Metroid Prime',
      system: 'gc',
      filePath: '/games/metroid.gcm',
      extension: 'gcm',
      coreId: 'powercube',
      lastPlayedMs: 1758500000000,
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

  final screens = <String, Widget Function(AppState)>{
    'Library': (state) => LibraryScreen(state: state),
    'Systems': (state) => CoreManagerScreen(state: state),
    'Time Capsule': (state) => VaultScreen(state: state),
    'Settings': (state) => SettingsScreen(state: state),
  };

  final shapes = <String, Size>{
    'phone landscape content': Size(772, 346),
    'tablet portrait content': Size(750, 1194),
  };

  for (final shape in shapes.entries) {
    for (final screen in screens.entries) {
      testWidgets('${screen.key} fits ${shape.key}', (tester) async {
        tester.view.physicalSize = shape.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final state = AppState.ephemeral()..games = games;
        state.registry.loadCatalog({core.id: jsonEncode(core.toJson())});
        state.registry.install(core, expectedSha256: 'test-pin');

        await tester.pumpWidget(
          MaterialApp(
            theme: Tokens.theme(),
            home: Scaffold(body: screen.value(state)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.key} at ${shape.value}',
        );
      });
    }
  }
}
