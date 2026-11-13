import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../core/access.dart';
import '../../core/packages.dart';
import '../../services/cloud_service.dart';
import '../brand.dart';
import 'account_screen.dart';
import 'admin/admin_panel.dart';
import '../../services/printer_service.dart';
import '../../services/product_service.dart';
import '../common.dart';
import 'plan_screen.dart';
import 'super_admin/super_admin_login.dart';
import 'two_factor_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _text(BuildContext context, String key, String title, {bool number = false}) async {
    final app = AppState.instance;
    final v = await promptText(context, title, initial: app.settings[key] ?? '', number: number);
    if (v == null) return;
    await app.setSetting(key, v.trim());
  }

  Widget _textTile(BuildContext context, String key, String title, IconData icon, {bool number = false, String empty = 'Not set'}) {
    final v = AppState.instance.settings[key] ?? '';
    return ListTile(
      leading: Icon(icon),
      title: Text(tr(title)),
      subtitle: Text(v.isEmpty ? tr(empty) : v),
      onTap: () => _text(context, key, title, number: number),
    );
  }

  Widget _switch(String key, String title, {String? subtitle}) {
    final app = AppState.instance;
    return SwitchListTile(
      title: Text(tr(title)),
      subtitle: subtitle == null ? null : Text(tr(subtitle)),
      value: app.settings[key] == '1',
      onChanged: (v) => app.setSetting(key, v ? '1' : '0'),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final app = AppState.instance;
    final pin = await promptText(context, 'New PIN', label: '4-8 digits', number: true);
    if (pin == null || !context.mounted) return;
    final p = pin.trim();
    if (p.length < 4 || int.tryParse(p) == null) return showSnack(context, tr('PIN must be at least 4 digits.'), error: true);
    if (await AuthService.pinTaken(p, exceptId: app.user!.id)) {
      if (context.mounted) showSnack(context, tr('Another employee already uses this PIN.'), error: true);
      return;
    }
    await Db.instance.s.update('employees', app.user!.id, AuthService.pinColumns(p));
    if (context.mounted) showSnack(context, tr('PIN changed'));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final admin = app.can(Perm.settings);
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(children: [
        if (admin) ...[
          const SectionTitle('Business profile'),
          ListTile(
            leading: ProductThumb(image: s['logo'], name: app.businessName, size: 40),
            title: Text(tr('Business logo')),
            subtitle: Text(tr('Shown on the login screen, dashboard and invoices')),
            onTap: () => openFeature(context, Feature.branding, () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
              if (x == null) return;
              final name = await ImageStore.save(File(x.path));
              await app.setSetting('logo', name);
            }),
            onLongPress: () => app.setSetting('logo', ''),
          ),
          _textTile(context, 'business_name', 'Business name', Icons.storefront),
          _textTile(context, 'business_phone', 'Phone', Icons.phone),
          _textTile(context, 'business_address', 'Address', Icons.location_on_outlined),
          _textTile(context, 'business_email', 'Email', Icons.email_outlined),
          _textTile(context, 'tax_number', 'Tax / NTN number', Icons.numbers),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(tr('Business type and modules')),
            subtitle: Text(app.businessType?.name ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessTypeEditor())),
          ),
          const SectionTitle('Currency and language'),
          _textTile(context, 'currency_symbol', 'Currency symbol', Icons.attach_money),
          _textTile(context, 'currency_decimals', 'Decimal places', Icons.pin_outlined, number: true, empty: '0'),
          _switch('currency_after', 'Show symbol after the amount'),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('Language')),
            subtitle: Text(I18n.languages[app.language] ?? app.language),
            onTap: () async {
              final l = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(tr('Language')),
                  children: [
                    for (final e in I18n.languages.entries)
                      SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
                  ],
                ),
              );
              if (l != null) await app.setSetting('language', l);
            },
          ),
          if (app.hasModule(Mod.tax)) ...[
            const SectionTitle('Tax'),
            _switch('tax_enabled', 'Charge tax'),
            if (s['tax_enabled'] == '1') ...[
              _textTile(context, 'tax_rate', 'Default tax rate (%)', Icons.percent, number: true, empty: '0'),
              _switch('tax_inclusive', 'Prices already include tax'),
            ],
          ],
          const SectionTitle('Invoices and receipts'),
          _textTile(context, 'invoice_prefix', 'Invoice number prefix', Icons.tag, empty: 'INV'),
          _textTile(context, 'invoice_footer', 'Receipt footer', Icons.short_text),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(tr('Receipt paper width')),
            subtitle: Text('${app.paperMm} mm'),
            onTap: () async {
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(title: Text(tr('Receipt paper width')), children: [
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, '58'), child: const Text('58 mm')),
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, '80'), child: const Text('80 mm')),
                ]),
              );
              if (v != null) await app.setSetting('receipt_paper', v);
            },
          ),
          _switch('auto_print', 'Print receipt automatically after each sale'),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: Text(tr('Printer')),
            subtitle: Text(_printerLabel()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen())),
          ),
          const SectionTitle('Selling'),
          _switch('block_out_of_stock', 'Block selling items that are out of stock'),
        ],
        const SectionTitle('Appearance'),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(tr('Theme')),
          subtitle: Text(tr(switch (s['theme'] ?? 'dark') { 'light' => 'Light', 'system' => 'Same as phone', _ => 'Dark' })),
          onTap: () async {
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(title: Text(tr('Theme')), children: [
                for (final e in const {'dark': 'Dark', 'light': 'Light', 'system': 'Same as phone'}.entries)
                  SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(tr(e.value))),
              ]),
            );
            if (v != null) await app.setSetting('theme', v);
          },
        ),
        const SectionTitle('Plan'),
        if (CloudService.instance.configured)
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(tr('Account')),
            subtitle: Text(CloudService.instance.user?.email ?? tr('Not signed in')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
          ),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr('Plan and upgrades')),
          subtitle: Text(tr(Access.instance.planName)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
        ),
        const SectionTitle('Security'),
        ListTile(leading: const Icon(Icons.password), title: Text(tr('Change my PIN')), onTap: () => _changePin(context)),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(tr('Two-factor sign-in (authenticator)')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TwoFactorScreen())),
        ),
        if (admin)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('Auto-lock')),
            subtitle: Text(app.autoLockMinutes == 0 ? tr('Off') : '${app.autoLockMinutes} ${tr('minutes in background')}'),
            onTap: () async {
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(title: Text(tr('Auto-lock')), children: [
                  for (final m in ['0', '1', '5', '15', '30'])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, m),
                      child: Text(m == '0' ? tr('Off') : '$m ${tr('minutes')}'),
                    ),
                ]),
              );
              if (v != null) await app.setSetting('auto_lock_minutes', v);
            },
          ),
        const SectionTitle('About'),
        if (CloudService.instance.isAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: Text(tr('Super admin panel')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminGate())),
          ),
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: Text(tr('Offline unlock codes (super admin)')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminLogin())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('BizPOS 1.2.0'),
          subtitle: Text('${tr('Device')} ${Db.instance.deviceId.substring(0, 8).toUpperCase()}'),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  String _printerLabel() {
    switch (PrinterService.type) {
      case 'bluetooth':
        return 'Bluetooth: ${PrinterService.btName ?? PrinterService.btAddress ?? ''}';
      case 'network':
        return 'Network: ${PrinterService.ip ?? ''}:${PrinterService.port}';
      default:
        return tr('System print dialog (Wi-Fi printers, PDF)');
    }
  }
}

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<PrinterDevice>? _devices;
  bool _loading = false;
  final _ip = TextEditingController(text: PrinterService.ip ?? '');
  final _port = TextEditingController(text: '${PrinterService.port}');

  Future<void> _scan() async {
    setState(() => _loading = true);
    await guard(context, () async {
      final d = await PrinterService.pairedPrinters();
      if (mounted) setState(() => _devices = d);
    });
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final type = PrinterService.type;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Printer'))),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        RadioListTile<String>(
          value: 'system',
          groupValue: type,
          title: Text(tr('System print dialog')),
          subtitle: Text(tr('Wi-Fi and network printers through Android/iOS printing, or save as PDF')),
          onChanged: (_) async {
            await PrinterService.useSystem();
            setState(() {});
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.bluetooth),
          title: Text(tr('Bluetooth thermal printer')),
          subtitle: Text(type == 'bluetooth' ? '${tr('Selected')}: ${PrinterService.btName}' : tr('Pair the printer in phone Bluetooth settings first')),
          trailing: _loading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonal(onPressed: _scan, child: Text(tr('Find'))),
        ),
        for (final d in _devices ?? <PrinterDevice>[])
          RadioListTile<String>(
            value: d.address,
            groupValue: type == 'bluetooth' ? PrinterService.btAddress : null,
            title: Text(d.name),
            subtitle: Text(d.address),
            onChanged: (_) async {
              await PrinterService.saveBluetooth(d);
              setState(() {});
            },
          ),
        if (_devices != null && _devices!.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(tr('No paired Bluetooth devices found.'))),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.lan_outlined),
          title: Text(tr('Network thermal printer (ESC/POS)')),
          subtitle: Text(type == 'network' ? '${tr('Selected')}: ${PrinterService.ip}:${PrinterService.port}' : tr('Printer and phone on the same Wi-Fi')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(flex: 3, child: TextField(controller: _ip, decoration: InputDecoration(labelText: tr('IP address')))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Port')))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: () async {
              if (_ip.text.trim().isEmpty) return;
              await PrinterService.saveNetwork(_ip.text, int.tryParse(_port.text) ?? 9100);
              if (!mounted) return;
              setState(() {});
              showSnack(context, tr('Network printer saved'));
            },
            child: Text(tr('Use network printer')),
          ),
        ),
      ]),
    );
  }
}

