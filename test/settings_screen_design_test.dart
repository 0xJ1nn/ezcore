import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings is one screen that adapts to five layout families. These tests
/// pin the design's structure (tabs, option rows, status pills) and make sure
/// every preference the screen used to expose is still reachable.
void main() {
  Future<void> pump(
    WidgetTester tester,
    AppState state, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: SettingsScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop shows the design header, tabs and appearance rows', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await pump(tester, state);

    expect(find.text('STORED ON THIS DEVICE'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final tab in [
      'Appearance',
      'Play',
      'Controls',
      'Audio',
      'Storage',
      'About',
    ]) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }

    // The four appearance rows, in the design's order.
    final labels = [
      'Library look',
      'Reduce motion',
      'Ambient motion',
      'Text size',
    ];
    final ys = [
      for (final label in labels) tester.getTopLeft(find.text(label)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'row order');

    expect(find.text('3D shelf'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Controller: A'), findsNothing);
  });

  testWidgets('the toggle and value rows persist their preferences', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await pump(tester, state);

    await tester.tap(find.text('Ambient motion'));
    await tester.pumpAndSettle();
    expect(state.settings['motion'], isFalse);

    await tester.tap(find.text('Text size'));
    await tester.pumpAndSettle();
    expect(state.settings['textScale'], 115);
    expect(find.text('115%'), findsOneWidget);

    await tester.tap(find.text('Library look'));
    await tester.pumpAndSettle();
    expect(state.settings['libraryView'], 'shelf');
  });

  testWidgets('text size scales the screen text', (tester) async {
    final state = AppState.ephemeral();
    await state.setSetting('textScale', 130);
    await pump(tester, state);

    final scaler = MediaQuery.textScalerOf(
      tester.element(find.text('Text size')),
    );
    expect(scaler.scale(100), 130);
    expect(find.text('130%'), findsOneWidget);
  });

  testWidgets('controls list remaps the design keys and starts listening', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await pump(tester, state);
    await openTab(tester, 'Controls');

    for (final label in ['Confirm', 'Back', 'Quick save', 'Fast-forward']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Controller: A'), findsOneWidget);
    expect(find.text('Controller: B'), findsOneWidget);
    expect(find.text('Controller: RB'), findsOneWidget);
    expect(find.text('Controller: RT'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);

    await tester.tap(find.text('Quick save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Press a button for Quick save'), findsOneWidget);
    expect(find.text('Press the button you want to use...'), findsOneWidget);

    // Nothing pressed: the sheet cancels after six seconds.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Listening'), findsNothing);
    expect(find.text('Press a button for Quick save'), findsNothing);
  });

  testWidgets('every older setting is still reachable', (tester) async {
    final state = AppState.ephemeral();
    await pump(tester, state);

    await openTab(tester, 'Play');
    for (final label in [
      'Automatic snapshots',
      'Crash protection',
      'Fast-forward speed',
      'Core verification',
      'State format',
      'Controller buttons',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await openTab(tester, 'Audio');
    for (final label in ['Mute all audio', 'Game volume', 'Output']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await openTab(tester, 'Storage');
    for (final label in ['Games folder', 'Core directory', 'Content policy']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await openTab(tester, 'About');
    for (final label in [
      'Version',
      'License',
      'Cores',
      'DMCA',
      'Privacy',
      'Reset appearance',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the buttons editor keeps every binding and touch overlay', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await pump(tester, state);
    await openTab(tester, 'Play');
    await tester.tap(find.text('Controller buttons'));
    await tester.pumpAndSettle();

    expect(find.text('On-screen controls'), findsOneWidget);
    for (final label in ['X', 'Y', 'L / L1']) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    for (final label in ['R2', 'Select', 'Up']) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('On-screen controls'), findsNothing);
  });

  testWidgets('phone portrait drills from the section list into a section', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await pump(tester, state, size: const Size(390, 844));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Library look'), findsNothing);

    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    expect(find.text('Controls'), findsOneWidget);
    expect(find.text('Quick save'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.byTooltip('All settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Quick save'), findsNothing);
  });

  testWidgets('tablet portrait wraps the tabs into pills', (tester) async {
    final state = AppState.ephemeral();
    await pump(tester, state, size: const Size(820, 1180));

    expect(find.text('STORED ON THIS DEVICE'), findsOneWidget);
    // Every tab is present as a pill above the rows.
    for (final tab in [
      'Appearance',
      'Play',
      'Controls',
      'Audio',
      'Storage',
      'About',
    ]) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    expect(find.text('Library look'), findsOneWidget);
  });

  testWidgets('phone landscape warns nothing is cut off', (tester) async {
    final state = AppState.ephemeral();
    await pump(tester, state, size: const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.text('Settings'), findsOneWidget);
  });
}
