// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

/// Stable product identifiers. These match the App Store and Play product IDs.
const String diamondWeeklyId = 'diamond.weekly';
const String diamondMonthlyId = 'diamond.monthly';
const String diamondYearlyId = 'diamond.yearly';

const List<String> diamondPlanIds = <String>[
  diamondWeeklyId,
  diamondMonthlyId,
  diamondYearlyId,
];

const List<String> tipIds = <String>[
  'tip.coffee',
  'tip.pizza',
  'tip.gamepad',
  'tip.console',
  'tip.arcade',
  'tip.devkit',
];

const Set<String> allPurchaseIds = <String>{...diamondPlanIds, ...tipIds};

bool isDiamondPlanId(String id) => diamondPlanIds.contains(id);
bool isTipId(String id) => tipIds.contains(id);

/// A product as the store describes it. Titles, prices and period text are the
/// store's localised strings; the app never hard-codes a price.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.price,
    this.description = '',
    this.period = '',
    this.trialAvailable = false,
  });

  final String id;
  final String title;
  final String price;

  /// Store-provided description, used as the billed-period line when the
  /// platform does not expose a separate subscription-period string.
  final String description;
  final String period;
  final bool trialAvailable;

  bool get isPlan => isDiamondPlanId(id);
  bool get isTip => isTipId(id);
}

enum PurchaseState { pending, success, failed, cancelled }

/// A purchase event delivered by the store.
class PurchaseUpdate {
  const PurchaseUpdate({
    required this.productId,
    required this.state,
    this.message,
  });

  final String productId;
  final PurchaseState state;
  final String? message;

  bool get isTip => isTipId(productId);
  bool get isPlan => isDiamondPlanId(productId);
}

/// The seam every screen uses. Tests inject a fake; production uses
/// [InAppPurchaseStore]. On platforms with no store, [isAvailable] is false and
/// the UI falls back to the Sponsors card.
abstract class PurchaseStore {
  bool get isAvailable;
  Stream<PurchaseUpdate> get updates;
  Future<void> start();
  Future<List<StoreProduct>> loadProducts();
  Future<void> buy(String productId);
  Future<void> restore();
  Future<void> finalize(String productId);
  Future<bool> trialEligible(String productId) async => false;
  void dispose();
}

/// Store-backed implementation using the official `in_app_purchase` package.
class InAppPurchaseStore implements PurchaseStore {
  InAppPurchaseStore();

  final InAppPurchase _iap = InAppPurchase.instance;
  final _updates = StreamController<PurchaseUpdate>.broadcast();
  final Map<String, ProductDetails> _details = <String, ProductDetails>{};
  final Map<String, PurchaseDetails> _purchases = <String, PurchaseDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _ready = false;

  @override
  bool get isAvailable =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  @override
  Stream<PurchaseUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    if (!isAvailable || _subscription != null) return;
    try {
      _ready = await _iap.isAvailable();
    } catch (_) {
      _ready = false;
    }
    if (!_ready) return;
    _subscription = _iap.purchaseStream.listen(_onPurchases, onError: (error) {
      _updates.add(
        PurchaseUpdate(
          productId: '',
          state: PurchaseState.failed,
          message: error.toString(),
        ),
      );
    });
    await loadProducts();
  }

  @override
  Future<List<StoreProduct>> loadProducts() async {
    if (!_ready) return const <StoreProduct>[];
    try {
      final response = await _iap.queryProductDetails(allPurchaseIds);
      _details
        ..clear()
        ..addEntries(response.productDetails.map((d) => MapEntry(d.id, d)));
      return response.productDetails.map(_toStoreProduct).toList();
    } catch (_) {
      return const <StoreProduct>[];
    }
  }

  StoreProduct _toStoreProduct(ProductDetails d) => StoreProduct(
        id: d.id,
        title: d.title,
        price: d.price,
        description: d.description,
        period: d.description,
      );

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _purchases[purchase.productID] = purchase;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _emit(purchase, PurchaseState.pending);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _emit(purchase, PurchaseState.success);
        case PurchaseStatus.error:
          _emit(
            purchase,
            PurchaseState.failed,
            message: purchase.error?.message,
          );
        case PurchaseStatus.canceled:
          _emit(purchase, PurchaseState.cancelled);
      }
    }
  }

  void _emit(
    PurchaseDetails purchase,
    PurchaseState state, {
    String? message,
  }) {
    if (!_updates.isClosed) {
      _updates.add(
        PurchaseUpdate(
          productId: purchase.productID,
          state: state,
          message: message,
        ),
      );
    }
  }

  @override
  Future<void> buy(String productId) async {
    final details = _details[productId];
    if (details == null || !_ready) return;
    final param = PurchaseParam(productDetails: details);
    if (isTipId(productId)) {
      // The store consumes the tip once the transaction finishes; the tally
      // is recorded locally before finishTransaction is called.
      await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> finalize(String productId) async {
    final purchase = _purchases.remove(productId);
    if (purchase != null) await _iap.completePurchase(purchase);
  }

  /// The store plugin does not expose introductory-offer eligibility on every
  /// platform, so trial wording is only shown when a store confirms it.
  @override
  Future<bool> trialEligible(String productId) async => false;

  @override
  void dispose() {
    _subscription?.cancel();
    _updates.close();
  }
}
