import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';

/// One Import screen adapts to every layout family: the source cards, the
/// radar and the review list must lay out without overflowing on each.
void main() {
  const families = <(String, Size)>[
    ('phone portrait', Size(390, 844)),
    ('phone landscape', Size(844, 390)),
    ('tablet portrait', Size(820, 1180)),
    ('tablet landscape', Size(1180, 820)),
    ('desktop', Size(1440, 900)),
  ];

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

  for (final (name, size) in families) {
    testWidgets('Import lays out and scans on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = AppState.ephemeral();
      late Directory folder;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp('ezcore_import_family');
        final bytes = List<int>.filled(4096, 0xFF);
        const magic = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];
        for (var i = 0; i < magic.length; i++) {
          bytes[0x04 + i] = magic[i];
        }
        await File('${folder.path}/fixture.gba').writeAsBytes(bytes);
        await state.load();
        installCore(state, 'advancebit');
        await state.addRomFolder(folder.path);
        await state.setSetting(AppState.romsFolderPromptKey, true);
      });

      await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Add games'), findsOneWidget);
      expect(find.byKey(const Key('import-source-watched')), findsOneWidget);
      expect(find.byKey(const Key('import-source-folder')), findsOneWidget);
      expect(find.byKey(const Key('import-source-drive')), findsOneWidget);
      final sourceError = tester.takeException();
      expect(sourceError, isNull);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('import-source-watched')));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Add 1 game').evaluate().isNotEmpty) break;
        }
      });

      expect(find.text('Add 1 game'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      state.dispose();
      await tester.runAsync(() => folder.delete(recursive: true));
    });
  }
}
