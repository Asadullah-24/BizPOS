// Renders the auth and lock screens to PNG files in build/screens so the
// design can be reviewed from CI. Real fonts are loaded so text is readable.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bizpos/app.dart';
import 'package:bizpos/core/access.dart';
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/business_templates.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/models/models.dart';
import 'package:bizpos/services/auth_service.dart';
import 'package:bizpos/services/product_service.dart';
import 'package:bizpos/services/setup_service.dart';
import 'package:bizpos/services/cart.dart';
import 'package:bizpos/services/ledger_service.dart';
import 'package:bizpos/services/sales_service.dart';
import 'package:bizpos/ui/tokens.dart';
import 'package:bizpos/ui/screens/admin/super_admin_hub.dart';
import 'package:bizpos/ui/screens/super_admin/super_admin_login.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/services/cloud_service.dart';
import 'package:bizpos/services/drive_service.dart';
import 'package:bizpos/ui/screens/auth/sign_in_screen.dart';
import 'package:bizpos/ui/screens/auth/welcome_screen.dart';
import 'package:bizpos/ui/screens/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final f = File('assets/fonts/Inter-$w.ttf');
    inter.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  }
  await inter.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await icons.load();
      break;
    }
  }
}

Future<void> _settle(WidgetTester t, [int rounds = 30]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 60));
  }
}

final _shot = GlobalKey();

Widget _wrap(Widget home) => RepaintBoundary(
      key: _shot,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: AppState.instance),
          ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
          ChangeNotifierProvider<LicenseService>.value(value: LicenseService.instance),
          ChangeNotifierProvider<Access>.value(value: Access.instance),
          ChangeNotifierProvider<CloudService>.value(value: CloudService.instance),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: ThemeMode.dark,
          home: home,
        ),
      ),
    );

Widget _wrapApp() => RepaintBoundary(
      key: _shot,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: AppState.instance),
          ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
          ChangeNotifierProvider<LicenseService>.value(value: LicenseService.instance),
          ChangeNotifierProvider<Access>.value(value: Access.instance),
          ChangeNotifierProvider<CloudService>.value(value: CloudService.instance),
        ],
        child: const BizPosApp(),
      ),
    );

