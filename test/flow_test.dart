// End-to-end business flows against a real SQLite database (sqflite FFI).
import 'package:bizpos/core/app_state.dart';
import 'package:bizpos/core/business_templates.dart';
import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/ids.dart';
import 'package:bizpos/models/models.dart';
import 'package:bizpos/services/auth_service.dart';
import 'package:bizpos/services/backup_service.dart';
import 'package:bizpos/services/cart.dart';
import 'package:bizpos/services/inventory_service.dart';
import 'package:bizpos/services/ledger_service.dart';
import 'package:bizpos/services/product_service.dart';
import 'package:bizpos/services/purchase_service.dart';
import 'package:bizpos/services/report_service.dart';
import 'package:bizpos/services/return_service.dart';
import 'package:bizpos/services/sales_service.dart';
import 'package:bizpos/services/setup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<double> stockOf(String id) async => (await ProductService.byId(id))!.stock;

Future<double> cashBalance() async => (await LedgerService.defaultAccount())!.balance;

Cart cartWith(Product p, double qty) => Cart()
  ..add(CartLine(
    productId: p.id,
    name: p.displayName,
    unitPrice: p.salePrice,
    costPrice: p.costPrice,
    qty: qty,
    trackStock: p.trackStock,
  ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Product rice;
  late String cashId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    Db.fileName = 'flow_test.db';
    await Db.instance.init();
    await Db.instance.wipe();
    await AppState.instance.load();
  });

  test('onboarding creates business, owner and PIN login', () async {
    await SetupService.createBusiness(
      businessName: 'Test Mart',
      template: businessTemplates.first,
      currencySymbol: 'Rs',
      decimals: 0,
      ownerName: 'Owner',
      pin: '1234',
      language: 'en',
    );
    expect(AppState.instance.onboarded, isTrue);
    expect(await AuthService.login('9999'), isNull);
    final owner = await AuthService.login('1234');
    expect(owner, isNotNull);
    expect(owner!.isOwner, isTrue);
    await AppState.instance.login(owner);
    expect(AppState.instance.businessType?.name, businessTemplates.first.name);
    expect((await LedgerService.accounts()).length, 3);
    cashId = (await LedgerService.defaultAccount())!.id;
  });

  test('product with opening stock', () async {
    final p = Product(id: newId(), name: 'Rice', costPrice: 100, salePrice: 150, lowStock: 2);
    await ProductService.save(p, isNew: true, openingStock: 10);
    rice = (await ProductService.byId(p.id))!;
    expect(rice.stock, 10);
    expect(await ProductService.findByCode('nothing'), isNull);
  });

  test('cash sale reduces stock, records payment and gives change', () async {
    final res = await SalesService.completeSale(
      cartWith(rice, 2),
      [PaymentLine(accountId: cashId, accountName: 'Cash', amount: 500)],
    );
    expect(res.change, 200);
    expect(await stockOf(rice.id), 8);
    expect(await cashBalance(), 300);
    final sale = await SalesService.sale(res.saleId);
    expect(sale!['total'], 300);
    expect((sale['invoice_no'] as String).startsWith('INV-'), isTrue);

    final r = await ReportService.build(Period.of(PeriodKind.day));
    expect(r.sales, 300);
    expect(r.cogs, 200);
    expect(r.grossProfit, 100);
    expect(r.topProducts.first['name'], 'Rice');
  });

  test('refund return puts stock back and pays out', () async {
    final sales = await SalesService.list();
    final saleId = sales.first['id'] as String;
    final items = await SalesService.items(saleId);
    await ReturnService.create(
      saleId: saleId,
      lines: [ReturnLineInput(saleItem: items.first, qty: 1)],
      type: 'refund',
      refundAccountId: cashId,
    );
    expect(await stockOf(rice.id), 9);
    expect(await cashBalance(), 150);
    final r = await ReportService.build(Period.of(PeriodKind.day));
    expect(r.netSales, 150);
    expect(r.grossProfit, 50);
    await expectLater(
      ReturnService.create(saleId: saleId, lines: [ReturnLineInput(saleItem: items.first, qty: 2)], type: 'refund', refundAccountId: cashId),
      throwsStateError,
    );
  });

  test('credit sale needs a customer and builds a balance', () async {
    await expectLater(SalesService.completeSale(cartWith(rice, 1), []), throwsStateError);
    final cid = await Db.instance.s.insert('customers', {'name': 'Ali', 'phone': '0300'});
    final cart = cartWith(rice, 1)..customerId = cid;
    await SalesService.completeSale(cart, []);
    expect((await LedgerService.party('customer', cid))!.balance, 150);
    await LedgerService.settle(kind: 'customer', partyId: cid, accountId: cashId, amount: 100);
    expect((await LedgerService.party('customer', cid))!.balance, 50);
    expect(await LedgerService.totalBalance('customer'), 50);
    expect(await stockOf(rice.id), 8);
  });

  test('exchange: return value becomes credit for a new sale', () async {
    final custs = await LedgerService.parties('customer');
    final ali = custs.first;
    final before = ali.balance;
    final sale = (await SalesService.list()).firstWhere((s) => s['customer_id'] == ali.id);
    final items = await SalesService.items(sale['id'] as String);
    final ret = await ReturnService.create(
      saleId: sale['id'] as String,
      lines: [ReturnLineInput(saleItem: items.first, qty: 1)],
      type: 'exchange',
    );
    expect(ret.total, 150);
    final cart = cartWith(rice, 2)
      ..customerId = ali.id
      ..exchangeCredit = ret.total
      ..exchangeReturnId = ret.id;
    final cashBefore = await cashBalance();
    await SalesService.completeSale(cart, [PaymentLine(accountId: cashId, accountName: 'Cash', amount: 150)]);
    expect(await cashBalance(), cashBefore + 150);
    expect((await LedgerService.party('customer', ali.id))!.balance, before);
    expect(await stockOf(rice.id), 7);
  });

  test('cancel sale restores stock and refunds payments', () async {
    final cashBefore = await cashBalance();
    final res = await SalesService.completeSale(
      cartWith(rice, 1),
      [PaymentLine(accountId: cashId, accountName: 'Cash', amount: 150)],
    );
    expect(await stockOf(rice.id), 6);
    await SalesService.cancelSale(res.saleId, reason: 'test');
    expect(await stockOf(rice.id), 7);
    expect(await cashBalance(), cashBefore);
    expect((await SalesService.sale(res.saleId))!['status'], 'cancelled');
  });

  test('purchase adds stock with weighted average cost and supplier balance', () async {
    final sid = await Db.instance.s.insert('suppliers', {'name': 'Wholesaler'});
    await PurchaseService.create(
      supplierId: sid,
      lines: [PurchaseLine(productId: rice.id, name: 'Rice', qty: 7, unitCost: 200)],
    );
    final p = (await ProductService.byId(rice.id))!;
    expect(p.stock, 14);
    expect(p.costPrice, closeTo((7 * 100 + 7 * 200) / 14, 0.001));
    expect((await LedgerService.party('supplier', sid))!.balance, 1400);
    await expectLater(PurchaseService.create(lines: [PurchaseLine(productId: rice.id, name: 'Rice', qty: 1, unitCost: 1)]), throwsStateError);
  });

  test('stock adjustment and low stock', () async {
    await InventoryService.adjust(productId: rice.id, mode: 'set', qty: 1);
    expect(await stockOf(rice.id), 1);
    expect((await ProductService.lowStock()).map((p) => p.id), contains(rice.id));
    await InventoryService.adjust(productId: rice.id, mode: 'add', qty: 9);
    expect(await stockOf(rice.id), 10);
  });

  test('variants are sold individually', () async {
    final shirt = Product(id: newId(), name: 'Shirt', salePrice: 1000, hasVariants: true);
    await ProductService.save(shirt, isNew: true, variants: [
      VariantInput(name: 'Red / M', price: 1000, cost: 600, openingStock: 3),
      VariantInput(name: 'Blue / L', price: 1100, cost: 650, openingStock: 2),
    ]);
    final sellable = await ProductService.sellable(search: 'Shirt');
    expect(sellable.length, 2);
    expect(sellable.every((p) => p.parentId == shirt.id), isTrue);
    final cat = await ProductService.catalogue(search: 'Shirt');
    expect(cat.single.stock, 5);
  });

  test('expense reduces account and profit', () async {
    final before = await cashBalance();
    final cats = await ProductService.categories('expense');
    await ExpenseService.add(categoryId: cats.first.id, amount: 50, accountId: cashId, date: DateTime.now().millisecondsSinceEpoch);
    expect(await cashBalance(), before - 50);
    final r = await ReportService.build(Period.of(PeriodKind.day));
    expect(r.expenses, 50);
  });

  test('backup merge is idempotent, keeps newer edits, and restores after wipe', () async {
    final snap = await BackupService.snapshot();
    final encoded = BackupService.encode(snap);
    final salesCount = (await SalesService.list(limit: 1000)).length;
    final stock = await stockOf(rice.id);
    final cash = await cashBalance();

    // Same data again: nothing new.
    final again = await BackupService.merge(BackupService.decode(encoded));
    expect(again.inserted, 0);
    expect(again.updated, 0);
    expect(await stockOf(rice.id), stock);

    // Local edit made after the backup wins over the older backup copy.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await Db.instance.s.update('products', rice.id, {'name': 'Basmati Rice'});
    await BackupService.merge(BackupService.decode(encoded));
    expect((await ProductService.byId(rice.id))!.name, 'Basmati Rice');

    // Another phone sold offline: its sale is added, not overwritten.
    final other = BackupService.decode(encoded);
    final tables = other['tables'] as Map<String, dynamic>;
    final saleId = newId();
    final now = DateTime.now().millisecondsSinceEpoch;
    (tables['sales'] as List).add({
      'id': saleId, 'created_at': now, 'updated_at': now, 'device_id': 'other', 'invoice_no': 'INV-OTHR-00001',
      'total': 150, 'paid': 150, 'subtotal': 150, 'status': 'completed', 'cost_total': 100, 'items_count': 1,
    });
    (tables['stock_movements'] as List).add({
      'id': newId(), 'created_at': now, 'updated_at': now, 'device_id': 'other', 'product_id': rice.id, 'qty': -1, 'type': 'sale', 'ref_id': saleId,
    });
    final r = await BackupService.merge(other);
    expect(r.inserted, 2);
    expect(await stockOf(rice.id), stock - 1);
    expect((await SalesService.list(limit: 1000)).length, salesCount + 1);

    // Full restore on an empty phone.
    await Db.instance.wipe();
    expect((await SalesService.list(limit: 1000)).length, 0);
    await BackupService.merge(BackupService.decode(encoded));
    expect((await SalesService.list(limit: 1000)).length, salesCount);
    expect(await stockOf(rice.id), stock);
    expect(await cashBalance(), cash);
    expect(AppState.instance.onboarded, isTrue);
  });
}
