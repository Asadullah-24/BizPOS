import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../core/packages.dart';
import '../models/models.dart';
import 'alert_service.dart';
import 'cloud_service.dart';
import 'product_service.dart';

/// Online store: the shop's public page on the BizPOS website, its products,
/// customer orders, and the super admin's marketplace controls.
///
/// Firestore:
/// - storefronts/{shopId}: public store card (published, adminHidden, paidUntil)
/// - storefronts/{shopId}/items/{productId}: products shown online
/// - orders/{id}: orders placed on the website
/// - featured/{id}: hot products and deals picked by the super admin
/// - settings/app: marketplaceOpen, onlineDefaultLimit
class StoreService extends ChangeNotifier {
  StoreService._();
  static final StoreService instance = StoreService._();

  /// Free website address used until the super admin sets their own domain.
  static const defaultWebBase = 'https://asadullah-24.github.io/BizPOS/';

  /// Website address (settings/app.websiteUrl), always ending with "/".
  static String get webBase {
    var u = '${CloudService.instance.appSettings['websiteUrl'] ?? ''}'.trim();
    if (u.isEmpty) return defaultWebBase;
    if (!u.startsWith('http')) u = 'https://$u';
    return u.endsWith('/') ? u : '$u/';
  }

  static String storeUrl(String shopId) => '$webBase?s=$shopId';

  /// Brand shown on the website (settings/app.brandName / brandLogo).
  String get brandName => '${_cloud.appSettings['brandName'] ?? ''}'.trim().isEmpty ? 'BizPOS' : '${_cloud.appSettings['brandName']}'.trim();
  String get brandLogo => '${_cloud.appSettings['brandLogo'] ?? ''}';

  static const defaultOnlineLimit = 3;

  CloudService get _cloud => CloudService.instance;
  FirebaseFirestore get _db => _cloud.db;

  // ---------------------------------------------------------------- settings

  int get defaultLimit => (_cloud.appSettings['onlineDefaultLimit'] as num?)?.toInt() ?? defaultOnlineLimit;
  bool get marketplaceOpen => _cloud.appSettings['marketplaceOpen'] != false;

  /// How many products [shop] may show online: null = no online store
  /// (free plan), 0 = no limit.
  int? allowanceFor(Map<String, dynamic>? shop) {
    if (shop == null) return null;
    final override = shop['onlineLimit'] as num?;
    if (override != null) return override.toInt();
    if (!CloudPlan.fromShop(shop).activeAt(nowMs())) return null;
    final fromPackage = shop['onlineProducts'] as num?;
    return fromPackage?.toInt() ?? defaultLimit;
  }

  int? get myAllowance => allowanceFor(_cloud.shop);

  // ---------------------------------------------------------------- owner

  Stream<Map<String, dynamic>?> storefront(String shopId) =>
      _db.doc('storefronts/$shopId').snapshots().map((s) => s.data());

