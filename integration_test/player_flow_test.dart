import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ezcore/main.dart';
import 'package:ezcore/state/app_state.dart';

// Local acceptance harness. No ROM or core is bundled by this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real import to native player, pause and save/load', (
    tester,
  ) async {
    const checkout = String.fromEnvironment('EZCORE_TEST_CHECKOUT');
    expect(
      checkout,
      isNotEmpty,
      reason: 'Pass --dart-define=EZCORE_TEST_CHECKOUT=/checkout',
    );
    final state = AppState.ephemeral();
    await state.setSetting('coreDirectory', '$checkout/native/cores');
    await state.load();
    expect(
      state.registry.isInstalled('mgba'),
      isTrue,
      reason:
          'Discovery failed: ${state.loadError}; ${state.coreDiscoveryErrors}',
    );
    await tester.pumpWidget(MaterialApp(home: Shell(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '$checkout/native/test-roms/test.gba',
    );
    await tester.tap(find.text('Scan'));
    for (
      var i = 0;
      i < 100 && find.text('Import scanned content').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Import scanned content'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.text('Import scanned content'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('test.gba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    for (var i = 0; i < 100 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(RawImage),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 240);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byTooltip('Quick-save'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      await state.saves.download(state.games.single.id, 'slot0'),
      isNotEmpty,
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load state — slot 0'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('State loaded'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
