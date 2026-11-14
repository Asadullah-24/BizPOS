/// Free tier, paid features, packages and vendor branding.
///
/// Free (no account or subscription needed): POS, products, stock, categories,
/// customers, sales, returns, purchases, suppliers, expenses, accounts, backup,
/// barcode scanning. No ads anywhere.
/// Paid features come from a subscription the super admin assigns online, or an
/// offline signed code.
library;

class Feature {
  /// Full reports, profit and loss, PDF export.
  static const reports = 'reports';

  /// Employees with their own PIN, roles and permissions.
  static const employees = 'employees';

  /// Own logo on invoices, login screen and dashboard.
  static const branding = 'branding';

  /// Low-stock and pending-payment notifications.
  static const alerts = 'alerts';

  /// Customer payment reminders over WhatsApp / SMS.
  static const reminders = 'reminders';

  /// Voice stock updates.
  static const voice = 'voice';

  /// Shop and products on the BizPOS online marketplace (phase 2).
  static const marketplace = 'marketplace';

  static const Map<String, String> labels = {
    reports: 'Full reports and profit',
    employees: 'Employees, roles and permissions',
    branding: 'Your logo on invoices and the app',
    alerts: 'Low stock and pending payment alerts',
    reminders: 'Customer payment reminders (WhatsApp / SMS)',
    voice: 'Voice stock updates',
    marketplace: 'Online marketplace listing (coming soon)',
  };

  static List<String> get all => labels.keys.toList();
}

/// Offline plans used by signed codes (shops without internet).
class Plan {
  const Plan({
    required this.key,
    required this.name,
    required this.price,
    required this.description,
    this.features = const [],
    this.credits = 0,
  });

  final String key;
  final String name;
  final String price;
  final String description;
  final List<String> features;
  final int credits;
}

class Plans {
  /// Products a free shop may add. Paid plans have no limit unless the
  /// package or the super admin sets one.
  static const freeMaxProducts = 100;

  static const free = Plan(key: 'free', name: 'Free', price: 'Free', description: 'Core POS, free forever.');

  static const trial = Plan(
    key: 'trial',
    name: 'Free trial',
    price: 'Free for 14 days',
    description: 'Every paid feature for 14 days.',
    features: [Feature.reports, Feature.employees, Feature.branding, Feature.alerts, Feature.reminders, Feature.voice],
  );

  static const basic = Plan(
    key: 'basic',
    name: 'Basic',
    price: 'Rs 15,000 one time',
    description: 'Full reports, employees and your logo. Lifetime.',
    features: [Feature.reports, Feature.employees, Feature.branding],
  );

  static const pro = Plan(
    key: 'pro',
    name: 'Pro',
    price: 'Rs 1,000 / month or Rs 10,000 / year',
    description: 'Everything: reports, employees, logo, alerts, reminders, voice, marketplace.',
    features: [
      Feature.reports, Feature.employees, Feature.branding, Feature.alerts, Feature.reminders, Feature.voice,
      Feature.marketplace,
    ],
  );

  static const List<Plan> all = [trial, basic, pro];

  static Plan byKey(String? key) => [free, ...all].firstWhere((p) => p.key == key, orElse: () => free);
}

/// Online package (Firestore packages/{id}), created and edited by the super admin.
class Package {
  Package({
    required this.id,
    required this.name,
    this.price = '',
    this.amount = 0,
    this.days = 30,
    this.features = const [],
    this.adFree = true,
    this.active = true,
    this.sort = 0,
    this.description = '',
    this.maxProducts = 0,
    this.onlineProducts = 0,
  });

  final String id;
  String name;

  /// Products the shop may show on its online store; 0 means no limit.
  int onlineProducts;

  /// Most products a shop on this package may have; 0 means no limit.
  int maxProducts;

  /// Shown to shops, e.g. "Rs 1,000 / month".
  String price;

  /// Amount in PKR, used for revenue totals.
  double amount;

  /// Validity in days; 0 means lifetime.
  int days;
  List<String> features;
  bool adFree;
  bool active;
  int sort;
  String description;

