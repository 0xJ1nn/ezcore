import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/core_manager_screen.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/screens/vault_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';

/// Phone-viewport rendering gate: every space must build its Orbit chrome
/// at 390x844 without layout exceptions.
void main() {
  const phone = Size(390, 844);

  Future<void> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('library renders on a phone viewport', (tester) async {
    final state = AppState();
    state.games = const [
      GameEntry(
        id: 'g1',
        title: 'My GBA Dump',
        system: 'gba',
        filePath: '~/Games/gba/mydump.gba',
        extension: 'gba',
        coreId: 'advancebit',
        lastPlayedMs: 1758000000000,
      ),
    ];
    await pumpPhone(tester, HomeScreen(state: state));
    // Phone portrait: Resume for the last game, the add button, filters.
    expect(find.text('Resume'), findsOneWidget);
    expect(find.byTooltip('Add games'), findsOneWidget);
    expect(find.text('All · 1'), findsOneWidget);
    expect(find.text('My GBA Dump'), findsWidgets);
  });

  testWidgets('systems empty state renders on a phone viewport', (
    tester,
  ) async {
    final state = AppState();
    await pumpPhone(tester, CoreManagerScreen(state: state));
    expect(find.text('Cores'), findsOneWidget);
  });

  testWidgets('vault empty state renders on a phone viewport', (tester) async {
    final state = AppState();
    await pumpPhone(tester, VaultScreen(state: state));
    expect(find.text('Your time capsule'), findsOneWidget);
  });

  testWidgets('settings render on a phone viewport', (tester) async {
    final state = AppState();
    await pumpPhone(tester, SettingsScreen(state: state));
    expect(find.text('Settings'), findsOneWidget);
  });
}
