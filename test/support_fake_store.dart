// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';

import 'package:ezcore/support/purchase_store.dart';

/// In-memory store for support tests. Prices mirror the design's fake values;
/// the real store supplies the device's localised strings in production.
class FakePurchaseStore implements PurchaseStore {
  FakePurchaseStore({
    this.available = true,
    bool trialEligible = false,
    List<StoreProduct>? products,
  })  : trialEligibleFlag = trialEligible,
        products = products ?? fakeProducts;

  bool available;
  bool trialEligibleFlag;
  List<StoreProduct> products;
  final List<String> consumed = <String>[];
  final List<String> bought = <String>[];
  int restores = 0;
  final _updates = StreamController<PurchaseUpdate>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Stream<PurchaseUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {}

  @override
  Future<List<StoreProduct>> loadProducts() async => products;

  @override
  Future<void> buy(String productId) async => bought.add(productId);

  @override
  Future<void> restore() async => restores++;

  @override
  Future<void> finalize(String productId) async => consumed.add(productId);

  @override
  @override
  Future<bool> trialEligible(String productId) async => trialEligibleFlag;

  @override
  void dispose() => _updates.close();

  void emit(
    String productId,
    PurchaseState state, {
    String? message,
  }) {
    if (!_updates.isClosed) {
      _updates.add(
        PurchaseUpdate(
          productId: productId,
          state: state,
          message: message,
        ),
      );
    }
  }
}

const List<StoreProduct> fakeProducts = <StoreProduct>[
  StoreProduct(
    id: diamondWeeklyId,
    title: 'Weekly',
    price: r'$0.99',
    description: 'Billed every week',
    period: 'per week',
  ),
  StoreProduct(
    id: diamondMonthlyId,
    title: 'Monthly',
    price: r'$2.99',
    description: 'Billed every month',
    period: 'per month',
  ),
  StoreProduct(
    id: diamondYearlyId,
    title: 'Yearly',
    price: r'$19.99',
    description: r'$1.67 a month, billed once a year',
    period: 'per year',
  ),
  StoreProduct(
    id: 'tip.coffee',
    title: 'Coffee',
    price: r'$1.99',
  ),
  StoreProduct(
    id: 'tip.pizza',
    title: 'Pizza',
    price: r'$4.99',
  ),
  StoreProduct(
    id: 'tip.gamepad',
    title: 'Gamepad',
    price: r'$9.99',
  ),
  StoreProduct(
    id: 'tip.console',
    title: 'Console',
    price: r'$24.99',
  ),
  StoreProduct(
    id: 'tip.arcade',
    title: 'Arcade cabinet',
    price: r'$49.99',
  ),
  StoreProduct(
    id: 'tip.devkit',
    title: 'Dev kit',
    price: r'$99.99',
  ),
];
