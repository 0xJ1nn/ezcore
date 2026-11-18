import 'package:ezcore/support/diamond_tokens.dart';
import 'package:ezcore/support/early_access.dart';
import 'package:ezcore/support/entitlement.dart';
import 'package:ezcore/support/purchase_store.dart';
import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import 'support_fake_store.dart';

void main() {
  group('Entitlement', () {
    test('not a member, then buying the yearly plan makes a member', () async {
      final store = FakePurchaseStore();
      final storage = InMemorySupportStorage();
      final entitlement = Entitlement(store: store, storage: storage);
      addTearDown(entitlement.dispose);

      await entitlement.start();
      expect(entitlement.isDiamond, isFalse);
      expect(entitlement.products, hasLength(9));

      await entitlement.buy(diamondYearlyId);
      expect(store.bought, [diamondYearlyId]);

      await entitlement.applyUpdate(
        const PurchaseUpdate(
          productId: diamondYearlyId,
          state: PurchaseState.success,
        ),
      );
      expect(entitlement.isDiamond, isTrue);
      expect(entitlement.activePlan, diamondYearlyId);
      expect(entitlement.renewDate, isNotNull);
      expect(store.consumed, [diamondYearlyId]);
      expect(storage.values['diamond.member'], isTrue);
    });

    test('a tip bought twice tallies two and is consumed twice', () async {
      final store = FakePurchaseStore();
      final storage = InMemorySupportStorage();
      final entitlement = Entitlement(store: store, storage: storage);
      addTearDown(entitlement.dispose);
      await entitlement.start();

      for (var i = 0; i < 2; i++) {
        await entitlement.applyUpdate(
          const PurchaseUpdate(
            productId: 'tip.coffee',
            state: PurchaseState.success,
          ),
        );
      }
      expect(entitlement.tipCount('tip.coffee'), 2);
      expect(entitlement.totalTips, 2);
      expect(store.consumed, ['tip.coffee', 'tip.coffee']);
      expect((storage.values['tip.tally'] as Map)['tip.coffee'], 2);
    });

    test('the tally and membership survive a restart from storage', () async {
      final storage = InMemorySupportStorage();
      final first = Entitlement(store: FakePurchaseStore(), storage: storage);
      await first.start();
      await first.applyUpdate(
        const PurchaseUpdate(
          productId: 'tip.pizza',
          state: PurchaseState.success,
        ),
      );
      first.dispose();

      final second = Entitlement(store: FakePurchaseStore(), storage: storage);
      addTearDown(second.dispose);
      await second.start();
      expect(second.tipCount('tip.pizza'), 1);
    });

    test('pending and failed updates emit their notice events', () async {
      final entitlement = Entitlement(
        store: FakePurchaseStore(),
        storage: InMemorySupportStorage(),
      );
      addTearDown(entitlement.dispose);
      final kinds = <SupportEventKind>[];
      entitlement.events.listen((e) => kinds.add(e.kind));

      await entitlement.applyUpdate(
        const PurchaseUpdate(
          productId: diamondYearlyId,
          state: PurchaseState.pending,
        ),
      );
      await entitlement.applyUpdate(
        const PurchaseUpdate(
          productId: diamondYearlyId,
          state: PurchaseState.failed,
        ),
      );
      expect(
        kinds,
        containsAll([
          SupportEventKind.pending,
          SupportEventKind.failed,
        ]),
      );
    });

    test('a tip success emits a thank-you event with the new count', () async {
      final entitlement = Entitlement(
        store: FakePurchaseStore(),
        storage: InMemorySupportStorage(),
      );
      addTearDown(entitlement.dispose);
      SupportEvent? seen;
      entitlement.events.listen((e) => seen = e);

      await entitlement.applyUpdate(
        const PurchaseUpdate(
          productId: 'tip.coffee',
          state: PurchaseState.success,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen?.kind, SupportEventKind.tip);
      expect(seen?.productId, 'tip.coffee');
      expect(seen?.count, 1);
    });

    test('restoring with nothing reports no purchases', () async {
      final entitlement = Entitlement(
        store: FakePurchaseStore(),
        storage: InMemorySupportStorage(),
      );
      addTearDown(entitlement.dispose);
      await entitlement.start();
      final kinds = <SupportEventKind>[];
      entitlement.events.listen((e) => kinds.add(e.kind));

      await entitlement.restore();
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(kinds, contains(SupportEventKind.nothingToRestore));
    });
  });

  group('Early access', () {
    final feature = EarlyAccessFeature(
      id: 'wall',
      title: 'Curved wall view',
      icon: const IconData(0xe8eb),
      freeFrom: DateTime(2026, 2, 12),
    );

    test('is on for Diamond members before the free date', () async {
      final diamond = Entitlement(
        store: FakePurchaseStore(),
        storage: InMemorySupportStorage({'diamond.member': true}),
      );
      addTearDown(diamond.dispose);
      await diamond.start();
      expect(
        earlyAccessIsOn(feature, diamond, now: DateTime(2026, 1, 1)),
        isTrue,
      );
    });

    test('is off for everyone until the free date, then on', () {
      final free = Entitlement(
        store: FakePurchaseStore(),
        storage: InMemorySupportStorage(),
      );
      expect(
        earlyAccessIsOn(feature, free, now: DateTime(2026, 2, 11)),
        isFalse,
      );
      expect(
        earlyAccessIsOn(feature, free, now: DateTime(2026, 2, 12)),
        isTrue,
      );
    });

    test('the feature table starts empty', () {
      expect(earlyAccessFeatures, isEmpty);
      expect(DiamondTokens.sponsorsUrl, contains('github.com/sponsors'));
    });
  });
}
