import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/access.dart';
import '../core/app_state.dart';
import '../core/db.dart';
import '../core/firebase_config.dart';
import '../core/ids.dart';
import '../core/license.dart';
import '../core/packages.dart';
import 'profile_service.dart';
import 'notice_service.dart';
import 'store_service.dart';

/// Turns Firebase Auth errors into short English messages.
String authError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Email or password is wrong.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Sign in instead.';
      case 'weak-password':
        return 'Use a stronger password: at least 8 characters with letters and numbers.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'requires-recent-login':
        return 'Please sign in again and retry.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
  if (e is FirebaseException) return e.message ?? 'Server error (${e.code}).';
  if (e is StateError) return e.message;
  return '$e';
}

/// Accounts, the shop's online subscription, devices and the super admin data.
/// Everything here is optional: without Firebase config the app runs offline.
class CloudService extends ChangeNotifier {
  CloudService._();
  static final CloudService instance = CloudService._();

  bool ready = false;
  String? lastError;
  User? user;
  bool isAdmin = false;
  Map<String, dynamic> adminDoc = {};
  String? shopId;
  Map<String, dynamic>? shop;
  bool revokedNotice = false;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _shopSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  bool _deviceRegistered = false;

  bool get configured => FirebaseConfig.configured;

  void refresh() => notifyListeners();
  bool get signedIn => user != null;
  FirebaseFirestore get db => FirebaseFirestore.instance;
  FirebaseAuth get auth => FirebaseAuth.instance;

  String get _device => LicenseService.instance.deviceCode;

  GoogleSignIn get _google => GoogleSignIn(
        scopes: const ['email'],
        serverClientId: Platform.isAndroid && FirebaseConfig.webClientId.isNotEmpty ? FirebaseConfig.webClientId : null,
      );

