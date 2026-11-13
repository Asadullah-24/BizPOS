import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import '../core/license.dart';
import '../core/packages.dart';
import '../models/models.dart';
import 'ledger_service.dart';
import 'product_service.dart';

/// Paid "alerts" feature: phone notifications for low stock and money owed.
/// Checks run when the app opens or returns to the foreground, at most once a
/// day per alert unless the numbers get worse.
class AlertService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> _show(int id, String title, String body) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('bizpos_alerts', 'Business alerts',
            channelDescription: 'Low stock and pending payment alerts', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Sends a notification only when [value] is new today or larger than before.
  static bool _shouldNotify(String key, double value) {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final prev = Local.prefs.getString('alert_$key') ?? '';
    final parts = prev.split('|');
    if (parts.length == 2 && parts[0] == today && (double.tryParse(parts[1]) ?? 0) >= value) return false;
    Local.prefs.setString('alert_$key', '$today|$value');
    return true;
  }

  static Future<void> runChecks() async {
    if (!LicenseService.instance.has(Feature.alerts)) return;
    try {
      await _init();
      final low = await ProductService.lowStock(limit: 500);
      if (low.isNotEmpty && _shouldNotify('low', low.length.toDouble())) {
        final names = low.take(3).map((p) => p.displayName).join(', ');
        await _show(1, '${low.length} items low on stock', '$names${low.length > 3 ? '...' : ''}');
      }
      final due = (await LedgerService.parties('customer')).where((p) => p.balance > 0.009).toList();
      final total = due.fold<double>(0, (a, p) => a + p.balance);
      if (due.isNotEmpty && _shouldNotify('due', total)) {
        await _show(2, 'Pending payments: ${Fmt.money(total)}', '${due.length} customers owe you money. Open Reminders to send them a message.');
      }
    } catch (_) {
      // Notifications are best effort.
    }
  }
}

/// Paid "reminders" feature: payment reminder messages to customers.
class ReminderService {
  static String message(Party p) {
    final shop = AppState.instance.businessName;
    return 'Dear ${p.name}, this is a friendly reminder from $shop. '
        'Your pending balance is ${Fmt.money(p.balance)}. Thank you!';
  }

  static String _intl(String phone) => Vendor.whatsappNumber(phone);

  static Future<void> whatsapp(Party p) async {
    final phone = p.phone ?? '';
    if (phone.isEmpty) throw StateError('Add a phone number for ${p.name} first.');
    final uri = Uri.parse('https://wa.me/${_intl(phone)}?text=${Uri.encodeComponent(message(p))}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) throw StateError('WhatsApp could not be opened.');
  }

  static Future<void> sms(Party p) async {
    final phone = p.phone ?? '';
    if (phone.isEmpty) throw StateError('Add a phone number for ${p.name} first.');
    final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': message(p)});
    if (!await launchUrl(uri)) throw StateError('SMS app could not be opened.');
  }
}

/// Opens WhatsApp or the dialer for the BizPOS vendor (super admin).
class VendorContact {
  static Future<void> whatsapp(String text) async {
    final phone = LicenseService.instance.phone;
    final uri = Uri.parse('https://wa.me/${Vendor.whatsappNumber(phone)}?text=${Uri.encodeComponent(text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> call() async {
    await launchUrl(Uri(scheme: 'tel', path: LicenseService.instance.phone));
  }
}
