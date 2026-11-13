import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'db.dart';
import 'license.dart';
import 'packages.dart';

/// Single place that answers "may this shop use feature X?".
///
/// Sources, any of which unlocks a feature:
/// 1. the online subscription assigned by the super admin (cached for offline use),
/// 2. an offline signed code (LicenseService),
/// 3. a rewarded ad watched in the last 24 hours (that feature only).
class Access extends ChangeNotifier {
  Access._() {
    LicenseService.instance.addListener(notifyListeners);
  }
  static final Access instance = Access._();

  static const unlockDuration = Duration(hours: 24);

  CloudPlan cloud = CloudPlan();
  Map<String, int> _unlocks = {};

  void load() {
    final raw = Local.prefs.getString('cloud_plan');
    if (raw != null) {
      try {
        cloud = CloudPlan.fromShop(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final u = Local.prefs.getString('ad_unlocks');
    if (u != null) {
      try {
        _unlocks = (jsonDecode(u) as Map).map((k, v) => MapEntry('$k', (v as num).toInt()));
      } catch (_) {}
    }
  }

  void setCloud(CloudPlan plan) {
    cloud = plan;
    Local.prefs.setString('cloud_plan', jsonEncode(plan.toJson()));
    notifyListeners();
  }

  int _now() => LicenseService.instance.now();

  bool get cloudActive => cloud.activeAt(_now());
  bool get blocked => cloud.blocked;

  /// Paid through a subscription or code (not counting ad unlocks).
  bool paidHas(String feature) =>
      (cloudActive && cloud.features.contains(feature)) || LicenseService.instance.has(feature);

  bool has(String feature) => paidHas(feature) || unlockedUntil(feature) > _now();

  int unlockedUntil(String feature) => _unlocks[feature] ?? 0;

  /// Free shops see ads; any paid subscription or offline code removes them.
  bool get adFree => (cloudActive && cloud.adFree) || LicenseService.instance.active;

  bool get isPaid => cloudActive || LicenseService.instance.active;

  String get planName {
    if (cloudActive) return cloud.name;
    if (LicenseService.instance.active) return LicenseService.instance.plan.name;
    return Plans.free.name;
  }

  /// 0 when there is no expiry (free or lifetime).
  int get expiresAt {
    if (cloudActive) return cloud.expiresAt;
    if (LicenseService.instance.active) return LicenseService.instance.planExpires;
    return 0;
  }

  int get daysLeft => expiresAt == 0 ? -1 : ((expiresAt - _now()) / 86400000).ceil();

  void grantUnlock(String feature) {
    _unlocks[feature] = _now() + unlockDuration.inMilliseconds;
    Local.prefs.setString('ad_unlocks', jsonEncode(_unlocks));
    notifyListeners();
  }
}
