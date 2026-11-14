import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'business_templates.dart';
import 'db.dart';
import 'format.dart';
import 'i18n.dart';
import 'permissions.dart';

/// Global app state: business settings, business type, and the signed-in employee.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  Map<String, String> settings = {};
  BusinessType? businessType;
  Employee? user;
  Set<String> _perms = {};

  bool get onboarded => settings['onboarded'] == '1';
  bool get locked => user == null;

  String get businessName => settings['business_name'] ?? 'My Business';
  String get language => settings['language'] ?? 'en';
  bool get taxEnabled => settings['tax_enabled'] == '1' && hasModule(Mod.tax);
  double get defaultTaxRate => double.tryParse(settings['tax_rate'] ?? '') ?? 0;
  bool get taxInclusive => settings['tax_inclusive'] == '1';
  String get invoicePrefix => (settings['invoice_prefix'] ?? 'INV').trim();
  String get invoiceFooter => settings['invoice_footer'] ?? 'Thank you for your business!';
  int get paperMm => int.tryParse(settings['receipt_paper'] ?? '') ?? 58;
  int get autoLockMinutes => int.tryParse(settings['auto_lock_minutes'] ?? '') ?? 0;

  Future<void> load() async {
    settings = await Db.instance.allSettings();
    _applyFormatting();
    final typeId = settings['business_type_id'];
    if (typeId != null) {
      final r = await Db.instance.s.byId('business_types', typeId);
      businessType = r == null ? null : BusinessType.fromRow(r);
    }
    if (user != null) await _loadPerms();
    notifyListeners();
  }

  void _applyFormatting() {
    Fmt.symbol = settings['currency_symbol'] ?? 'Rs';
    Fmt.decimals = int.tryParse(settings['currency_decimals'] ?? '') ?? 0;
    Fmt.symbolAfter = settings['currency_after'] == '1';
    I18n.lang = language;
  }

  /// Settings that are also shown online (shop record and website card).
  static const profileKeys = {'business_name', 'business_phone', 'business_address', 'currency_symbol', 'business_type'};

  /// Set by the cloud service: copies the shop profile online when it changes.
  static void Function()? onProfileChanged;

  Future<void> setSetting(String key, String value) async {
    await Db.instance.setSetting(key, value);
    settings[key] = value;
    _applyFormatting();
    notifyListeners();
    if (profileKeys.contains(key)) onProfileChanged?.call();
  }

  Future<void> setSettings(Map<String, String> values) async {
    for (final e in values.entries) {
      await Db.instance.setSetting(e.key, e.value);
      settings[e.key] = e.value;
    }
    _applyFormatting();
    notifyListeners();
    if (values.keys.any(profileKeys.contains)) onProfileChanged?.call();
  }

  /// Switches language before the business exists (onboarding).
  void previewLanguage(String lang) {
    settings['language'] = lang;
    I18n.lang = lang;
    notifyListeners();
  }

  Future<void> reloadBusinessType() async {
    await load();
  }

  bool hasModule(String module) => businessType?.has(module) ?? true;

  bool can(String perm) => user != null && (user!.isOwner || _perms.contains(perm));

  /// Module enabled for the business AND permitted for the user.
  bool allowed(String module, String perm) => hasModule(module) && can(perm);

  Future<void> login(Employee e) async {
    user = e;
    await _loadPerms();
    notifyListeners();
  }

  void lock() {
    user = null;
    _perms = {};
    notifyListeners();
  }

  Future<void> _loadPerms() async {
    final u = user;
    if (u == null) return;
    if (u.isOwner) {
      _perms = Perm.all.toSet();
      return;
    }
    if (u.roleId == null) {
      _perms = {};
      return;
    }
    final r = await Db.instance.s.byId('roles', u.roleId!);
    _perms = r == null ? {} : Role.fromRow(r).permissions.toSet();
  }
}
