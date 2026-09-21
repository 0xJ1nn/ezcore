import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';

/// TDD-first tests for issue #14: ROM-folder wiring on the Import screen.
/// "Add ROM folder" registers the typed path for watched-folder rescan;
/// "Re-scan" runs the rescan and reports the outcome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpImport(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
    await tester.pumpAndSettle();
  }

  testWidgets('Add ROM folder registers the typed path (#14)',
      (tester) async {
    final state = AppState.ephemeral();
    await pumpImport(tester, state);

    await tester.enterText(
      find.byKey(const Key('import-path-field')),
      '/tmp/ezcore_fake_roms',
    );
    await tester.tap(find.byKey(const Key('import-add-folder')));
    await tester.pumpAndSettle();

    expect(state.romFolders, contains('/tmp/ezcore_fake_roms'));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Add ROM folder rejects an empty path', (tester) async {
    final state = AppState.ephemeral();
    await pumpImport(tester, state);

    await tester.tap(find.byKey(const Key('import-add-folder')));
    await tester.pumpAndSettle();

    expect(state.romFolders, isEmpty);
    expect(find.text('Enter a folder path first'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('watched folders are listed as removable chips', (tester) async {
    final state = AppState.ephemeral();
    await state.addRomFolder('/tmp/ezcore_one');
    await state.addRomFolder('/tmp/ezcore_two');
    await pumpImport(tester, state);

    expect(find.text('/tmp/ezcore_one'), findsOneWidget);
    expect(find.text('/tmp/ezcore_two'), findsOneWidget);

    // Removing a chip unregisters the folder (tap the delete icon, not the
    // chip body — InputChip.onDeleted fires from the trailing icon).
    await tester.tap(find.descendant(
      of: find.byKey(const Key('remove-folder-/tmp/ezcore_one')),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();
    expect(state.romFolders, isNot(contains('/tmp/ezcore_one')));
    expect(state.romFolders, contains('/tmp/ezcore_two'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    state.dispose();
  });

  testWidgets('Re-scan runs the watched-folder rescan and reports (#14)',
      (tester) async {
    final state = AppState.ephemeral();
    late Directory roms;
    await tester.runAsync(() async {
      roms = await Directory.systemTemp.createTemp('ezcore_rescan_ui');
      await state.addRomFolder(roms.path);
      await state.load();
    });
    await pumpImport(tester, state);

    await tester.tap(find.byKey(const Key('import-rescan')));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.textContaining('folders scanned').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();

    // Empty folder: 0 added, 0 pruned, 1 folder scanned — no crash.
    expect(find.textContaining('folders scanned'), findsOneWidget);
    expect(state.games, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await roms.delete(recursive: true);
      await state.removeRomFolder(roms.path);
    });
  });
}
