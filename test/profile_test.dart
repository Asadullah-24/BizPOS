// Several stores on one phone: each profile has its own database and settings.
import 'package:bizpos/core/access.dart';
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/business_templates.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/services/profile_service.dart';
import 'package:bizpos/services/setup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching stores keeps each store\'s data apart', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Local.prefs = await SharedPreferences.getInstance();
    final profiles = ProfileService.instance;
    await profiles.load();
    Db.fileName = 'profile_test_a.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await AppState.instance.load();
    await LicenseService.instance.load();
    Access.instance.load();
    await SetupService.createBusiness(
      businessName: 'Store A',
      template: businessTemplates.first,
      currencySymbol: 'Rs',
      decimals: 0,
      ownerName: 'A',
      pin: '1111',
      language: 'en',
    );
    await profiles.rememberActive(uid: 'uid-a', email: 'a@example.com');
    await Local.prefs.setBool(Local.k('offline_mode'), true);

    final b = await profiles.create(uid: 'uid-b', email: 'b@example.com');
    await profiles.switchTo(b);
    expect(Db.fileName, isNot('profile_test_a.db'));
    expect(AppState.instance.onboarded, isFalse, reason: 'new store starts empty');
    expect(Local.prefs.getBool(Local.k('offline_mode')), isNull, reason: 'settings are per store');
    await Db.instance.wipe();

    await profiles.switchTo(ProfileService.defaultId);
    await Db.instance.reopen('profile_test_a.db');
    await AppState.instance.load();
    expect(AppState.instance.businessName, 'Store A');
    expect(Local.prefs.getBool(Local.k('offline_mode')), isTrue);
    expect(profiles.byUid('uid-b')?.id, b);
    expect(profiles.byUid('uid-a')?.id, ProfileService.defaultId);
  });
}
