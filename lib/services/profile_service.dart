import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/access.dart';
import '../core/app_state.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../core/license.dart';

/// One store kept on this phone: its own database file and settings.
class StoreProfile {
  StoreProfile({required this.id, this.name = '', this.uid, this.email, this.updatedAt = 0});

  final String id;
  String name;

  /// BizPOS account that owns the store (null for an offline store).
  String? uid;
  String? email;
  int updatedAt;

  factory StoreProfile.fromJson(Map<String, dynamic> m) => StoreProfile(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        uid: m['uid'] as String?,
        email: m['email'] as String?,
        updatedAt: ((m['updatedAt'] ?? 0) as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'uid': uid, 'email': email, 'updatedAt': updatedAt};
}

/// Several stores on one phone. Each BizPOS account opens its own store;
/// signing out keeps the data, and signing in with another account opens (or
/// creates) that account's store.
class ProfileService extends ChangeNotifier {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  static const defaultId = 'default';
  static const _listKey = 'store_profiles';
  static const _activeKey = 'store_profile_active';

  List<StoreProfile> profiles = [];
  String activeId = defaultId;

  StoreProfile get active => profiles.firstWhere((p) => p.id == activeId, orElse: () => StoreProfile(id: activeId));

  static String fileFor(String id) => id == defaultId ? 'bizpos.db' : 'bizpos_$id.db';

  /// Tag added to this store's Google Drive backup file names.
  String get driveTag => activeId == defaultId ? '' : 'u${active.uid ?? activeId}-';

  /// Reads the profiles and points the database at the active store.
  /// Call before Db.instance.init().
  Future<void> load() async {
    final prefs = Local.prefs;
    final raw = prefs.getString(_listKey);
    profiles = raw == null
        ? []
        : (jsonDecode(raw) as List).map((e) => StoreProfile.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    if (profiles.every((p) => p.id != defaultId)) profiles.insert(0, StoreProfile(id: defaultId));
    activeId = prefs.getString(_activeKey) ?? defaultId;
    if (profiles.every((p) => p.id != activeId)) activeId = defaultId;
    Local.scope = activeId == defaultId ? '' : activeId;
    Db.fileName = fileFor(activeId);
  }

  Future<void> _save() async {
    await Local.prefs.setString(_listKey, jsonEncode(profiles.map((p) => p.toJson()).toList()));
    await Local.prefs.setString(_activeKey, activeId);
    notifyListeners();
  }

  StoreProfile? byUid(String uid) {
    for (final p in profiles) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  /// Stores on this phone other than the open one, newest first.
  List<StoreProfile> get others =>
      profiles.where((p) => p.id != activeId && (p.name.isNotEmpty || p.uid != null)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> rememberActive({String? uid, String? email}) async {
    final p = active;
    if (uid != null) p.uid = uid;
    if (email != null) p.email = email;
    p.name = AppState.instance.businessName;
    p.updatedAt = nowMs();
    if (profiles.every((x) => x.id != p.id)) profiles.add(p);
    await _save();
  }

  /// Opens another store's data on this phone.
  Future<void> switchTo(String id) async {
    if (id == activeId) return;
    await rememberActive();
    activeId = id;
    Local.scope = id == defaultId ? '' : id;
    await Db.instance.reopen(fileFor(id));
    await AppState.instance.load();
    AppState.instance.lock();
    await LicenseService.instance.load();
    Access.instance.load();
    await _save();
  }

  /// A new, empty store on this phone.
  Future<String> create({String? uid, String? email}) async {
    final p = StoreProfile(id: newId().substring(0, 8), uid: uid, email: email, updatedAt: nowMs());
    profiles.add(p);
    await _save();
    return p.id;
  }

  /// Signed out on this phone: the welcome screen shows until someone signs in.
  bool get signedOut => Local.prefs.getBool(Local.k('signed_out')) ?? false;

  Future<void> setSignedOut(bool v) async {
    await Local.prefs.setBool(Local.k('signed_out'), v);
    notifyListeners();
  }
}