  /// Cached branding and trusted keys, applied before Firebase is reachable.
  void loadCachedSettings() {
    final raw = Local.prefs.getString('cloud_settings');
    if (raw == null) return;
    try {
      _applySettings(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> init() async {
    loadCachedSettings();
    if (!configured || ready) return;
    try {
      await Firebase.initializeApp(options: FirebaseConfig.current);
      db.settings = const Settings(persistenceEnabled: true);
      ready = true;
      NoticeService.instance.start();
      AppState.onProfileChanged = _profileChanged;
      _settingsSub = db.doc('settings/app').snapshots().listen((s) {
        final d = s.data();
        if (d == null) return;
        Local.prefs.setString('cloud_settings', jsonEncode(_jsonSafe(d)));
        _applySettings(d);
        // Fresh from the server (not the offline cache): update checks may run.
        if (!s.metadata.isFromCache) settingsLive = true;
        notifyListeners();
      }, onError: (_) {});
      _authSub = auth.authStateChanges().listen(_onAuth, onError: (_) {});
    } catch (e) {
      lastError = '$e';
    }
    notifyListeners();
  }

  Map<String, dynamic> _jsonSafe(Map<String, dynamic> m) => m.map((k, v) {
        if (v is Timestamp) return MapEntry(k, v.millisecondsSinceEpoch);
        if (v is Map<String, dynamic>) return MapEntry(k, _jsonSafe(v));
        return MapEntry(k, v);
      });

  /// settings/app as last read (branding, online store settings).
  Map<String, dynamic> appSettings = {};

  /// settings/app was read from the server in this session.
  bool settingsLive = false;

  void _applySettings(Map<String, dynamic> d) {
    appSettings = d;
    final lic = LicenseService.instance;
    final footer = d['footer'] as String?;
    final phone = d['phone'] as String?;
    if (footer != null && footer.isNotEmpty) lic.footer = footer;
    if (phone != null && phone.isNotEmpty) lic.phone = phone;
    for (final k in ((d['trustedKeys'] as List?) ?? [])) {
      if (!LicenseKeys.trusted.contains('$k')) LicenseKeys.trusted.add('$k');
    }
    lic.refresh();
  }

  Future<void> _onAuth(User? u) async {
    user = u;
    if (u == null) {
      isAdmin = false;
      adminDoc = {};
      StoreService.instance.watchOrders();
      shop = null;
      shopId = null;
      await _shopSub?.cancel();
      _shopSub = null;
      notifyListeners();
      return;
    }
    await _openStoreFor(u);
    try {
      final a = await db.doc('admins/${u.uid}').get();
      isAdmin = a.exists && a.data()?['role'] == 'super';
      adminDoc = a.data() ?? {};
    } catch (_) {
      isAdmin = false;
    }
    try {
      final userDoc = await _ensureUserDoc(u);
      final id = (userDoc['shopId'] as String?) ?? AppState.instance.settings['shop_id'];
      if (id != null && id.isNotEmpty) await _link(id);
      await ensureShopLinked();
    } catch (e) {
      lastError = authError(e);
    }
    notifyListeners();
  }

  /// Reads admins/{uid} again (after the super admin document is created).
  Future<bool> reloadAdmin() async {
    final u = user;
    if (u == null) return false;
    try {
      final a = await db.doc('admins/${u.uid}').get(const GetOptions(source: Source.server));
      isAdmin = a.exists && a.data()?['role'] == 'super';
      adminDoc = a.data() ?? {};
    } catch (e) {
      lastError = authError(e);
    }
    notifyListeners();
    return isAdmin;
  }

  /// Each account has its own store on this phone: open it, or start a new
  /// one when the open store belongs to another account.
  Future<void> _openStoreFor(User u) async {
    final profiles = ProfileService.instance;
    final mine = profiles.byUid(u.uid);
    if (mine != null && mine.id != profiles.activeId) {
      await _shopSub?.cancel();
      _shopSub = null;
      shopId = null;
      shop = null;
      await profiles.switchTo(mine.id);
    } else if (mine == null && profiles.active.uid != null && profiles.active.uid != u.uid) {
      await _shopSub?.cancel();
      _shopSub = null;
      shopId = null;
      shop = null;
      await profiles.switchTo(await profiles.create(uid: u.uid, email: u.email));
    }
    await profiles.rememberActive(uid: u.uid, email: u.email);
    await profiles.setSignedOut(false);
  }

  Future<Map<String, dynamic>> _ensureUserDoc(User u, {String? name}) async {
    final ref = db.doc('users/${u.uid}');
    final snap = await ref.get();
    if (snap.exists) return snap.data() ?? {};
    final data = {
      'email': u.email ?? '',
      'name': name ?? u.displayName ?? (u.email ?? '').split('@').first,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
    return data;
  }

  // ----------------------------------------------------------------- auth

  Future<void> signUp({required String name, required String email, required String password}) async {
    final c = await auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    await c.user!.updateDisplayName(name.trim());
    await _ensureUserDoc(c.user!, name: name.trim());
    try {
      await c.user!.sendEmailVerification();
    } catch (_) {}
  }

  Future<void> signIn(String email, String password) =>
      auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signInWithGoogle() async {
    final acc = await _google.signIn();
    if (acc == null) throw StateError('Google sign-in was cancelled.');
    final a = await acc.authentication;
    await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken));
  }

  Future<void> resetPassword(String email) => auth.sendPasswordResetEmail(email: email.trim());

  bool get usesPassword => user?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// Asks the user to prove who they are again (PIN reset, password change).
  Future<void> reauthenticate({String? password}) async {
    final u = user;
    if (u == null) throw StateError('Sign in first.');
    if (usesPassword) {
      if (password == null || password.isEmpty) throw StateError('Enter your account password.');
      await u.reauthenticateWithCredential(EmailAuthProvider.credential(email: u.email!, password: password));
    } else {
      final acc = await _google.signIn();
      if (acc == null) throw StateError('Google sign-in was cancelled.');
      final a = await acc.authentication;
      await u.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken));
    }
  }

  Future<void> changePassword(String current, String next) async {
    await reauthenticate(password: current);
    await user!.updatePassword(next);
  }

  Future<void> sendVerification() async => user?.sendEmailVerification();

