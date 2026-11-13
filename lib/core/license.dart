import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'db.dart';
import 'ids.dart';
import 'packages.dart';
import 'totp.dart';

/// Super admin keys.
///
/// The super admin's Ed25519 key pair is derived from a master password, so no
/// secret is stored in the app or the repository. The app only contains the
/// public key and accepts codes signed by the matching private key.
/// To change the password run `python3 tool/admin_key.py "<new password>"` and
/// add the printed public key to [trusted].
class LicenseKeys {
  static const salt = 'bizpos-super-admin-v1';
  static const iterations = 60000;

  /// Public keys whose signatures the app accepts (base64url, no padding).
  static final List<String> trusted = ['j8Zhhemvtig034SFCkT0zNFe87wSeQwU7Rw29CxHGww'];

  static Future<SuperAdminKey> derive(String password) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final secret = await pbkdf2.deriveKeyFromPassword(password: password, nonce: utf8.encode(salt));
    final seed = await secret.extractBytes();
    final kp = await Ed25519().newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    final totpKey = crypto.Hmac(crypto.sha256, seed).convert(utf8.encode('totp')).bytes.sublist(0, 20);
    return SuperAdminKey(kp, b64(pub.bytes), Totp.base32Encode(totpKey));
  }

  static String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  static List<int> unb64(String s) => base64Url.decode(base64Url.normalize(s));
}

class SuperAdminKey {
  SuperAdminKey(this.keyPair, this.publicKey, this.totpSecret);
  final SimpleKeyPair keyPair;
  final String publicKey;
  final String totpSecret;

  bool get isTrusted => LicenseKeys.trusted.contains(publicKey);
}

/// Contents of an activation, upgrade or credit code.
class LicensePayload {
  LicensePayload({
    required this.type,
    required this.device,
    required this.nonce,
    required this.issued,
    this.storeId,
    this.storeName,
    this.plan,
    this.features = const [],
    this.expires = 0,
    this.credits = 0,
    this.footer,
    this.phone,
  });

  /// act (activation or upgrade) | cred (credits)
  final String type;

  /// Device code the code is valid for.
  final String device;
  final String nonce;
  final int issued;
  final String? storeId;
  final String? storeName;
  final String? plan;
  final List<String> features;

  /// Expiry in milliseconds since epoch; 0 means lifetime.
  final int expires;
  final int credits;
  final String? footer;
  final String? phone;

  Map<String, Object?> toJson() => {
        'v': 1,
        't': type,
        'd': device,
        'n': nonce,
        'i': issued,
        if (storeId != null) 's': storeId,
        if (storeName != null) 'sn': storeName,
        if (plan != null) 'p': plan,
        if (features.isNotEmpty) 'f': features,
        'e': expires,
        if (credits != 0) 'c': credits,
        if (footer != null || phone != null) 'b': {if (footer != null) 'f': footer, if (phone != null) 'p': phone},
      };

  factory LicensePayload.fromJson(Map<String, dynamic> j) {
    final b = j['b'] as Map<String, dynamic>?;
    return LicensePayload(
      type: j['t'] as String,
      device: j['d'] as String,
      nonce: j['n'] as String,
      issued: (j['i'] as num).toInt(),
      storeId: j['s'] as String?,
      storeName: j['sn'] as String?,
      plan: j['p'] as String?,
      features: ((j['f'] as List?) ?? []).map((e) => e.toString()).toList(),
      expires: ((j['e'] as num?) ?? 0).toInt(),
      credits: ((j['c'] as num?) ?? 0).toInt(),
      footer: b?['f'] as String?,
      phone: b?['p'] as String?,
    );
  }

  bool activeAt(int nowMs) => expires == 0 || expires > nowMs;
}

/// Encodes and verifies codes: "BZ1.<payload>.<signature>".
class LicenseCodec {
  static const prefix = 'BZ1.';

