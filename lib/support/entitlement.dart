import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/app_state.dart';
import 'purchase_store.dart';

// Persisted keys. Stored through the app's existing local settings service.
const String _memberKey = 'diamond.member';
const String _planKey = 'diamond.plan';
const String _renewKey = 'diamond.renew';
const String _tallyKey = 'tip.tally';

/// The local persistence seam used by [Entitlement]. Production backs it with
/// [AppState] settings; tests use [InMemorySupportStorage].
abstract class SupportStorage {
  Map<String, dynamic> get values;
  Future<void> write(String key, Object? value);
}

class InMemorySupportStorage implements SupportStorage {
  InMemorySupportStorage([Map<String, dynamic>? initial]) {
    if (initial != null) _values.addAll(initial);
  }

  final Map<String, dynamic> _values = <String, dynamic>{};

  @override
  Map<String, dynamic> get values => Map.unmodifiable(_values);

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class AppStateSupportStorage implements SupportStorage {
  AppStateSupportStorage(this._state);

  final AppState _state;

  @override
  Map<String, dynamic> get values => _state.settings;

  @override
  Future<void> write(String key, Object? value) => _state.setSetting(key, value);
}

enum SupportEventKind {
  pending,
  failed,
  restored,
  nothingToRestore,
  tip,
  diamond,
}

/// A one-off message for the UI to turn into a toast or thank-you overlay.
class SupportEvent {
  const SupportEvent(this.kind, {this.productId, this.count});

  final SupportEventKind kind;
  final String? productId;
  final int? count;
}

/// Local membership and tip state. Everything is checked on the device: there
/// is no account, server or analytics.
class Entitlement extends ChangeNotifier {
  Entitlement({required this.store, required this.storage}) {
    _subscription = store.updates.listen(_onUpdate);
  }

  /// An inert instance for contexts (such as widget tests) that do not wire a
  /// real store. It never reports a store, so the Sponsors card is shown.
  factory Entitlement.inert() => Entitlement(
        store: _NoStore(),
        storage: InMemorySupportStorage(),
      );

  final PurchaseStore store;
  final SupportStorage storage;
  StreamSubscription<PurchaseUpdate>? _subscription;
  final StreamController<SupportEvent> _events =
      StreamController<SupportEvent>.broadcast();

  Stream<SupportEvent> get events => _events.stream;

  bool _isDiamond = false;
  String? _activePlan;
  DateTime? _renewDate;
  bool _trialEligible = false;
  final Map<String, int> _tipTally = <String, int>{};
  bool _started = false;
  bool _restorePending = false;
  Timer? _restoreTimer;
  List<StoreProduct> _products = const [];

  bool get isDiamond => _isDiamond;
  String? get activePlan => _activePlan;
  DateTime? get renewDate => _renewDate;
  bool get trialEligible => _trialEligible;
  Map<String, int> get tipTally => Map.unmodifiable(_tipTally);
  bool get storeAvailable => store.isAvailable;
  List<StoreProduct> get products => List.unmodifiable(_products);

  int tipCount(String productId) => _tipTally[productId] ?? 0;
  int get totalTips => _tipTally.values.fold(0, (a, b) => a + b);

  /// Restores membership and the tip tally, subscribes to store updates and
  /// completes any transaction left pending by an earlier session.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _loadLocal();
    await store.start();
    _products = await store.loadProducts();
    _trialEligible = await store.trialEligible(diamondYearlyId);
    notifyListeners();
    if (store.isAvailable) await store.restore();
  }

  void _loadLocal() {
    final values = storage.values;
    _isDiamond = values[_memberKey] == true;
    final plan = values[_planKey];
    _activePlan = plan is String ? plan : null;
    final renew = values[_renewKey];
    _renewDate = renew is int
        ? DateTime.fromMillisecondsSinceEpoch(renew)
        : null;
    final tally = values[_tallyKey];
    if (tally is Map) {
      tally.forEach((key, value) {
        if (key is String && value is num) {
          _tipTally[key] = value.toInt();
        }
      });
    }
  }

  Future<void> _save() async {
    await storage.write(_memberKey, _isDiamond);
    await storage.write(_planKey, _activePlan);
    await storage.write(
      _renewKey,
      _renewDate?.millisecondsSinceEpoch,
    );
    await storage.write(_tallyKey, _tipTally);
  }

  Future<void> _onUpdate(PurchaseUpdate update) async {
    switch (update.state) {
      case PurchaseState.pending:
        _events.add(const SupportEvent(SupportEventKind.pending));
      case PurchaseState.failed:
        _events.add(const SupportEvent(SupportEventKind.failed));
      case PurchaseState.cancelled:
        break;
      case PurchaseState.success:
        await _succeed(update.productId);
    }
  }

  /// Applies a store update directly. Used by tests to drive the state machine
  /// without relying on stream timing.
  @visibleForTesting
  Future<void> applyUpdate(PurchaseUpdate update) => _onUpdate(update);

  Future<void> _succeed(String productId) async {
    if (isTipId(productId)) {
      final next = (_tipTally[productId] ?? 0) + 1;
      _tipTally[productId] = next;
      await _save();
      await store.finalize(productId);
      if (!_events.isClosed) {
        _events.add(
          SupportEvent(
            SupportEventKind.tip,
            productId: productId,
            count: next,
          ),
        );
      }
      notifyListeners();
      return;
    }

    if (isDiamondPlanId(productId)) {
      _isDiamond = true;
      _activePlan = productId;
      _renewDate = DateTime.now().add(_period(productId));
      await _save();
      await store.finalize(productId);
      if (!_events.isClosed) {
        _events.add(const SupportEvent(SupportEventKind.diamond));
      }
      if (_restorePending) _finishRestore(true);
      notifyListeners();
    }
  }

  Duration _period(String planId) => switch (planId) {
        diamondWeeklyId => const Duration(days: 7),
        diamondMonthlyId => const Duration(days: 30),
        _ => const Duration(days: 365),
      };

  Future<void> buy(String productId) => store.buy(productId);

  /// Requests a restore and reports whether anything came back. A quiet store
  /// produces the "No purchases to restore" information toast.
  Future<void> restore() async {
    if (!store.isAvailable) {
      _events.add(const SupportEvent(SupportEventKind.nothingToRestore));
      return;
    }
    _restorePending = true;
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 2), () {
      if (_restorePending) _finishRestore(false);
    });
    await store.restore();
  }

  void _finishRestore(bool found) {
    _restorePending = false;
    _restoreTimer?.cancel();
    _events.add(
      SupportEvent(
        found ? SupportEventKind.restored : SupportEventKind.nothingToRestore,
      ),
    );
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    _subscription?.cancel();
    _events.close();
    super.dispose();
  }
}

class _NoStore implements PurchaseStore {
  @override
  bool get isAvailable => false;

  @override
  Stream<PurchaseUpdate> get updates => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<List<StoreProduct>> loadProducts() async => const [];

  @override
  Future<void> buy(String productId) async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> finalize(String productId) async {}

  @override
  Future<bool> trialEligible(String productId) async => false;

  @override
  void dispose() {}
}
