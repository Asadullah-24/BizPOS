import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import 'cart.dart';
import 'cloud_service.dart';
import 'ledger_service.dart';
import 'product_service.dart';
import 'sales_service.dart';
import 'store_service.dart';

/// Turns website orders into BizPOS sales on the shop phone.
///
/// Confirm: saves the customer (matched by phone), records a sale on credit
/// (stock goes down), and marks the order confirmed.
/// Delivered: records the payment and gives the shopper BizPOS coins.
/// Cancel: cancels the sale (stock goes back).
class OnlineOrderService {
  static String code(String orderId) => orderId.length < 6 ? orderId.toUpperCase() : orderId.substring(0, 6).toUpperCase();

  static String _digits(String phone) {
    final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// Existing customer with the same phone number, or a new one.
  static Future<String> customerFor(Map<String, dynamic> o) async {
    final s = Db.instance.s;
    final phone = '${o['customerPhone'] ?? ''}';
    final key = _digits(phone);
    if (key.isNotEmpty) {
      final rows = await s.q('SELECT id, phone FROM customers WHERE deleted_at IS NULL AND phone IS NOT NULL');
      for (final r in rows) {
        if (_digits('${r['phone']}') == key) return r['id'] as String;
      }
    }
    return s.insert('customers', {
      'name': '${o['customerName'] ?? 'Online customer'}'.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'address': '${o['address'] ?? ''}'.trim().isEmpty ? null : '${o['address']}'.trim(),
      'notes': 'From online store',
    });
  }

  /// The sale made for an order, if any.
  static Future<String?> saleFor(String orderId) async {
    final r = await Db.instance.s.one('SELECT id FROM sales WHERE ref = ? AND deleted_at IS NULL', [orderId]);
    return r?['id'] as String?;
  }

  static Future<String> confirm(Map<String, dynamic> o) async {
    final id = o['id'] as String;
    var saleId = await saleFor(id);
    if (saleId == null) {
      final customerId = await customerFor(o);
      final cart = Cart()
        ..customerId = customerId
        ..customerName = '${o['customerName'] ?? ''}'
        ..note = 'Online order #${code(id)}'
        ..source = 'online'
        ..ref = id;
      for (final it in ((o['items'] as List?) ?? []).cast<Map>()) {
        final pid = '${it['id'] ?? ''}';
        final p = pid.isEmpty ? null : await ProductService.byId(pid);
        cart.add(CartLine(
          productId: p?.id,
          name: '${it['name'] ?? p?.name ?? ''}',
          unitPrice: ((it['price'] ?? 0) as num).toDouble(),
          qty: ((it['qty'] ?? 1) as num).toDouble(),
          costPrice: p?.costPrice ?? 0,
          unit: p?.unit,
          trackStock: p?.trackStock ?? false,
          stock: p?.stock ?? 0,
        ));
      }
      // Paid on delivery, so the sale starts on the customer's account.
      saleId = (await SalesService.completeSale(cart, const [])).saleId;
    }
    await StoreService.instance.setOrderStatus(id, 'confirmed');
    return saleId;
  }

  static Future<void> deliver(Map<String, dynamic> o) async {
    final id = o['id'] as String;
    await confirm(o);
    final sale = await SalesService.sale((await saleFor(id))!);
    final due = ((sale?['total'] ?? 0) as num).toDouble() - ((sale?['paid'] ?? 0) as num).toDouble();
    final account = await LedgerService.defaultAccount();
    final customerId = sale?['customer_id'] as String?;
    if (due > 0.0001 && account != null && customerId != null) {
      final coinPart = ((o['coinDiscount'] ?? 0) as num).toDouble().clamp(0, due).toDouble();
      final cash = due - coinPart;
      if (cash > 0.0001) {
        await LedgerService.settle(
            kind: 'customer', partyId: customerId, accountId: account.id, amount: Fmt.round(cash),
            note: 'Online order #${code(id)}', employeeId: AppState.instance.user?.id);
      }
      if (coinPart > 0.0001) {
        await LedgerService.settle(
            kind: 'customer', partyId: customerId, accountId: account.id, amount: Fmt.round(coinPart),
            note: 'BizPOS coins discount, order #${code(id)} (paid by BizPOS)', employeeId: AppState.instance.user?.id);
      }
    }
    await _deliveredWithCoins(o);
  }

  /// Marks delivered and, when coins are on, gives the shopper coins.
  static Future<void> _deliveredWithCoins(Map<String, dynamic> o) async {
    final cloud = CloudService.instance;
    final db = cloud.db;
    final id = o['id'] as String;
    final uid = '${o['customerUid'] ?? ''}';
    final settings = cloud.appSettings;
    final perHundred = ((settings['coinsPerHundred'] ?? 0) as num).toDouble();
    final coins = (((o['total'] ?? 0) as num).toDouble() / 100 * perHundred).floor();
    final award = settings['coinsEnabled'] == true && uid.isNotEmpty && coins > 0 && o['coinsAwarded'] == null;
    final batch = db.batch();
    batch.update(db.doc('orders/$id'), {
      'status': 'delivered',
      if (award) 'coinsAwarded': coins,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (award) {
      batch.set(db.doc('coinAwards/$id'), {
        'uid': uid,
        'coins': coins,
        'shopId': o['shopId'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(db.doc('shoppers/$uid'), {'coins': FieldValue.increment(coins), 'lastAward': id});
    }
    try {
      await batch.commit();
    } catch (_) {
      if (!award) rethrow;
      // Coins could not be given (for example the shopper account is gone): still deliver.
      await StoreService.instance.setOrderStatus(id, 'delivered');
    }
  }

  static Future<void> cancel(Map<String, dynamic> o) async {
    final id = o['id'] as String;
    final saleId = await saleFor(id);
    if (saleId != null) {
      final sale = await SalesService.sale(saleId);
      if (sale?['status'] != 'cancelled') await SalesService.cancelSale(saleId, reason: 'Online order cancelled');
    }
    await StoreService.instance.setOrderStatus(id, 'cancelled');
  }

  /// WhatsApp text to the customer for a status change.
  static String message(Map<String, dynamic> o, String status) {
    final shop = AppState.instance.businessName;
    final cur = '${o['currency'] ?? 'Rs'}';
    final total = ((o['total'] ?? 0) as num).toDouble() - ((o['coinDiscount'] ?? 0) as num).toDouble();
    final track = '${StoreService.webBase}?o=${o['id']}';
    final c = code(o['id'] as String);
    final name = '${o['customerName'] ?? ''}';
    return switch (status) {
      'confirmed' => 'Assalam o Alaikum $name! Your order #$c from $shop is confirmed. '
          'Amount to pay: $cur ${total.toStringAsFixed(0)}. We will deliver soon.\nTrack: $track',
      'delivered' => 'Thank you $name! Your order #$c from $shop has been delivered. We hope to serve you again.',
      'cancelled' => 'Sorry $name, your order #$c from $shop has been cancelled. Please call us for help.',
      _ => 'Order #$c from $shop: $track',
    };
  }

  static Future<void> whatsapp(String phone, String text) async {
    var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('0')) d = '92${d.substring(1)}';
    if (d.isEmpty) return;
    await launchUrl(Uri.parse('https://wa.me/$d?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }
}
