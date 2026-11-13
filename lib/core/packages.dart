/// Plans, paid features, credit packs and vendor branding.
///
/// Prices are in PKR and only shown to shops (payment happens with the super
/// admin, who then issues a signed unlock code).
library;

/// Paid features that a plan or an upgrade code can unlock.
class Feature {
  /// Low-stock and pending-payment notifications, daily summary.
  static const alerts = 'alerts';

  /// Customer payment reminders over WhatsApp / SMS.
  static const reminders = 'reminders';

  /// Unlimited voice stock updates (otherwise each command costs a credit).
  static const voice = 'voice';

  /// Shop and products listed on the BizPOS online marketplace (phase 2).
  static const marketplace = 'marketplace';

  static const Map<String, String> labels = {
    alerts: 'Low stock and pending payment alerts',
    reminders: 'Customer payment reminders (WhatsApp / SMS)',
    voice: 'Unlimited voice stock updates',
    marketplace: 'Online marketplace listing (coming soon)',
  };

  static List<String> get all => labels.keys.toList();
}

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

  /// Voice credits included when the plan is activated.
  final int credits;
}

class Plans {
  static const trial = Plan(
    key: 'trial',
    name: 'Free trial',
    price: 'Free for 14 days',
    description: 'Everything in Basic for 14 days.',
    credits: 20,
  );

  static const basic = Plan(
    key: 'basic',
    name: 'Basic',
    price: 'Rs 15,000 one time',
    description: 'Full offline POS for one phone: sales, stock, purchases, customers, suppliers, '
        'expenses, accounts, reports, employees, invoices, returns, backup, barcode scanning.',
    credits: 20,
  );

  static const pro = Plan(
    key: 'pro',
    name: 'Pro',
    price: 'Rs 1,000 / month or Rs 10,000 / year',
    description: 'Basic plus alerts, payment reminders, unlimited voice and marketplace listing.',
    features: [Feature.alerts, Feature.reminders, Feature.voice, Feature.marketplace],
    credits: 100,
  );

  static const List<Plan> all = [trial, basic, pro];

  static Plan byKey(String? key) => all.firstWhere((p) => p.key == key, orElse: () => basic);
}

class CreditPack {
  const CreditPack(this.credits, this.price);
  final int credits;
  final String price;
}

class Credits {
  /// Cost of one voice command.
  static const voiceCost = 1;

  /// Credits for watching one rewarded ad.
  static const perAd = 3;

  /// Maximum ads per day.
  static const adsPerDay = 10;

  static const packs = [
    CreditPack(50, 'Rs 300'),
    CreditPack(200, 'Rs 1,000'),
    CreditPack(1000, 'Rs 4,000'),
  ];
}

/// Vendor branding shown on every screen, receipt and the login screen.
/// The super admin can change it; new values travel inside activation codes.
class Vendor {
  static const defaultName = 'BizPOS';
  static const defaultPhone = '03224699887';
  static const defaultFooter = 'Powered by BizPOS';

  /// Phone in international form for WhatsApp links.
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
