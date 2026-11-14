import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/db.dart';
import '../core/ids.dart';
import '../core/packages.dart';
import 'alert_service.dart';
import 'cloud_service.dart';
import 'product_service.dart';
import 'store_service.dart';

/// Announcements and offers from the super admin.
///
/// announcements/{id}: title, message, kind (info, update, offer, warning),
///   audience (all, shops, shoppers), startAt, endAt (ms, 0 = no end), active, link.
/// offers/{id}: title, message, packageId, days, minProducts, startAt, endAt, active.
/// A shop claims an offer once; offerClaims/{shopId}_{offerId} records it.
class NoticeService extends ChangeNotifier {
  NoticeService._();
  static final NoticeService instance = NoticeService._();

  static const kinds = ['info', 'update', 'offer', 'warning'];
  static const audiences = ['all', 'shops', 'shoppers'];

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool get _ready => CloudService.instance.configured && Firebase.apps.isNotEmpty;

  List<Map<String, dynamic>> _announcements = const [];
  List<Map<String, dynamic>> _offers = const [];
  StreamSubscription? _aSub;
  StreamSubscription? _oSub;

  static bool liveAt(Map<String, dynamic> m, int now) {
    if (m['active'] != true) return false;
    final start = ((m['startAt'] ?? 0) as num).toInt();
    final end = ((m['endAt'] ?? 0) as num).toInt();
    return start <= now && (end == 0 || end > now);
  }

  /// Announcements for shop apps that are live and not dismissed on this phone.
  List<Map<String, dynamic>> get announcements {
    final now = nowMs();
    final dismissed = Local.prefs.getStringList('dismissed_notices') ?? const [];
    return _announcements
        .where((a) => liveAt(a, now) && a['audience'] != 'shoppers' && !dismissed.contains(a['id']))
        .toList();
  }

  /// Offers this shop can still claim.
  List<Map<String, dynamic>> get offers => _offers.where((o) => liveAt(o, nowMs())).toList();

  void start() {
    if (!_ready || _aSub != null) return;
    _aSub = _db.collection('announcements').where('active', isEqualTo: true).snapshots().listen((q) {
      _announcements = q.docs.map((d) => {'id': d.id, ...d.data()}).toList()
        ..sort((a, b) => ((b['startAt'] ?? 0) as num).compareTo((a['startAt'] ?? 0) as num));
      _alertNew();
      notifyListeners();
    }, onError: (_) {});
    _oSub = _db.collection('offers').where('active', isEqualTo: true).snapshots().listen((q) {
      _offers = q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      notifyListeners();
    }, onError: (_) {});
  }

  /// A phone notification the first time this phone sees an announcement.
  void _alertNew() {
    final seen = Local.prefs.getStringList('seen_notices') ?? <String>[];
    var changed = false;
    for (final a in announcements) {
      final id = a['id'] as String;
      if (seen.contains(id)) continue;
      seen.add(id);
      changed = true;
      AlertService.notify(7000 + id.hashCode % 1000, '${a['title'] ?? 'BizPOS'}', '${a['message'] ?? ''}');
    }
    if (changed) Local.prefs.setStringList('seen_notices', seen.length > 200 ? seen.sublist(seen.length - 200) : seen);
  }

  Future<void> dismiss(String id) async {
    final l = Local.prefs.getStringList('dismissed_notices') ?? <String>[];
    if (!l.contains(id)) l.add(id);
    await Local.prefs.setStringList('dismissed_notices', l);
    notifyListeners();
  }

  // ---------------------------------------------------------------- offers

  Future<bool> claimed(String offerId) async {
    final shopId = CloudService.instance.shopId;
    if (shopId == null) return false;
    try {
      return (await _db.doc('offerClaims/${shopId}_$offerId').get()).exists;
    } catch (_) {
      return false;
    }
  }

  /// Claims [offer]: the shop gets the offer's package for its days.
  /// The shop must be on the free plan (or expired) and have enough products.
  Future<void> claim(Map<String, dynamic> offer) async {
    final cloud = CloudService.instance;
    final shopId = cloud.shopId;
    final user = cloud.user;
    if (shopId == null || user == null) throw StateError('Sign in to your BizPOS account first.');
    final now = nowMs();
    final plan = CloudPlan.fromShop(cloud.shop);
    if (plan.packageId != 'free' && plan.activeAt(now)) {
      throw StateError('Offers are for shops on the free plan. Your plan is still active.');
    }
    final need = ((offer['minProducts'] ?? 0) as num).toInt();
    final have = await ProductService.count();
    if (have < need) throw StateError('Add $need products to get this offer. You have $have.');
    // The rules check the product count saved on the shop, so send it first.
    await StoreService.instance.pushStats(force: true);
    final pkgSnap = await _db.doc('packages/${offer['packageId']}').get();
    if (!pkgSnap.exists) throw StateError('This offer is not available right now.');
    final p = Package.fromMap(pkgSnap.id, pkgSnap.data()!);
    final days = ((offer['days'] ?? 0) as num).toInt();
    final batch = _db.batch();
    batch.update(_db.doc('shops/$shopId'), {
      'plan': p.id,
      'planName': p.name,
      'features': p.features,
      'adFree': p.adFree,
      'maxProducts': p.maxProducts,
      'onlineProducts': p.onlineProducts,
      'expiresAt': now + days * 86400000,
      'offer': offer['id'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.doc('offerClaims/${shopId}_${offer['id']}'), {
      'shopId': shopId,
      'offerId': offer['id'],
      'ownerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await StoreService.instance.refreshCard();
  }

  // ----------------------------------------------------------- super admin

  Stream<List<Map<String, dynamic>>> all(String collection) => _db.collection(collection).snapshots().map((q) {
        final l = q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        l.sort((a, b) => ((b['startAt'] ?? 0) as num).compareTo((a['startAt'] ?? 0) as num));
        return l;
      });

  Future<void> save(String collection, String? id, Map<String, dynamic> data) async {
    final ref = id == null ? _db.collection(collection).doc() : _db.doc('$collection/$id');
    await ref.set({
      ...data,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> remove(String collection, String id) => _db.doc('$collection/$id').delete();

  Future<int> claimCount(String offerId) async {
    final q = await _db.collection('offerClaims').where('offerId', isEqualTo: offerId).count().get();
    return q.count ?? 0;
  }
}