  /// Deletes the signed-in account: its online store, company record, user
  /// record and sign-in. Data saved on the phone is handled by the caller.
  Future<void> deleteAccount({String? password}) async {
    final u = user;
    if (u == null) throw StateError('Sign in first.');
    await reauthenticate(password: password);
    final id = shopId ?? (await db.doc('users/${u.uid}').get()).data()?['shopId'] as String?;
    if (id != null) {
      try {
        final items = await db.collection('storefronts/$id/items').get();
        for (final d in items.docs) {
          await d.reference.delete();
        }
        final store = db.doc('storefronts/$id');
        if ((await store.get()).exists) await store.delete();
      } catch (_) {}
      await _shopSub?.cancel();
      _shopSub = null;
      try {
        await db.doc('shops/$id').delete();
      } catch (_) {}
    }
    try {
      await db.doc('users/${u.uid}').delete();
    } catch (_) {}
    shopId = null;
    shop = null;
    Access.instance.setCloud(CloudPlan.fromShop(null));
    await u.delete();
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await auth.signOut();
  }

  // ----------------------------------------------------------------- shop

  Future<void> _link(String id) async {
    if (shopId == id && _shopSub != null) return;
    shopId = id;
    if (AppState.instance.settings['shop_id'] != id && AppState.instance.onboarded) {
      await AppState.instance.setSetting('shop_id', id);
    }
    await _shopSub?.cancel();
    _deviceRegistered = false;
    _shopSub = db.doc('shops/$id').snapshots().listen(_onShop, onError: (e) {
      lastError = authError(e);
      // Deleted by the super admin (or given to another owner): free plan.
      if (e is FirebaseException && e.code == 'permission-denied') {
        Access.instance.setCloud(CloudPlan.fromShop(null));
        _shopSub = null;
        shopId = null;
        notifyListeners();
      }
    });
  }

