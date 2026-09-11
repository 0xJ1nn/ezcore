import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';

void main() {
  testWidgets('library renders mock games and filters', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My GBA Dump'), findsOneWidget);
    expect(find.text('My SNES Dump'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'snes');
    await tester.pumpAndSettle();
    expect(find.text('My SNES Dump'), findsOneWidget);
    expect(find.text('My GBA Dump'), findsNothing);
  });
}
