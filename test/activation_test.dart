// Free start: a fresh phone (no Firebase config in CI) goes straight to shop
// setup. Offline unlock codes still work, and the welcome / sign-in screens render.
import 'package:bizpos/app.dart';
import 'package:bizpos/core/access.dart';
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/core/packages.dart';
import 'package:bizpos/services/cloud_service.dart';
import 'package:bizpos/services/drive_service.dart';
import 'package:bizpos/ui/screens/auth/sign_in_screen.dart';
import 'package:bizpos/ui/screens/auth/welcome_screen.dart';
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

Widget providers(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState.instance),
        ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
        ChangeNotifierProvider<LicenseService>.value(value: LicenseService.instance),
        ChangeNotifierProvider<Access>.value(value: Access.instance),
        ChangeNotifierProvider<CloudService>.value(value: CloudService.instance),
      ],
      child: child,
    );

void phone(WidgetTester t) {
  t.view.devicePixelRatio = 2.0;
  t.view.physicalSize = const Size(412, 915) * 2.0;
  addTearDown(t.view.reset);
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
    Access.instance.load();
    LicenseKeys.trusted.add('bX-2DqGStn1nvQ5vvJ5hUBRlI4awixygow2VCWd3s6U');
  });

  testWidgets('fresh phone opens shop setup with no activation', (t) async {
    phone(t);
    await t.pumpWidget(providers(const BizPosApp()));
    await settle(t);
    expect(find.text('Set up your business'), findsOneWidget);
    expect(Access.instance.isPaid, isFalse);
    expect(Access.instance.has(Feature.reports), isFalse);

    // An offline code still unlocks paid features.
    await t.runAsync(() async {
      SuperAdmin.key = await LicenseKeys.derive('test-password-123');
      await LicenseService.instance.apply(await SuperAdmin.issue(
          type: 'act', device: LicenseService.instance.deviceCode, plan: 'basic', storeName: 'Code Shop'));
      SuperAdmin.key = null;
    });
    await settle(t, 3);
    expect(Access.instance.has(Feature.reports), isTrue);
    expect(Access.instance.isPaid, isTrue);
  });

  testWidgets('welcome and sign-up screens render and validate', (t) async {
    phone(t);
    await t.pumpWidget(providers(MaterialApp(theme: buildTheme(Brightness.dark), home: const WelcomeScreen())));
    await settle(t, 6);
    expect(find.text('Create free account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Use without an account (offline)'), findsOneWidget);

    await t.pumpWidget(providers(MaterialApp(theme: buildTheme(Brightness.dark), home: const SignInScreen(signUp: true))));
    await settle(t, 6);
    await t.tap(find.text('Create account'));
    await t.pump();
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Enter your email.'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(1), 'shop@example.com');
    await t.enterText(find.byType(TextFormField).at(2), 'short');
    await t.tap(find.text('Create account'));
    await t.pump();
    expect(find.text('At least 8 characters.'), findsOneWidget);
  });
}
