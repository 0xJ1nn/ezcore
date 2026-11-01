import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';

/// Production ships its bundled cores; a bare test state has none, and the
/// review correctly marks a file whose system is not installed as skipped.
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

void main() {
  testWidgets('typed folder imports real files and returns to library', (tester) async {
    final state = AppState.ephemeral();
    late Directory folder;
    await tester.runAsync(() async {
      folder = await Directory.systemTemp.createTemp('ezcore_import_ui');
      // Valid GBA ROM fixture (magic bytes at 0x04 + size >= 512)
      final bytes = Uint8List(4096);
      final magic = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];
      for (var i = 0; i < magic.length; i++) {
        bytes[0x04 + i] = magic[i];
      }
      for (var i = 0x04 + magic.length; i < 4096; i++) {
        bytes[i] = 0xFF;
      }
      await File('${folder.path}/fixture.gba').writeAsBytes(bytes);
      await state.load();
      installCore(state, 'advancebit');
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeScreen(state: state))));
    await tester.tap(find.text('Add games').first);
    await tester.pumpAndSettle();
    // The typed-path controls live behind the quiet "Scan a path" row.
    final toggle = find.byKey(const Key('import-advanced-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('import-path-field')),
      folder.path,
    );
    final scan = find.text('Scan typed path');
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(scan);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Add 1 game').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('Fixture'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    await tester.tap(find.text('Add 1 game'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.byType(ImportScreen).evaluate().isEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsNothing);
    expect(find.text('fixture.gba'), findsWidgets);
    expect(state.games.single.filePath, '${folder.path}/fixture.gba');
    expect(state.games.single.sha1.length, 64);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.runAsync(() => folder.delete(recursive: true));
  });

  testWidgets('import does not invent preview games for a nonexistent path', (tester) async {
    final state = AppState.ephemeral();
    await tester.pumpWidget(MaterialApp(home: ImportScreen(state: state)));
    final toggle = find.byKey(const Key('import-advanced-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('import-path-field')),
      '/missing/ezcore-content',
    );
    final scan = find.text('Scan typed path');
    await tester.ensureVisible(scan);
    await tester.pumpAndSettle();
    await tester.tap(scan);
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('does not exist').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('does not exist'), findsOneWidget);
    expect(find.text('mydump2.gba'), findsNothing);
    expect(state.games, isEmpty);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
