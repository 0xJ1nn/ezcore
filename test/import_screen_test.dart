import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/screens/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';

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
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LibraryScreen(state: state))));
    await tester.tap(find.byTooltip('Import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, folder.path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Scan typed path'));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('Import scanned content').evaluate().isNotEmpty) break;
      }
    });
    expect(find.text('fixture.gba'), findsOneWidget);
    expect(find.text('Ready to import'), findsOneWidget);
    await tester.tap(find.text('Import scanned content'));
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
    await tester.enterText(find.byType(TextField), '/missing/ezcore-content');
    await tester.tap(find.text('Scan typed path'));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
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