  static Future<String> encode(LicensePayload p, SuperAdminKey key) async {
    final body = LicenseKeys.b64(utf8.encode(jsonEncode(p.toJson())));
    final sig = await Ed25519().sign(utf8.encode('$prefix$body'), keyPair: key.keyPair);
    return '$prefix$body.${LicenseKeys.b64(sig.bytes)}';
  }

  /// Returns the payload when the code is genuine, otherwise null.
  static Future<LicensePayload?> decode(String code) async {
    final c = code.trim().replaceAll(RegExp(r'\s'), '');
    if (!c.startsWith(prefix)) return null;
    final parts = c.substring(prefix.length).split('.');
    if (parts.length != 2) return null;
    try {
      final message = utf8.encode('$prefix${parts[0]}');
      final sigBytes = LicenseKeys.unb64(parts[1]);
      var ok = false;
      for (final pk in LicenseKeys.trusted) {
        final sig = Signature(sigBytes, publicKey: SimplePublicKey(LicenseKeys.unb64(pk), type: KeyPairType.ed25519));
        if (await Ed25519().verify(message, signature: sig)) {
          ok = true;
          break;
        }
      }
      if (!ok) return null;
      final json = jsonDecode(utf8.decode(LicenseKeys.unb64(parts[0])));
      return LicensePayload.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// What this device is allowed to do, worked out from the signed codes it holds.
class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  bool loaded = false;
  bool everActivated = false;
  bool active = false;
  String planKey = 'basic';
  Set<String> features = {};
  int planExpires = 0;
  String? storeId;
  String? storeName;
  double credits = 0;
  String footer = Vendor.defaultFooter;
  String phone = Vendor.defaultPhone;

  /// Short code that identifies this phone (shown to the super admin).
  String get deviceCode => Db.instance.deviceId.replaceAll('-', '').substring(0, 8).toUpperCase();
  String get deviceCodePretty => '${deviceCode.substring(0, 4)}-${deviceCode.substring(4)}';

  Plan get plan => Plans.byKey(planKey);
  bool has(String feature) => active && features.contains(feature);
  bool get canSell => active;
  int get daysLeft => planExpires == 0 ? -1 : ((planExpires - now()) / 86400000).ceil();

  /// Clock that never goes backwards, so setting the phone date back does not
  /// extend a trial.
  int now() {
    final n = nowMs();
    final seen = Local.prefs.getInt('max_seen_time') ?? 0;
    if (n > seen) {
      Local.prefs.setInt('max_seen_time', n);
      return n;
    }
    return seen;
  }

  static const _rank = {'trial': 1, 'basic': 2, 'pro': 3};

  Future<void> load() async {
    final rows = await Db.instance.s.q("SELECT code FROM licenses WHERE deleted_at IS NULL AND kind = 'act'");
    final mine = <LicensePayload>[];
    for (final r in rows) {
      final p = await LicenseCodec.decode(r['code'] as String);
      if (p != null && p.type == 'act' && p.device == deviceCode) mine.add(p);
    }
    mine.sort((a, b) => a.issued.compareTo(b.issued));
    final t = now();
    final current = mine.where((p) => p.activeAt(t)).toList();

    everActivated = mine.isNotEmpty;
    active = current.isNotEmpty;
    features = {};
    LicensePayload? best;
    int score(LicensePayload p) => p.expires == 0 ? 1 << 62 : p.expires;
    for (final p in current) {
      features.addAll(p.features);
      features.addAll(Plans.byKey(p.plan).features);
      final rank = _rank[p.plan] ?? 0;
      final bestRank = best == null ? -1 : (_rank[best.plan] ?? 0);
      if (best == null || rank > bestRank || (rank == bestRank && score(p) > score(best))) best = p;
    }
    if (best != null) {
      planKey = best.plan ?? 'basic';
      planExpires = best.expires;
    }
    if (current.isEmpty && mine.isNotEmpty) {
      planKey = mine.last.plan ?? 'basic';
      planExpires = mine.last.expires;
    }
    final withId = mine.where((p) => p.storeId != null).toList();
    if (withId.isNotEmpty) storeId = withId.last.storeId;
    final named = mine.where((p) => p.storeName != null).toList();
    if (named.isNotEmpty) storeName = named.last.storeName;
    final branded = mine.where((p) => p.footer != null || p.phone != null).toList();
    if (branded.isNotEmpty) {
      footer = branded.last.footer ?? footer;
      phone = branded.last.phone ?? phone;
    }
    credits = await Db.instance.s.scalar('SELECT COALESCE(SUM(amount), 0) FROM credit_ledger WHERE deleted_at IS NULL');
    loaded = true;
    notifyListeners();
  }

  /// Tells listeners that branding or trusted keys changed.
  void refresh() => notifyListeners();

  /// Applies an activation, upgrade or credit code. Returns a short summary.
  Future<String> apply(String code) async {
    final p = await LicenseCodec.decode(code);
    if (p == null) throw StateError('This code is not valid. Check that it was copied completely.');
    if (p.device != deviceCode) {
      throw StateError('This code is for another phone (${p.device}). This phone is $deviceCodePretty.');
    }
    final s = Db.instance.s;
    final exists = await s.byId('licenses', p.nonce);
    String summary;
    if (p.type == 'cred') {
      if (exists != null) throw StateError('This credit code was already used.');
      await s.insert('licenses', {'id': p.nonce, 'code': code.trim(), 'kind': 'cred', 'device': p.device});
      await s.insert('credit_ledger', {'id': 'c-${p.nonce}', 'amount': p.credits, 'reason': 'Credit code', 'ref': p.nonce});
      summary = '${p.credits} credits added';
    } else {
      if (exists == null) {
        await s.insert('licenses', {'id': p.nonce, 'code': code.trim(), 'kind': 'act', 'device': p.device});
        if (p.credits > 0 && await s.byId('credit_ledger', 'c-${p.nonce}') == null) {
          await s.insert('credit_ledger', {'id': 'c-${p.nonce}', 'amount': p.credits, 'reason': 'Plan credits', 'ref': p.nonce});
        }
      }
      summary = '${Plans.byKey(p.plan).name} activated'
          '${p.expires == 0 ? '' : ' until ${DateTime.fromMillisecondsSinceEpoch(p.expires).toString().substring(0, 10)}'}';
    }
    await load();
    return summary;
  }

  /// Spends credits. Throws when there are not enough.
  Future<void> spend(double amount, String reason) async {
    await load();
    if (credits < amount) throw StateError('Not enough credits. Watch an ad or buy credits.');
    await Db.instance.s.insert('credit_ledger', {'amount': -amount, 'reason': reason});
    await load();
  }

  Future<void> earn(double amount, String reason) async {
    await Db.instance.s.insert('credit_ledger', {'amount': amount, 'reason': reason});
    await load();
  }

  Future<int> adsWatchedToday() async {
    final d = DateTime.now();
    final start = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    return (await Db.instance.s.scalar(
            "SELECT COUNT(*) FROM credit_ledger WHERE reason = 'Rewarded ad' AND created_at >= ? AND deleted_at IS NULL",
            [start]))
        .toInt();
  }
}

/// Super admin session (in memory only; cleared when the console closes).
class SuperAdmin {
  static SuperAdminKey? key;
  static bool get signedIn => key != null;

  static Future<String> issue({
    required String type,
    required String device,
    String? storeId,
    String? storeName,
    String? plan,
    List<String> features = const [],
    int expires = 0,
    int credits = 0,
    String? footer,
    String? phone,
  }) {
    final k = key;
    if (k == null) throw StateError('Super admin is not signed in.');
    return LicenseCodec.encode(
      LicensePayload(
        type: type,
        device: device.replaceAll('-', '').trim().toUpperCase(),
        nonce: newId().replaceAll('-', '').substring(0, 16),
        issued: nowMs(),
        storeId: storeId,
        storeName: storeName,
        plan: plan,
        features: features,
        expires: expires,
        credits: credits,
        footer: footer,
        phone: phone,
      ),
      k,
    );
  }
}
