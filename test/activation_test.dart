// A fresh phone must show the activation screen; nothing else opens until a
// super admin code is applied.
import 'package:bizpos/app.dart';
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/services/drive_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester t, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Db.fileName = 'activation_test.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await AppState.instance.load();
    await LicenseService.instance.load();
    LicenseKeys.trusted.add('bX-2DqGStn1nvQ5vvJ5hUBRlI4awixygow2VCWd3s6U');
  });

  testWidgets('activation gate, then onboarding after a valid code', (t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(412, 915) * 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState.instance),
        ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
        ChangeNotifierProvider<LicenseService>.value(value: LicenseService.instance),
      ],
      child: const BizPosApp(),
    ));
    await settle(t);
    expect(find.text('Activate this phone'), findsOneWidget);
    expect(find.text(LicenseService.instance.deviceCodePretty), findsOneWidget);
    expect(find.textContaining('0322-4699887'), findsWidgets);

    // Super admin screen opens from the gate.
    await t.tap(find.text('Super admin'));
    await settle(t);
    expect(find.text('Master password'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await t.runAsync(() async {
      SuperAdmin.key = await LicenseKeys.derive('test-password-123');
      final code = await SuperAdmin.issue(type: 'act', device: LicenseService.instance.deviceCode, plan: 'trial', storeName: 'Gate Shop', expires: nowMs() + 86400000 * 14);
      await LicenseService.instance.apply(code);
      SuperAdmin.key = null;
    });
    await settle(t);
    expect(find.text('Set up your business'), findsOneWidget);
    final field = t.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'Gate Shop');
  });
}
