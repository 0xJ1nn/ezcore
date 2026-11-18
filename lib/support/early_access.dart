import 'package:flutter/widgets.dart';

import 'entitlement.dart';

/// A finished, released feature that reaches Diamond members first and every
/// free user on [freeFrom]. Only shipped features belong here.
class EarlyAccessFeature {
  const EarlyAccessFeature({
    required this.id,
    required this.title,
    required this.icon,
    required this.freeFrom,
  });

  final String id;
  final String title;
  final IconData icon;
  final DateTime freeFrom;
}

/// No real early-access feature exists yet, so the list starts empty. The UI
/// then reads "Nothing in early access right now."
const List<EarlyAccessFeature> earlyAccessFeatures = <EarlyAccessFeature>[];

/// Diamond members have a feature now; everyone else gets it on its free date.
bool earlyAccessIsOn(
  EarlyAccessFeature feature,
  Entitlement entitlement, {
  DateTime? now,
}) {
  if (entitlement.isDiamond) return true;
  final moment = now ?? DateTime.now();
  return !moment.isBefore(feature.freeFrom);
}