/// Edit the business type: name, enabled modules, units and extra product fields.
class BusinessTypeEditor extends StatefulWidget {
  const BusinessTypeEditor({super.key});

  @override
  State<BusinessTypeEditor> createState() => _BusinessTypeEditorState();
}

class _BusinessTypeEditorState extends State<BusinessTypeEditor> {
  late final BusinessType? _type = AppState.instance.businessType;
  late final _name = TextEditingController(text: _type?.name ?? '');
  late final Set<String> _modules = {...?_type?.modules};
  late final List<String> _units = [...?_type?.units];
  late final List<String> _fields = [...?_type?.fields];

  Future<void> _addTo(List<String> list, String title) async {
    final v = await promptText(context, title, label: 'Name');
    if (v == null || v.trim().isEmpty) return;
    setState(() => list.add(v.trim()));
  }

  Future<void> _save() async {
    final t = _type;
    if (t == null) return;
    t
      ..name = _name.text.trim().isEmpty ? t.name : _name.text.trim()
      ..modules = _modules.toList()
      ..units = _units
      ..fields = _fields;
    await Db.instance.s.update('business_types', t.id, t.toRow());
    await AppState.instance.load();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_type == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline, text: 'Not found'));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Business type')), actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)]),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(controller: _name, decoration: InputDecoration(labelText: tr('Business type name'))),
        ),
        const SectionTitle('Modules'),
        for (final e in Mod.labels.entries)
          SwitchListTile(
            title: Text(tr(e.value)),
            value: _modules.contains(e.key),
            onChanged: e.key == Mod.pos
                ? null
                : (v) => setState(() => v ? _modules.add(e.key) : _modules.remove(e.key)),
          ),
        SectionTitle('Units', trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _addTo(_units, 'New unit'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final u in _units) InputChip(label: Text(u), onDeleted: () => setState(() => _units.remove(u))),
          ]),
        ),
        SectionTitle('Extra product fields',
            trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _addTo(_fields, 'New product field'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in _fields) InputChip(label: Text(f), onDeleted: () => setState(() => _fields.remove(f))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: Text(tr('Save'))),
        ),
      ]),
    );
  }
}