  Future<void> _onShop(DocumentSnapshot<Map<String, dynamic>> s) async {
    shop = s.data();
    if (shop == null) {
      // The super admin deleted this company: back to the free plan.
      if (s.exists == false && !s.metadata.isFromCache) {
        Access.instance.setCloud(CloudPlan.fromShop(null));
        await _shopSub?.cancel();
        _shopSub = null;
        shopId = null;
        notifyListeners();
      }
      return;
    }
    Access.instance.setCloud(CloudPlan.fromShop(shop));
    final devices = (shop!['devices'] as Map?) ?? {};
    final mine = devices[_device] as Map?;
    if (mine != null && mine['revoked'] == true) {
      await _revokedHere();
      return;
    }
    if (!_deviceRegistered) {
      _deviceRegistered = true;
      final store = StoreService.instance;
      store.watchOrders();
      unawaited(store.pushStats());
      unawaited(store.syncAll().catchError((_) {}));
      // Business details edited while offline or before this fix reach the shop record.
      if (AppState.instance.settings.containsKey('business_name')) _profileChanged();
      try {
        await db.doc('shops/$shopId').update({
          'devices.$_device.name': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim(),
          'devices.$_device.lastSeen': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    notifyListeners();
  }

  /// The owner removed this phone (lost or stolen): erase local data and sign out.
  Future<void> _revokedHere() async {
    await _shopSub?.cancel();
    _shopSub = null;
    await Db.instance.wipe();
    await Local.prefs.remove(Local.k('cloud_plan'));
    Access.instance.setCloud(CloudPlan());
    revokedNotice = true;
    AppState.instance.lock();
    await AppState.instance.load();
    await LicenseService.instance.load();
    await signOut();
    notifyListeners();
  }

  /// The signed-in user's existing shop, if any (for a new phone).
  Future<Map<String, dynamic>?> existingShop() async {
    final u = user;
    if (u == null) return null;
    final d = (await db.doc('users/${u.uid}').get()).data();
    final id = d?['shopId'] as String?;
    if (id == null || id.isEmpty) return null;
    final s = await db.doc('shops/$id').get();
    return s.exists ? {'id': id, ...?s.data()} : null;
  }

  /// Links the local business to the account, creating the online shop on first use.
  Future<void> ensureShopLinked() async {
    final u = user;
    final app = AppState.instance;
    if (u == null || !app.onboarded) return;
    if (shopId != null) {
      if (app.settings['shop_id'] != shopId) await app.setSetting('shop_id', shopId!);
      return;
    }
    final existing = await existingShop();
    if (existing != null) {
      await _link(existing['id'] as String);
      return;
    }
    final pending = await _pendingCompanyForEmail();
    if (pending != null) {
      await _claim(pending);
      return;
    }
    final ref = db.collection('shops').doc();
    await ref.set({
      'ownerUid': u.uid,
      'ownerEmail': u.email ?? '',
      'name': app.businessName,
      'category': app.businessType?.name ?? '',
      'phone': app.settings['business_phone'] ?? '',
      'currency': app.settings['currency_symbol'] ?? '',
      'plan': 'free',
      'status': 'active',
      'devices': {},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await db.doc('users/${u.uid}').update({'shopId': ref.id, 'updatedAt': FieldValue.serverTimestamp()});
    await _link(ref.id);
  }

  Future<void> updateShopProfile() async {
    final id = shopId;
    if (id == null || !signedIn) return;
    final app = AppState.instance;
    final fields = {
      'name': app.businessName,
      'phone': app.settings['business_phone'] ?? '',
      if (app.businessType != null) 'category': app.businessType!.name,
    };
    final current = shop ?? {};
    if (fields.entries.every((e) => '${current[e.key] ?? ''}' == '${e.value}')) {
      await StoreService.instance.refreshCard();
      return;
    }
    await db.doc('shops/$id').update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
    // The website card shows the same name, phone and address.
    await StoreService.instance.refreshCard();
  }

  Timer? _profileTimer;

  /// Business details changed in Settings: copy them online a moment later.
  void _profileChanged() {
    _profileTimer?.cancel();
    _profileTimer = Timer(const Duration(seconds: 2), () => updateShopProfile().catchError((_) {}));
  }

  Map<String, Map<String, dynamic>> get devices {
    final d = (shop?['devices'] as Map?) ?? {};
    return d.map((k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)));
  }

  Future<void> setDeviceRevoked(String code, bool revoked) async {
    final id = shopId;
    if (id == null) throw StateError('This phone is not linked to an online shop.');
    if (code == _device && revoked) throw StateError('You cannot remove the phone you are using.');
    await db.doc('shops/$id').update({'devices.$code.revoked': revoked, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> requestUpgrade(Package p, {String note = ''}) async {
    final u = user;
    final id = shopId;
    if (u == null || id == null) throw StateError('Sign in to request an upgrade.');
    await db.collection('requests').add({
      'ownerUid': u.uid,
      'ownerEmail': u.email ?? '',
      'shopId': id,
      'shopName': AppState.instance.businessName,
      'packageId': p.id,
      'packageName': p.name,
      'price': p.price,
      'note': note,
      'device': _device,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Package>> packages({bool includeInactive = false}) => db.collection('packages').snapshots().map((q) {
        final list = q.docs.map((d) => Package.fromMap(d.id, d.data())).where((p) => includeInactive || p.active).toList();
        list.sort((a, b) => a.sort.compareTo(b.sort));
        return list;
      });

  // ----------------------------------------------------------------- super admin

  Stream<List<Map<String, dynamic>>> shops() => db
      .collection('shops')
      .orderBy('createdAt', descending: true)
      .limit(1000)
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> requests() => db
      .collection('requests')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> subscriptionsSince(int fromMs) => db
      .collection('subscriptions')
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(fromMs))
      .snapshots()
      .map((q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> shopSubscriptions(String shopId) => db
      .collection('subscriptions')
      .where('shopId', isEqualTo: shopId)
      .snapshots()
      .map((q) {
        final l = q.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        int ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : 0;
        l.sort((a, b) => ms(b['createdAt']).compareTo(ms(a['createdAt'])));
        return l;
      });

  /// New expiry: lifetime stays lifetime; otherwise extends from the later of
  /// now or the current expiry, so renewing early never loses days.
  static int newExpiry({required int now, required int currentExpiry, required bool currentActive, required int days}) {
    if (days == 0) return 0;
    final base = (currentActive && currentExpiry > now) ? currentExpiry : now;
    return base + days * 86400000;
  }

  Future<void> assignSubscription(Map<String, dynamic> shopDoc, Package p, {double? amount, String note = ''}) async {
    final id = shopDoc['id'] as String;
    final now = nowMs();
    final current = CloudPlan.fromShop(shopDoc);
    final expires = newExpiry(
      now: now,
      currentExpiry: current.expiresAt,
      currentActive: current.activeAt(now) && current.packageId == p.id,
      days: p.days,
    );
    final batch = db.batch();
    batch.update(db.doc('shops/$id'), {
      'plan': p.id,
      'planName': p.name,
      'features': p.features,
      'adFree': p.adFree,
      'maxProducts': p.maxProducts,
      'onlineProducts': p.onlineProducts,
      'expiresAt': expires,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('subscriptions').doc(), {
      'shopId': id,
      'shopName': shopDoc['name'] ?? '',
      'ownerUid': shopDoc['ownerUid'] ?? '',
      'packageId': p.id,
      'packageName': p.name,
      'amount': amount ?? p.amount,
      'days': p.days,
      'expiresAt': expires,
      'note': note,
      'by': user?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _storefrontAdmin(id, {'paidUntil': expires});
  }

  /// Admin change on a shop's online store, if the shop has one.
  Future<void> _storefrontAdmin(String shopId, Map<String, dynamic> fields) async {
    final ref = db.doc('storefronts/$shopId');
    try {
      if ((await ref.get()).exists) await ref.update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // ----------------------------------------------------------- companies

  /// Super admin: creates a company (shop) for an owner who has not signed in
  /// yet. The owner joins it with the company code (the document id), or
  /// automatically when they sign in with Google using [ownerEmail].
  Future<String> createCompany({
    required String name,
    required String ownerEmail,
    String ownerName = '',
    String phone = '',
    String city = '',
    String category = '',
    Package? package,
    double? amount,
  }) async {
    final ref = db.collection('shops').doc();
    final data = <String, dynamic>{
      'ownerUid': '',
      'ownerEmail': ownerEmail.trim().toLowerCase(),
      'ownerName': ownerName.trim(),
      'name': name.trim(),
      'category': category,
      'phone': phone.trim(),
      'city': city.trim(),
      'currency': 'Rs',
      'plan': 'free',
      'status': 'active',
      'devices': <String, dynamic>{},
      'createdBy': user?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
    if (package != null) {
      await assignSubscription({'id': ref.id, ...data}, package, amount: amount, note: 'New company');
    }
    return ref.id;
  }

  /// Super admin: creates the owner's login (email + password) and the
  /// company in one step, so the owner can simply sign in on their phone.
  /// Uses a second Firebase app so the super admin stays signed in.
  /// Returns the company id.
  Future<String> createCompanyWithLogin({
    required String name,
    required String ownerEmail,
    required String password,
    String ownerName = '',
    String phone = '',
    String city = '',
    String category = '',
    Package? package,
    double? amount,
  }) async {
    const appName = 'bizpos-owner-setup';
    FirebaseApp second;
    try {
      second = Firebase.app(appName);
    } catch (_) {
      second = await Firebase.initializeApp(name: appName, options: Firebase.app().options);
    }
    final secondAuth = FirebaseAuth.instanceFor(app: second);
    final email = ownerEmail.trim().toLowerCase();
    final cred = await secondAuth.createUserWithEmailAndPassword(email: email, password: password);
    final owner = cred.user!;
    try {
      if (ownerName.trim().isNotEmpty) await owner.updateDisplayName(ownerName.trim());
      final shopRef = db.collection('shops').doc();
      final data = <String, dynamic>{
        'ownerUid': owner.uid,
        'ownerEmail': email,
        'ownerName': ownerName.trim(),
        'name': name.trim(),
        'category': category,
        'phone': phone.trim(),
        'city': city.trim(),
        'currency': 'Rs',
        'plan': 'free',
        'status': 'active',
        'devices': <String, dynamic>{},
        'createdBy': user?.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await shopRef.set(data);
      // The owner's own users document is written as the owner (rules allow only that).
      await FirebaseFirestore.instanceFor(app: second).doc('users/${owner.uid}').set({
        'email': email,
        'name': ownerName.trim().isEmpty ? email.split('@').first : ownerName.trim(),
        'shopId': shopRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (package != null) {
        await assignSubscription({'id': shopRef.id, ...data}, package, amount: amount, note: 'New company');
      }
      return shopRef.id;
    } finally {
      await secondAuth.signOut();
    }
  }

  /// Super admin: deletes a company. Its phones drop to the free plan.
  Future<void> deleteCompany(String shopId) async {
    final snap = await db.doc('shops/$shopId').get();
    final ownerUid = '${snap.data()?['ownerUid'] ?? ''}';
    final batch = db.batch();
    batch.delete(db.doc('shops/$shopId'));
    batch.delete(db.doc('storefronts/$shopId'));
    if (ownerUid.isNotEmpty) {
      batch.set(db.doc('users/$ownerUid'), {'shopId': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// A company the super admin created for this verified email, not yet claimed.
  Future<String?> _pendingCompanyForEmail() async {
    final u = user;
    final email = (u?.email ?? '').toLowerCase();
    if (u == null || email.isEmpty || !u.emailVerified) return null;
    try {
      final q = await db
          .collection('shops')
          .where('ownerUid', isEqualTo: '')
          .where('ownerEmail', isEqualTo: email)
          .limit(1)
          .get();
      return q.docs.isEmpty ? null : q.docs.first.id;
    } catch (_) {
      return null;
    }
  }

  /// Joins the company with [code] (given by the super admin) and links this
  /// phone to it.
  Future<String> joinCompany(String code) async {
    final u = user;
    if (u == null) throw StateError('Sign in first.');
    final id = code.trim();
    if (id.isEmpty) throw StateError('Enter the company code.');
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await db.doc('shops/$id').get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        throw StateError('No company has this code, or it already has an owner.');
      }
      rethrow;
    }
    final d = snap.data();
    if (!snap.exists || d == null) throw StateError('No company has this code.');
    if ((d['ownerUid'] ?? '') != '' && d['ownerUid'] != u.uid) throw StateError('This company already has an owner.');
    await _claim(id);
    return '${d['name'] ?? ''}';
  }

  Future<void> _claim(String id) async {
    final u = user!;
    await db.doc('shops/$id').update({
      'ownerUid': u.uid,
      'ownerEmail': (u.email ?? '').toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await db.doc('users/${u.uid}').set({'shopId': id, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await _shopSub?.cancel();
    _shopSub = null;
    shopId = null;
    await _link(id);
    notifyListeners();
  }

  Future<void> setFree(String shopId) async {
    await _setFree(shopId);
    await _storefrontAdmin(shopId, {'published': false});
  }

  Future<void> _setFree(String shopId) => db.doc('shops/$shopId').update({
        'plan': 'free',
        'planName': 'Free',
        'features': <String>[],
        'adFree': false,
        'maxProducts': FieldValue.delete(),
        'onlineProducts': FieldValue.delete(),
        'expiresAt': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setBlocked(String shopId, bool blocked) async {
    await db.doc('shops/$shopId').update({'status': blocked ? 'blocked' : 'active', 'updatedAt': FieldValue.serverTimestamp()});
    await _storefrontAdmin(shopId, {'adminHidden': blocked});
  }

  /// Saves a package and gives the shops already on it the new limits and features.
  Future<int> savePackage(Package p) async {
    await db.doc('packages/${p.id}').set(p.toMap());
    final shops = await db.collection('shops').where('plan', isEqualTo: p.id).get();
    var batch = db.batch();
    var n = 0;
    for (final d in shops.docs) {
      batch.update(d.reference, {
        'planName': p.name,
        'features': p.features,
        'adFree': p.adFree,
        'maxProducts': p.maxProducts,
        'onlineProducts': p.onlineProducts,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (++n % 400 == 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    return n;
  }

  Future<void> deletePackage(String id) => db.doc('packages/$id').delete();

  Future<void> seedPackages() async {
    final batch = db.batch();
    for (final p in Package.defaults()) {
      batch.set(db.doc('packages/${p.id}'), p.toMap());
    }
    await batch.commit();
  }

  // ------------------------------------------------- website import checks

  /// "https://www.Tajoree.com/shop" → "tajoree.com"
  static String siteHost(String site) {
    var s = site.trim().toLowerCase();
    if (s.isEmpty) return '';
    if (!s.startsWith('http')) s = 'https://$s';
    var h = Uri.tryParse(s)?.host ?? '';
    if (h.startsWith('www.')) h = h.substring(4);
    return h;
  }

  /// Websites the super admin confirmed belong to this shop (shops/{id}.importSites).
  List<String> get importSites => ((shop?['importSites'] as List?) ?? []).map((e) => '$e').toList();

  bool importAllowed(String site) => isAdmin || importSites.contains(siteHost(site));

  /// The owner asks the super admin to confirm that [site] is theirs.
  /// Returns false when a request for it is already waiting.
  Future<bool> requestImport(String site) async {
    final u = user;
    final id = shopId;
    if (u == null || id == null) throw StateError('Sign in to your BizPOS account first.');
    final host = siteHost(site);
    if (host.isEmpty) throw StateError('Type your website address.');
    final mine = await db.collection('requests').where('ownerUid', isEqualTo: u.uid).get();
    final waiting = mine.docs.any((d) => d.data()['type'] == 'import' && d.data()['site'] == host && d.data()['status'] == 'pending');
    if (waiting) return false;
    await db.collection('requests').add({
      'type': 'import',
      'site': host,
      'ownerUid': u.uid,
      'ownerEmail': u.email ?? '',
      'shopId': id,
      'shopName': AppState.instance.businessName,
      'packageName': 'Website import',
      'price': host,
      'device': _device,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Whether a request to import from [site] is waiting for the super admin.
  Future<bool> importPending(String site) async {
    final u = user;
    if (u == null) return false;
    final host = siteHost(site);
    final mine = await db.collection('requests').where('ownerUid', isEqualTo: u.uid).get();
    return mine.docs.any((d) => d.data()['type'] == 'import' && d.data()['site'] == host && d.data()['status'] == 'pending');
  }

  /// Super admin: the website is the shop's own; its products may be imported.
  Future<void> approveImport(Map<String, dynamic> request) async {
    final batch = db.batch();
    batch.update(db.doc('shops/${request['shopId']}'), {
      'importSites': FieldValue.arrayUnion([request['site']]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(db.doc('requests/${request['id']}'), {'status': 'approved', 'resolvedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> removeImportSite(String shopId, String host) => db.doc('shops/$shopId').update({
        'importSites': FieldValue.arrayRemove([host]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> resolveRequest(String id, String status) =>
      db.doc('requests/$id').update({'status': status, 'resolvedAt': FieldValue.serverTimestamp()});

  Future<void> saveBranding({required String footer, required String phone}) =>
      db.doc('settings/app').set({'footer': footer, 'phone': phone}, SetOptions(merge: true));

  Future<void> addTrustedKey(String publicKey) =>
      db.doc('settings/app').set({'trustedKeys': FieldValue.arrayUnion([publicKey])}, SetOptions(merge: true));

  Future<void> setAdminTotp(String? secret) async {
    final u = user;
    if (u == null || !isAdmin) throw StateError('Super admin only.');
    await db.doc('admins/${u.uid}').update({'totpEnabled': secret != null, 'totpSecret': secret});
    adminDoc = {...adminDoc, 'totpEnabled': secret != null, 'totpSecret': secret};
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _shopSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }
}