Future<void> _save(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screens')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _size(WidgetTester t, Size s) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = s;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Db.fileName = 'screenshots_test.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await AppState.instance.load();
    await LicenseService.instance.load();
    Access.instance.load();
    await _loadFonts();
    await SetupService.createBusiness(
      businessName: 'Asad General Store',
      template: businessTemplates.firstWhere((t) => t.key == 'grocery', orElse: () => businessTemplates.first),
      currencySymbol: 'Rs',
      decimals: 0,
      ownerName: 'Asad',
      pin: '1234',
      language: 'en',
    );
    Tw.shadows = false;
    // Demo shop data so the screens look like a real day in a shop.
    final ids = <String, Product>{};
    for (final (name, cost, price, stock) in [
      ('Basmati Rice 5kg', 1800.0, 2100.0, 24.0),
      ('Sugar 1kg', 140.0, 160.0, 2.0),
      ('Cooking Oil 1L', 520.0, 580.0, 1.0),
      ('Tea Leaves 900g', 1150.0, 1350.0, 18.0),
      ('Milk Pack 1L', 250.0, 280.0, 40.0),
      ('Flour 10kg', 1350.0, 1550.0, 12.0),
      ('Lemon Soap', 90.0, 120.0, 60.0),
      ('Mineral Water 1.5L', 70.0, 100.0, 48.0),
    ]) {
      final p = Product(id: newId(), name: name, costPrice: cost, salePrice: price, lowStock: 5);
      await ProductService.save(p, isNew: true, openingStock: stock);
      ids[name] = (await ProductService.byId(p.id))!;
    }
    final account = (await LedgerService.defaultAccount())!;
    final list = ids.values.toList();
    final now = DateTime.now();
    for (var day = 6; day >= 0; day--) {
      for (var n = 0; n < 3 + (day * 7) % 5; n++) {
        final cart = Cart();
        for (var k = 0; k < 2 + (n % 3); k++) {
          final p = list[(day * 3 + n + k) % list.length];
          cart.add(CartLine(productId: p.id, name: p.name, unitPrice: p.salePrice, qty: 1.0 + (k % 2), costPrice: p.costPrice, trackStock: false));
        }
        final total = cart.compute(taxEnabled: false, taxInclusive: false).total;
        final r = await SalesService.completeSale(cart, [PaymentLine(accountId: account.id, accountName: account.name, amount: total)]);
        final at = DateTime(now.year, now.month, now.day, 10 + n).subtract(Duration(days: day)).millisecondsSinceEpoch;
        await Db.instance.raw.rawUpdate('UPDATE sales SET created_at = ? WHERE id = ?', [at, r.saleId]);
      }
    }
  });

  testWidgets('screenshots: welcome', (t) async {
    _size(t, const Size(412, 915));
    await t.pumpWidget(_wrap(const WelcomeScreen()));
    await _settle(t);
    await _save(t, '1-welcome');
  });

  testWidgets('screenshots: sign in', (t) async {
    _size(t, const Size(412, 915));
    await t.pumpWidget(_wrap(const SignInScreen()));
    await _settle(t);
    await _save(t, '2-sign-in');
  });

  testWidgets('screenshots: sign up', (t) async {
    _size(t, const Size(412, 1000));
    await t.pumpWidget(_wrap(const SignInScreen(signUp: true)));
    await _settle(t);
    await t.enterText(find.byType(TextFormField).at(0), 'Asad Traders');
    await t.enterText(find.byType(TextFormField).at(1), 'shop@example.com');
    await t.enterText(find.byType(TextFormField).at(2), 'Shop2026');
    await _settle(t, 8);
    await _save(t, '3-sign-up');
  });

  testWidgets('screenshots: lock screen', (t) async {
    _size(t, const Size(412, 915));
    await t.pumpWidget(_wrap(const LockScreen()));
    await _settle(t);
    await _save(t, '4-lock');
  });

  testWidgets('screenshots: super admin hub and offline login', (t) async {
    _size(t, const Size(412, 915));
    await t.pumpWidget(_wrap(const SuperAdminHub()));
    await _settle(t);
    await _save(t, '6-super-admin-hub');
    await t.pumpWidget(_wrap(const SuperAdminLogin()));
    await _settle(t);
    await _save(t, '7-offline-codes-login');
  });

  testWidgets('screenshots: main app tabs', (t) async {
    _size(t, const Size(412, 915));
    final owner = await t.runAsync<Employee?>(() => AuthService.login('1234'));
    await AppState.instance.login(owner!);
    await t.pumpWidget(_wrapApp());
    await _settle(t);
    await _save(t, '10-dashboard');
    for (final (tab, file) in [('Sell', '11-sell'), ('Products', '12-products'), ('Sales', '13-sales'), ('More', '14-more')]) {
      await t.tap(find.text(tab).last);
      await _settle(t, 15);
      await _save(t, file);
      if (tab == 'Sell') {
        for (final name in ['Basmati Rice 5kg', 'Tea Leaves 900g', 'Milk Pack 1L', 'Milk Pack 1L']) {
          final f = find.text(name);
          if (f.evaluate().isNotEmpty) {
            await t.tap(f.first, warnIfMissed: false);
            await _settle(t, 3);
          }
        }
        await _save(t, '11b-sell-cart');
      }
    }
    await t.ensureVisible(find.text('Settings').first);
    await _settle(t, 4);
    await t.tap(find.text('Settings').first);
    await _settle(t, 15);
    await _save(t, '15-settings');
  });

  testWidgets('screenshots: tablet welcome', (t) async {
    _size(t, const Size(1280, 800));
    await t.pumpWidget(_wrap(const WelcomeScreen()));
    await _settle(t);
    await _save(t, '5-tablet-welcome');
  });
}