  Stream<List<Map<String, dynamic>>> items(String shopId) => _db
      .collection('storefronts/$shopId/items')
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Map<String, dynamic> _card(String shopId) {
    final app = AppState.instance;
    final shop = _cloud.shop ?? {};
    return {
      'shopId': shopId,
      'ownerUid': _cloud.user!.uid,
      'name': app.businessName,
      'category': app.businessType?.name ?? '',
      'phone': app.settings['business_phone'] ?? '',
      'address': app.settings['business_address'] ?? '',
      'city': shop['city'] ?? '',
      'currency': app.settings['currency_symbol'] ?? 'Rs',
      'paidUntil': ((shop['expiresAt'] ?? 0) as num).toInt(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Turns the online store on or off for this shop.
  Future<void> setPublished(bool on) async {
    final id = _requireShop();
    if (on && myAllowance == null) throw StateError('The online store is part of the paid plans.');
    final ref = _db.doc('storefronts/$id');
    final exists = (await ref.get()).exists;
    await ref.set({
      ..._card(id),
      'published': on,
      if (!exists) 'adminHidden': false,
      if (!exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    notifyListeners();
  }

  /// Shows [p] on the online store, within the plan's limit.
  Future<void> publish(Product p, {required int currentCount}) async {
    final id = _requireShop();
    final allowance = myAllowance;
    if (allowance == null) throw StateError('The online store is part of the paid plans.');
    if (allowance > 0 && currentCount >= allowance) {
      throw StateError('Your plan shows $allowance products online. Ask BizPOS support for more.');
    }
    await _db.doc('storefronts/$id/items/${p.id}').set(await _itemData(p));
  }

  Future<void> unpublish(String productId) async {
    final id = _requireShop();
    await _db.doc('storefronts/$id/items/$productId').delete();
  }

  /// Refreshes name, price, stock and photo of every product shown online,
  /// and the store card (name, phone, plan expiry).
  Future<void> syncAll() async {
    final id = _cloud.shopId;
    if (id == null || !_cloud.signedIn) return;
    final store = await _db.doc('storefronts/$id').get();
    if (!store.exists) return;
    await _db.doc('storefronts/$id').set(_card(id), SetOptions(merge: true));
    final online = await _db.collection('storefronts/$id/items').get();
    for (final d in online.docs) {
      final row = await Db.instance.s.byId('products', d.id);
      if (row == null || row['deleted_at'] != null) {
        await d.reference.delete();
        continue;
      }
      final p = await ProductService.byId(d.id);
      if (p != null) await d.reference.set(await _itemData(p, keepThumb: d.data()['thumb'] as String?), SetOptions(merge: true));
    }
  }

  /// Called after a product is saved: refresh it online if it is published.
  Future<void> productChanged(String productId) async {
    final id = _cloud.shopId;
    if (id == null || !_cloud.signedIn) return;
    try {
      final ref = _db.doc('storefronts/$id/items/$productId');
      final d = await ref.get();
      if (!d.exists) return;
      final p = await ProductService.byId(productId);
      if (p != null) await ref.set(await _itemData(p), SetOptions(merge: true));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _itemData(Product p, {String? keepThumb}) async {
    final cat = p.categoryId == null ? null : await Db.instance.s.byId('categories', p.categoryId!);
    return {
      'name': p.name,
      'price': p.salePrice,
      'unit': p.unit ?? '',
      'category': cat?['name'] ?? '',
      'inStock': !p.trackStock || p.stock > 0 || p.hasVariants,
      'thumb': keepThumb ?? await _thumb(p.image) ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Small JPEG (data URL) of the product photo for the website.
  Future<String?> _thumb(String? image) async {
    final f = await ImageStore.file(image);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    final jpg = await compute(_shrink, bytes);
    return jpg == null ? null : 'data:image/jpeg;base64,${base64Encode(jpg)}';
  }

  String _requireShop() {
    final id = _cloud.shopId;
    if (!_cloud.signedIn || id == null) throw StateError('Sign in to your BizPOS account first.');
    return id;
  }

  // ---------------------------------------------------------------- orders

  Stream<List<Map<String, dynamic>>> orders() {
    final u = _cloud.user;
    if (u == null) return Stream.value(const []);
    return _db
        .collection('orders')
        .where('ownerUid', isEqualTo: u.uid)
        .snapshots()
        .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList()
          ..sort((a, b) => _ms(b['createdAt']).compareTo(_ms(a['createdAt']))));
  }

  Future<void> setOrderStatus(String orderId, String status) =>
      _db.doc('orders/$orderId').update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});

  int newOrders = 0;
  StreamSubscription? _orderSub;
  String? _watchingUid;

  /// Notifies the owner about new website orders while the app is open.
  void watchOrders() {
    final u = _cloud.user;
    if (u == null) {
      _orderSub?.cancel();
      _orderSub = null;
      _watchingUid = null;
      return;
    }
    if (_watchingUid == u.uid) return;
    _watchingUid = u.uid;
    _orderSub?.cancel();
    _orderSub = _db
        .collection('orders')
        .where('ownerUid', isEqualTo: u.uid)
        .where('status', isEqualTo: 'new')
        .snapshots()
        .listen((q) async {
      newOrders = q.docs.length;
      notifyListeners();
      final seen = (Local.prefs.getStringList('orders_seen') ?? []).toSet();
      for (final d in q.docs) {
        if (seen.contains(d.id)) continue;
        seen.add(d.id);
        final o = d.data();
        await AlertService.notify(
          d.id.hashCode & 0x7fffffff,
          'New online order',
          '${o['customerName'] ?? ''} · ${o['currency'] ?? 'Rs'} ${((o['total'] ?? 0) as num).toStringAsFixed(0)}',
        );
      }
      await Local.prefs.setStringList('orders_seen', seen.toList().takeLast(300));
    }, onError: (_) {});
  }

  // ---------------------------------------------------------------- stats

  /// Sends the shop's counts to the super admin (at most every 6 hours).
  Future<void> pushStats({bool force = false}) async {
    final id = _cloud.shopId;
    if (id == null || !_cloud.signedIn) return;
    final last = Local.prefs.getInt('stats_pushed') ?? 0;
    if (!force && nowMs() - last < 6 * 3600000) return;
    try {
      final s = Db.instance.s;
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month).millisecondsSinceEpoch;
      await _db.doc('shops/$id').update({
        'stats': {
          'products': await ProductService.count(),
          'customers': (await s.scalar('SELECT COUNT(*) FROM customers WHERE deleted_at IS NULL')).toInt(),
          'suppliers': (await s.scalar('SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL')).toInt(),
          'salesMonth': await s.scalar(
              "SELECT COALESCE(SUM(total),0) FROM sales WHERE deleted_at IS NULL AND status != 'cancelled' AND created_at >= ?", [monthStart]),
          'salesCountMonth': (await s.scalar(
                  "SELECT COUNT(*) FROM sales WHERE deleted_at IS NULL AND status != 'cancelled' AND created_at >= ?", [monthStart]))
              .toInt(),
          'lastSale': (await s.scalar('SELECT COALESCE(MAX(created_at),0) FROM sales WHERE deleted_at IS NULL')).toInt(),
          'at': nowMs(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await Local.prefs.setInt('stats_pushed', nowMs());
    } catch (_) {}
  }

  // ---------------------------------------------------------------- super admin

  Stream<List<Map<String, dynamic>>> allStorefronts() => _db
      .collection('storefronts')
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> featured() => _db
      .collection('featured')
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> ordersOf(String shopId) => _db
      .collection('orders')
      .where('shopId', isEqualTo: shopId)
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) => _ms(b['createdAt']).compareTo(_ms(a['createdAt']))));

  Future<void> saveMarketSettings({bool? open, int? defaultLimit, String? websiteUrl, String? brandName, String? brandLogo}) =>
      _db.doc('settings/app').set({
        if (open != null) 'marketplaceOpen': open,
        if (defaultLimit != null) 'onlineDefaultLimit': defaultLimit,
        if (websiteUrl != null) 'websiteUrl': websiteUrl.trim(),
        if (brandName != null) 'brandName': brandName.trim(),
        if (brandLogo != null) 'brandLogo': brandLogo,
      }, SetOptions(merge: true));

  /// Square logo (data URL) for the website, from a picked image file.
  static Future<String?> logoFromBytes(Uint8List bytes) async {
    final jpg = await compute(_logo, bytes);
    return jpg == null ? null : 'data:image/png;base64,${base64Encode(jpg)}';
  }

  /// Super admin: hide or show a store on the website.
  Future<void> setHidden(String shopId, bool hidden) => _db
      .doc('storefronts/$shopId')
      .update({'adminHidden': hidden, 'updatedAt': FieldValue.serverTimestamp()});

  /// Super admin: own online product limit for a shop (null = follow the plan).
  Future<void> setOnlineLimit(String shopId, int? limit) => _db.doc('shops/$shopId').update({
        'onlineLimit': limit ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Super admin: put a product in "Hot" or "Deals" on the website home.
  Future<void> feature(Map<String, dynamic> store, Map<String, dynamic> item, {required String kind, double? dealPrice}) {
    final id = '${store['id']}_${item['id']}';
    return _db.doc('featured/$id').set({
      'kind': kind,
      'shopId': store['id'],
      'storeName': store['name'] ?? '',
      'itemId': item['id'],
      'name': item['name'] ?? '',
      'price': item['price'] ?? 0,
      if (dealPrice != null) 'dealPrice': dealPrice,
      'thumb': item['thumb'] ?? '',
      'currency': store['currency'] ?? 'Rs',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unfeature(String featuredId) => _db.doc('featured/$featuredId').delete();

  /// Super admin: replace the "Hot" list with [count] random products from
  /// published stores.
  Future<int> randomHot(int count) async {
    final stores = (await _db.collection('storefronts').where('published', isEqualTo: true).get())
        .docs
        .where((d) => d.data()['adminHidden'] != true)
        .toList();
    final pool = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final s in stores) {
      final items = await _db.collection('storefronts/${s.id}/items').get();
      for (final i in items.docs) {
        pool.add(({'id': s.id, ...s.data()}, {'id': i.id, ...i.data()}));
      }
    }
    pool.shuffle(Random());
    final batch = _db.batch();
    for (final old in (await _db.collection('featured').where('kind', isEqualTo: 'hot').get()).docs) {
      batch.delete(old.reference);
    }
    await batch.commit();
    final picked = pool.take(count).toList();
    for (final (store, item) in picked) {
      await feature(store, item, kind: 'hot');
    }
    return picked.length;
  }
}

int _ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : (v is num ? v.toInt() : 0);

/// Square 192px PNG logo (runs in an isolate).
Uint8List? _logo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final side = min(decoded.width, decoded.height);
  final square = img.copyCrop(decoded,
      x: (decoded.width - side) ~/ 2, y: (decoded.height - side) ~/ 2, width: side, height: side);
  return Uint8List.fromList(img.encodePng(img.copyResize(square, width: 192, height: 192)));
}

/// Resizes a photo to 320px and encodes it as JPEG (runs in an isolate).
Uint8List? _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width > decoded.height
      ? img.copyResize(decoded, width: min(320, decoded.width))
      : img.copyResize(decoded, height: min(320, decoded.height));
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}

extension<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
