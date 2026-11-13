import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'db.dart';
import 'license.dart';
import 'packages.dart';

/// Single place that answers "may this shop use feature X?".
///
/// Sources, either of which unlocks a feature:
/// 1. the online subscription assigned by the super admin (cached for offline use),
/// 2. an offline signed code (LicenseService).
class Access extends ChangeNotifier {
  Access._() {
    LicenseService.instance.addListener(notifyListeners);
  }
  static final Access instance = Access._();

  CloudPlan cloud = CloudPlan();

  void load() {
    final raw = Local.prefs.getString(Local.k('cloud_plan'));
    cloud = CloudPlan();
    if (raw != null) {
      try {
        cloud = CloudPlan.fromShop(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    notifyListeners();
  }

  void setCloud(CloudPlan plan) {
    cloud = plan;
    Local.prefs.setString(Local.k('cloud_plan'), jsonEncode(plan.toJson()));
    notifyListeners();
  }

  int _now() => LicenseService.instance.now();

  bool get cloudActive => cloud.activeAt(_now());
  bool get blocked => cloud.blocked;

  /// Paid through a subscription or an offline code.
  bool paidHas(String feature) =>
      (cloudActive && cloud.features.contains(feature)) || LicenseService.instance.has(feature);

  bool has(String feature) => paidHas(feature);

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

  /// Most products this shop may have; 0 means no limit.
  int get maxProducts {
    if (cloud.productLimit != null) return cloud.productLimit!;
    if (cloudActive) return cloud.maxProducts;
    if (LicenseService.instance.active) return 0;
    return Plans.freeMaxProducts;
  }

  int get daysLeft => expiresAt == 0 ? -1 : ((expiresAt - _now()) / 86400000).ceil();
}
