import 'dart:io';
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
      // Arbitrary bytes test importing only; this is NOT playable ROM evidence.
      await File('${folder.path}/fixture.gba').writeAsBytes([1, 2, 3, 4]);
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
