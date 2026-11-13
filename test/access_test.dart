import 'package:bizpos/core/access.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/core/packages.dart';
import 'package:bizpos/services/cloud_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final access = Access.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Db.fileName = 'access_test.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await LicenseService.instance.load();
    access.load();
  });

  test('free shop has core only', () {
    access.setCloud(CloudPlan());
    expect(access.isPaid, isFalse);
    for (final f in Feature.all) {
      expect(access.has(f), isFalse, reason: f);
    }
    expect(access.planName, 'Free');
  });

  test('online subscription grants its features until it expires', () {
    access.setCloud(CloudPlan.fromShop({
      'plan': 'pro-monthly',
      'planName': 'Pro monthly',
      'features': ['voice', 'alerts'],
      'adFree': true,
      'expiresAt': nowMs() + 10 * 86400000,
      'status': 'active',
    }));
    expect(access.isPaid, isTrue);
    expect(access.has(Feature.voice), isTrue);
    expect(access.planName, 'Pro monthly');
    expect(access.daysLeft, inInclusiveRange(9, 10));

    access.setCloud(CloudPlan.fromShop({'plan': 'pro-monthly', 'features': ['voice'], 'adFree': true, 'expiresAt': nowMs() - 1}));
    expect(access.isPaid, isFalse);
    expect(access.has(Feature.voice), isFalse);
  });

  test('blocked shop loses paid features', () {
    access.setCloud(CloudPlan.fromShop({'plan': 'lifetime', 'features': ['reports'], 'expiresAt': 0, 'status': 'blocked'}));
    expect(access.blocked, isTrue);
    expect(access.paidHas(Feature.reports), isFalse);
  });

  test('cached plan survives a restart', () {
    access.setCloud(CloudPlan.fromShop({'plan': 'lifetime', 'planName': 'Lifetime', 'features': ['reports'], 'adFree': true, 'expiresAt': 0}));
    access.cloud = CloudPlan();
    access.load();
    expect(access.planName, 'Lifetime');
    expect(access.has(Feature.reports), isTrue);
  });

  test('renewing early keeps the remaining days; lifetime stays lifetime', () {
    const day = 86400000;
    final now = 1000 * day;
    expect(CloudService.newExpiry(now: now, currentExpiry: now + 5 * day, currentActive: true, days: 30), now + 35 * day);
    expect(CloudService.newExpiry(now: now, currentExpiry: now - day, currentActive: false, days: 30), now + 30 * day);
    expect(CloudService.newExpiry(now: now, currentExpiry: now + 5 * day, currentActive: true, days: 0), 0);
  });

  test('default packages are valid', () {
    final p = Package.defaults();
    expect(p.length, 5);
    for (final x in p) {
      expect(Package.fromMap(x.id, x.toMap()).toMap(), x.toMap());
      expect(x.features.every(Feature.all.contains), isTrue);
    }
  });
}
