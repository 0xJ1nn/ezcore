import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/support/entitlement.dart';
import 'package:ezcore/support/purchase_store.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support_fake_store.dart';

/// Bounded pumping: these screens have short animations but no reason to wait
/// on a full settle (which can chase a store-restore timer).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
}

void main() {
  Future<Entitlement> pumpDiamond(
    WidgetTester tester, {
    FakePurchaseStore? store,
    bool trialEligible = false,
  }) async {
    final s = store ?? FakePurchaseStore(trialEligible: trialEligible);
    final entitlement = Entitlement(
      store: s,
      storage: InMemorySupportStorage(),
    );
    addTearDown(entitlement.dispose);
    await entitlement.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SettingsScreen(
            state: AppState.ephemeral(),
            entitlement: entitlement,
            initialTab: 'Diamond',
          ),
        ),
      ),
    );
    await settle(tester);
    return entitlement;
  }

  testWidgets('pending and failed purchases show their toasts', (tester) async {
    final store = FakePurchaseStore();
    await pumpDiamond(tester, store: store);

    store.emit(diamondYearlyId, PurchaseState.pending);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Waiting for approval. You can keep playing.'),
      findsOneWidget,
    );

    store.emit(diamondYearlyId, PurchaseState.failed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text("The purchase didn't go through. You weren't charged."),
      findsOneWidget,
    );
  });

  testWidgets('restoring with nothing shows the information toast', (
    tester,
  ) async {
    final entitlement = await pumpDiamond(tester);
    entitlement.restore();
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.text('No purchases to restore for this account.'),
      findsOneWidget,
    );
  });

  testWidgets('a store build shows Diamond, empty early access and the tip card', (
    tester,
  ) async {
    await pumpDiamond(tester);
    expect(find.text('ezCORE Diamond'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Nothing in early access right now.'), findsOneWidget);
    expect(find.text('Send the developer something'), findsOneWidget);
    expect(
      find.text('Support ezCORE on GitHub Sponsors'),
      findsNothing,
    );
  });

  testWidgets('a build without a store shows only the Sponsors card', (
    tester,
  ) async {
    await pumpDiamond(tester, store: FakePurchaseStore(available: false));
    expect(find.text('Support ezCORE on GitHub Sponsors'), findsOneWidget);
    expect(find.text('ezCORE Diamond'), findsNothing);
    expect(find.text('See plans'), findsNothing);
    expect(find.text('Send the developer something'), findsNothing);
  });

  testWidgets('plans sheet selects yearly and shows trial wording when eligible', (
    tester,
  ) async {
    await pumpDiamond(tester, trialEligible: true);
    await tester.tap(find.text('See plans'));
    await settle(tester);

    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text(r'$19.99'), findsOneWidget);
    expect(find.text('7 DAYS FREE'), findsOneWidget);
    expect(find.text('Start 7-day free trial'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('plans sheet hides trial wording when not eligible', (
    tester,
  ) async {
    await pumpDiamond(tester, trialEligible: false);
    await tester.tap(find.text('See plans'));
    await settle(tester);
    expect(find.text('7 DAYS FREE'), findsNothing);
    expect(find.text('Subscribe to Diamond'), findsOneWidget);
  });

  testWidgets('tip sheet lists all six tips and a tip thanks the player', (
    tester,
  ) async {
    final store = FakePurchaseStore();
    final entitlement = await pumpDiamond(tester, store: store);
    await tester.tap(find.text('Send the developer something'));
    await settle(tester);

    for (final name in [
      'Coffee',
      'Pizza',
      'Gamepad',
      'Console',
      'Arcade cabinet',
      'Dev kit',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }

    await tester.tap(find.text('Coffee'));
    await settle(tester);
    expect(store.bought, ['tip.coffee']);

    await entitlement.applyUpdate(
      const PurchaseUpdate(
        productId: 'tip.coffee',
        state: PurchaseState.success,
      ),
    );
    await settle(tester);
    expect(find.text('Thanks for the coffee.'), findsOneWidget);
    expect(find.text('You have sent 1 coffee.'), findsOneWidget);
  });

  testWidgets('member state shows the badge and hides the app icon row', (
    tester,
  ) async {
    final storage = InMemorySupportStorage({'diamond.member': true});
    final entitlement = Entitlement(
      store: FakePurchaseStore(),
      storage: storage,
    );
    addTearDown(entitlement.dispose);
    await entitlement.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SettingsScreen(
            state: AppState.ephemeral(),
            entitlement: entitlement,
            initialTab: 'Diamond',
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('DIAMOND MEMBER'), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.text('Diamond app icon'), findsNothing);
  });
}