  factory Package.fromMap(String id, Map<String, dynamic> m) => Package(
        id: id,
        name: (m['name'] ?? '') as String,
        price: (m['price'] ?? '') as String,
        amount: ((m['amount'] ?? 0) as num).toDouble(),
        days: ((m['days'] ?? 30) as num).toInt(),
        features: ((m['features'] as List?) ?? []).map((e) => '$e').toList(),
        adFree: (m['adFree'] ?? true) as bool,
        active: (m['active'] ?? true) as bool,
        sort: ((m['sort'] ?? 0) as num).toInt(),
        description: (m['description'] ?? '') as String,
        maxProducts: ((m['maxProducts'] ?? 0) as num).toInt(),
        onlineProducts: ((m['onlineProducts'] ?? 0) as num).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'maxProducts': maxProducts,
        'onlineProducts': onlineProducts,
        'name': name,
        'price': price,
        'amount': amount,
        'days': days,
        'features': features,
        'adFree': adFree,
        'active': active,
        'sort': sort,
        'description': description,
      };

  static List<Package> defaults() => [
        Package(id: 'starter-monthly', name: 'Starter', price: 'Rs 500 / month', amount: 500, days: 30, sort: 1,
            features: [Feature.reports, Feature.employees, Feature.branding], description: 'Reports, employees, your logo.'),
        Package(id: 'pro-monthly', name: 'Pro monthly', price: 'Rs 1,000 / month', amount: 1000, days: 30, sort: 2,
            features: Plans.pro.features, description: 'Everything in BizPOS.'),
        Package(id: 'trial-14', name: 'Free trial', price: 'Free for 14 days', amount: 0, days: 14, sort: 0,
            features: Plans.pro.features, description: 'Try every paid feature for 14 days.'),
        Package(id: 'pro-yearly', name: 'Pro yearly', price: 'Rs 10,000 / year', amount: 10000, days: 365, sort: 3,
            features: Plans.pro.features, description: 'Everything, two months free.'),
        Package(id: 'lifetime', name: 'Lifetime Basic', price: 'Rs 15,000 one time', amount: 15000, days: 0, sort: 4,
            features: Plans.basic.features, description: 'Reports, employees, your logo. Forever.'),
      ];
}

/// What a shop's online subscription grants, read from shops/{id}.
class CloudPlan {
  CloudPlan({
    this.name = 'Free',
    this.packageId = 'free',
    this.features = const {},
    this.adFree = false,
    this.expiresAt = 0,
    this.status = 'active',
    this.maxProducts = 0,
    this.productLimit,
  });

  /// Product limit from the package (0 = none); applies while the plan is active.
  final int maxProducts;

  /// Limit the super admin set for this shop by hand (0 = none); always applies.
  final int? productLimit;

  final String name;
  final String packageId;
  final Set<String> features;
  final bool adFree;

  /// 0 means no expiry (lifetime) when a paid package is set.
  final int expiresAt;

  /// active | blocked
  final String status;

  bool get paid => packageId != 'free';
  bool get blocked => status == 'blocked';
  bool activeAt(int now) => paid && !blocked && (expiresAt == 0 || expiresAt > now);

  factory CloudPlan.fromShop(Map<String, dynamic>? m) {
    if (m == null) return CloudPlan();
    return CloudPlan(
      name: (m['planName'] ?? 'Free') as String,
      packageId: (m['plan'] ?? 'free') as String,
      features: ((m['features'] as List?) ?? []).map((e) => '$e').toSet(),
      adFree: (m['adFree'] ?? false) as bool,
      expiresAt: ((m['expiresAt'] ?? 0) as num).toInt(),
      status: (m['status'] ?? 'active') as String,
      maxProducts: ((m['maxProducts'] ?? 0) as num).toInt(),
      productLimit: (m['productLimit'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'planName': name,
        'plan': packageId,
        'features': features.toList(),
        'adFree': adFree,
        'expiresAt': expiresAt,
        'status': status,
        'maxProducts': maxProducts,
        if (productLimit != null) 'productLimit': productLimit,
      };
}

class Credits {
  static const voiceCost = 1;
  static const perAd = 3;
  static const adsPerDay = 10;
  static const packs = <CreditPack>[];
}

class CreditPack {
  const CreditPack(this.credits, this.price);
  final int credits;
  final String price;
}

/// Vendor branding shown on every screen, receipt and the login screen.
class Vendor {
  static const defaultName = 'BizPOS';
  static const defaultPhone = '03224699887';
  static const defaultFooter = 'Powered by BizPOS';

  static String whatsappNumber(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) return '92${digits.substring(1)}';
    return digits;
  }

  static String pretty(String phone) {
    final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 11 && d.startsWith('0')) return '${d.substring(0, 4)}-${d.substring(4)}';
    return phone;
  }
}
