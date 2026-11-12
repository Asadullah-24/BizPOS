// Renders the real app on phone and tablet sizes and walks through every
// main screen and a full sale, so layout errors and crashes fail CI.
import 'package:bizpos/app.dart';
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/business_templates.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/models/models.dart';
import 'package:bizpos/services/auth_service.dart';
import 'package:bizpos/services/drive_service.dart';
import 'package:bizpos/services/product_service.dart';
import 'package:bizpos/services/setup_service.dart';
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

Widget app() => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState.instance),
        ChangeNotifierProvider<DriveService>.value(value: DriveService.instance),
      ],
      child: const BizPosApp(),
    );

void setSize(WidgetTester t, Size logical) {
  t.view.devicePixelRatio = 2.0;
  t.view.physicalSize = logical * 2.0;
  addTearDown(t.view.reset);
}

Future<void> openFromMore(WidgetTester t, String label) async {
  await t.tap(find.text('More').last);
  await settle(t, 3);
  final item = find.text(label);
  await t.ensureVisible(item.first);
  await t.pump();
  await t.tap(item.first);
  await settle(t);
  expect(t.takeException(), isNull, reason: 'opening $label');
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await settle(t, 3);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Db.fileName = 'smoke_test.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await SetupService.createBusiness(
      businessName: 'Smoke Shop',
      template: businessTemplates.firstWhere((t) => t.key == 'clothing'),
      currencySymbol: 'Rs',
      decimals: 0,
      ownerName: 'Owner',
      pin: '1234',
      language: 'en',
    );
    await ProductService.save(
      Product(id: newId(), name: 'Rice', costPrice: 100, salePrice: 150, lowStock: 2),
      isNew: true,
      openingStock: 10,
    );
    await ProductService.save(
      Product(id: newId(), name: 'Shirt', salePrice: 1000, hasVariants: true),
      isNew: true,
      variants: [VariantInput(name: 'Red / M', price: 1000, cost: 600, openingStock: 3)],
    );
  });

  testWidgets('lock screen rejects a wrong PIN', (t) async {
    setSize(t, const Size(412, 915));
    AppState.instance.lock();
    await t.pumpWidget(app());
    await settle(t);
    expect(find.text('Enter PIN'), findsOneWidget);
    for (final d in ['9', '9', '9', '9']) {
      await t.tap(find.text(d).last);
      await t.pump();
    }
    await t.tap(find.byIcon(Icons.arrow_forward));
    await settle(t);
    expect(find.text('Wrong PIN'), findsOneWidget);
  });

  testWidgets('phone: every screen renders and a sale completes', (t) async {
    setSize(t, const Size(412, 915));
    final owner = await t.runAsync<Employee?>(() => AuthService.login('1234'));
    await AppState.instance.login(owner!);
    await t.pumpWidget(app());
    await settle(t);
    expect(find.text('Smoke Shop'), findsWidgets);

    // Sell: add a product, open the cart, check out with cash.
    await t.tap(find.text('Sell').last);
    await settle(t);
    await t.tap(find.text('Rice').first);
    await settle(t, 3);
    await t.tap(find.text('View cart'));
    await settle(t);
    await t.tap(find.textContaining('Charge'));
    await settle(t);
    expect(find.text('Checkout'), findsOneWidget);
    await t.tap(find.text('Complete sale'));
    await settle(t, 12);
    expect(find.text('Sale completed'), findsOneWidget);
    await t.tap(find.text('New sale'));
    await settle(t);

    // Variant picker opens from the catalogue.
    await t.tap(find.text('Shirt').first);
    await settle(t, 4);
    expect(find.text('Red / M'), findsOneWidget);
    await t.tap(find.text('Red / M'));
    await settle(t, 3);

    for (final tab in ['Products', 'Sales', 'Dashboard']) {
      await t.tap(find.text(tab).last);
      await settle(t);
      expect(t.takeException(), isNull, reason: tab);
    }

    for (final label in [
      'Inventory', 'Categories', 'Customers', 'Suppliers', 'Purchases', 'Expenses', 'Accounts',
      'Reports', 'Returns', 'Employees', 'Activity log', 'Backup & restore', 'Settings',
    ]) {
      await openFromMore(t, label);
    }

    // Open the sale that was just made.
    await t.tap(find.text('Sales').last);
    await settle(t);
    await t.tap(find.textContaining('INV-').first);
    await settle(t);
    expect(find.text('Return / exchange items'), findsOneWidget);

    // Product form opens for a new product.
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.popUntil((r) => r.isFirst);
    await settle(t, 3);
    await t.tap(find.text('Products').last);
    await settle(t);
    await t.tap(find.text('Add product'));
    await settle(t);
    expect(find.text('Product name'), findsOneWidget);
    nav.popUntil((r) => r.isFirst);
    await settle(t, 3);

    // Switching to Urdu flips the app to right-to-left.
    AppState.instance.previewLanguage('ur');
    await settle(t, 3);
    expect(Directionality.of(t.element(find.byType(Scaffold).first)), TextDirection.rtl);
    AppState.instance.previewLanguage('en');
    await settle(t, 3);
  });

  testWidgets('tablet: POS shows catalogue and cart side by side', (t) async {
    setSize(t, const Size(1280, 800));
    await t.pumpWidget(app());
    await settle(t);
    await t.tap(find.text('Sell').last);
    await settle(t);
    await t.tap(find.text('Rice').first);
    await settle(t, 3);
    expect(find.textContaining('Charge'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
