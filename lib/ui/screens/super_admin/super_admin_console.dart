import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/business_templates.dart';
import '../../../core/db.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/ids.dart';
import '../../../core/license.dart';
import '../../../core/packages.dart';
import '../../../core/totp.dart';
import '../../common.dart';
import '../activation_screen.dart';
import '../scanner_screen.dart';

String get _saFooter => Local.prefs.getString('sa_footer') ?? Vendor.defaultFooter;
String get _saPhone => Local.prefs.getString('sa_phone') ?? Vendor.defaultPhone;

String expiryLabel(int expires) {
  if (expires == 0) return tr('Lifetime');
  final days = ((expires - nowMs()) / 86400000).ceil();
  final date = Fmt.date(expires);
  if (days < 0) return '${tr('Expired')} $date';
  return '$date ($days ${tr('days left')})';
}

class SuperAdminConsole extends StatelessWidget {
  const SuperAdminConsole({super.key});

  @override
  Widget build(BuildContext context) {
    final lic = LicenseService.instance;
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(icon)),
            title: Text(tr(title)),
            subtitle: Text(tr(sub)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) SuperAdmin.key = null;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Super admin console')), actions: [
          IconButton(
            tooltip: tr('Sign out'),
            icon: const Icon(Icons.logout),
            onPressed: () {
              SuperAdmin.key = null;
              Navigator.pop(context);
            },
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          tile(Icons.add_business, 'Activate or upgrade a shop', 'Signed code or QR bound to the shop phone',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueCodeScreen(type: 'act')))),
          tile(Icons.toll, 'Give voice credits', 'One-time credit code',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssueCodeScreen(type: 'cred')))),
          tile(Icons.store, 'My shops', 'Every shop you activated, renewals and QR codes',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoresRegistryScreen()))),
          tile(Icons.phone_android, 'Set up this phone for a shop', 'Activate this device ${lic.deviceCodePretty} directly',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueCodeScreen(type: 'act', device: lic.deviceCode)))),
          tile(Icons.brush, 'Branding', 'Footer and support number shown in every shop app',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrandingScreen()))),
          tile(Icons.inventory, 'Packages and prices', 'What each plan includes',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PackagesScreen()))),
          tile(Icons.security, 'Authenticator (2FA)', 'Add the super admin code to another phone',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthenticatorScreen()))),
        ]),
      ),
    );
  }
}

class IssueCodeScreen extends StatefulWidget {
  const IssueCodeScreen({super.key, required this.type, this.device, this.store});

  /// act | cred
  final String type;
  final String? device;
  final DbRow? store;

  @override
  State<IssueCodeScreen> createState() => _IssueCodeScreenState();
}

class _IssueCodeScreenState extends State<IssueCodeScreen> {
  late final _device = TextEditingController(text: widget.device ?? (widget.store?['device'] as String?) ?? '');
  late final _name = TextEditingController(text: (widget.store?['name'] as String?) ?? '');
  late final _phone = TextEditingController(text: (widget.store?['owner_phone'] as String?) ?? '');
  late final _credits = TextEditingController(text: widget.type == 'cred' ? '50' : '${Plans.basic.credits}');
  late String _category = (widget.store?['category'] as String?) ?? businessTemplates.first.name;
  late String _plan = (widget.store?['plan'] as String?) ?? 'basic';
  String _duration = 'lifetime';
  final Set<String> _extra = {};
  bool _brand = true;
  bool _busy = false;

  static const _durations = {
    'lifetime': 'Lifetime',
    '14d': '14 days',
    '1m': '1 month',
    '3m': '3 months',
    '6m': '6 months',
    '1y': '1 year',
  };

  @override
  void initState() {
    super.initState();
    _setPlan(_plan, keepCredits: false);
    if (widget.store != null) {
      final f = widget.store!['features'] as String?;
      if (f != null && f.isNotEmpty) _extra.addAll((jsonDecode(f) as List).map((e) => '$e'));
    }
  }

  void _setPlan(String p, {bool keepCredits = true}) {
    _plan = p;
    _duration = switch (p) { 'trial' => '14d', 'pro' => '1m', _ => 'lifetime' };
    if (!keepCredits || widget.type == 'act') _credits.text = '${Plans.byKey(p).credits}';
  }

  int _expiry() {
    final now = DateTime.now();
    final d = switch (_duration) {
      '14d' => now.add(const Duration(days: 14)),
      '1m' => DateTime(now.year, now.month + 1, now.day, 23, 59),
      '3m' => DateTime(now.year, now.month + 3, now.day, 23, 59),
      '6m' => DateTime(now.year, now.month + 6, now.day, 23, 59),
      '1y' => DateTime(now.year + 1, now.month, now.day, 23, 59),
      _ => null,
    };
    return d?.millisecondsSinceEpoch ?? 0;
  }

  Future<void> _scanDevice() async {
    final raw = await ScannerScreen.scan(context);
    if (raw == null) return;
    final code = parseDeviceCode(raw);
    if (code == null) {
      if (mounted) showSnack(context, tr('That QR is not a BizPOS device code.'), error: true);
      return;
    }
    setState(() => _device.text = code);
  }

  Future<void> _generate() async {
    final device = parseDeviceCode(_device.text);
    if (device == null) return showSnack(context, tr('Enter the 8-character device code from the shop phone.'), error: true);
    final isAct = widget.type == 'act';
    if (isAct && _name.text.trim().isEmpty) return showSnack(context, tr('Enter the shop name.'), error: true);
    final credits = int.tryParse(_credits.text.trim()) ?? 0;
    if (!isAct && credits <= 0) return showSnack(context, tr('Enter the number of credits.'), error: true);
    setState(() => _busy = true);
    final storeId = (widget.store?['store_id'] as String?) ?? newId().substring(0, 8);
    final expires = isAct ? _expiry() : 0;
    final code = await SuperAdmin.issue(
      type: widget.type,
      device: device,
      storeId: isAct ? storeId : null,
      storeName: isAct ? _name.text.trim() : null,
      plan: isAct ? _plan : null,
      features: isAct ? _extra.toList() : const [],
      expires: expires,
      credits: credits,
      footer: isAct && _brand ? _saFooter : null,
      phone: isAct && _brand ? _saPhone : null,
    );
    // Keep the super admin's register of shops up to date.
    final s = Db.instance.s;
    final existing = await s.one('SELECT * FROM sa_stores WHERE device = ? AND deleted_at IS NULL', [device]);
    if (isAct) {
      final row = {
        'store_id': storeId,
        'name': _name.text.trim(),
        'owner_phone': _phone.text.trim(),
        'category': _category,
        'device': device,
        'plan': _plan,
        'features': jsonEncode(_extra.toList()),
        'expires': expires,
        'credits': credits,
        'code': code,
      };
      if (existing == null) {
        await s.insert('sa_stores', row);
      } else {
        await s.update('sa_stores', existing['id'] as String, row);
      }
    } else if (existing != null) {
      await s.update('sa_stores', existing['id'] as String, {'credits': asInt(existing['credits']) + credits});
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CodeResultScreen(
          code: code,
          device: device,
          title: isAct ? '${Plans.byKey(_plan).name} · ${tr(_durations[_duration]!)}' : '$credits ${tr('credits')}',
          ownerPhone: _phone.text.trim().isEmpty ? (existing?['owner_phone'] as String?) : _phone.text.trim(),
          shopName: isAct ? _name.text.trim() : (existing?['name'] as String?),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAct = widget.type == 'act';
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: Text(tr(isAct ? 'Activate or upgrade a shop' : 'Give voice credits'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _device,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr('Shop device code'),
            hintText: 'XXXX-XXXX',
            suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scanDevice),
          ),
        ),
        if (isAct) ...[
          gap,
          TextField(controller: _name, decoration: InputDecoration(labelText: tr('Shop name'))),
          gap,
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Owner phone (WhatsApp)'))),
          gap,
          DropdownButtonFormField<String>(
            value: businessTemplates.any((t) => t.name == _category) ? _category : businessTemplates.first.name,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Category')),
            items: [for (final t in businessTemplates) DropdownMenuItem(value: t.name, child: Text(tr(t.name)))],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SectionTitle('Plan'),
          SegmentedButton<String>(
            segments: [for (final p in Plans.all) ButtonSegment(value: p.key, label: Text(tr(p.name)))],
            selected: {_plan},
            onSelectionChanged: (s) => setState(() => _setPlan(s.first)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${Plans.byKey(_plan).price}\n${tr(Plans.byKey(_plan).description)}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          DropdownButtonFormField<String>(
            value: _duration,
            decoration: InputDecoration(labelText: tr('Valid for')),
            items: [for (final e in _durations.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
            onChanged: (v) => setState(() => _duration = v ?? _duration),
          ),
          const SectionTitle('Extra paid features'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final f in Feature.all)
              FilterChip(
                label: Text(tr(Feature.labels[f]!)),
                selected: _extra.contains(f) || Plans.byKey(_plan).features.contains(f),
                onSelected: Plans.byKey(_plan).features.contains(f)
                    ? null
                    : (v) => setState(() => v ? _extra.add(f) : _extra.remove(f)),
              ),
          ]),
          gap,
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Include my branding')),
            subtitle: Text('$_saFooter · ${Vendor.pretty(_saPhone)}'),
            value: _brand,
            onChanged: (v) => setState(() => _brand = v),
          ),
        ],
        gap,
        NumField(controller: _credits, label: isAct ? 'Voice credits included' : 'Credits'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.qr_code_2),
          label: Text(tr('Generate code')),
        ),
      ]),
    );
  }
}

class CodeResultScreen extends StatelessWidget {
  const CodeResultScreen({super.key, required this.code, required this.device, required this.title, this.ownerPhone, this.shopName});
  final String code;
  final String device;
  final String title;
  final String? ownerPhone;
  final String? shopName;

  @override
  Widget build(BuildContext context) {
    final thisPhone = device == LicenseService.instance.deviceCode;
    final text = 'BizPOS code for ${shopName ?? 'your shop'} ($title):\n$code';
    return Scaffold(
      appBar: AppBar(title: Text(tr('Code ready'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(shopName ?? '', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        Text('$title · ${tr('Device')} ${device.substring(0, 4)}-${device.substring(4)}', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: code, size: 280, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr('On the shop phone tap "Scan activation QR" (or Plan > Scan code) and scan this.'),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        const SizedBox(height: 16),
        if (thisPhone)
          FilledButton.icon(
            icon: const Icon(Icons.check_circle),
            label: Text(tr('Apply on this phone')),
            onPressed: () async {
              final ok = await guard(context, () async {
                final msg = await LicenseService.instance.apply(code);
                if (context.mounted) showSnack(context, msg);
              });
              if (ok && context.mounted) {
                SuperAdmin.key = null;
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(tr('Copy code')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) showSnack(context, tr('Copied'));
          },
        ),
        const SizedBox(height: 8),
        if (ownerPhone != null && ownerPhone!.isNotEmpty)
          OutlinedButton.icon(
            icon: const Icon(Icons.chat, color: Colors.green),
            label: Text('${tr('Send on WhatsApp')} ${ownerPhone!}'),
            onPressed: () => launchUrl(
              Uri.parse('https://wa.me/${Vendor.whatsappNumber(ownerPhone!)}?text=${Uri.encodeComponent(text)}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.share), label: Text(tr('Share')), onPressed: () => Share.share(text)),
      ]),
    );
  }
}

class StoresRegistryScreen extends StatefulWidget {
  const StoresRegistryScreen({super.key});

  @override
  State<StoresRegistryScreen> createState() => _StoresRegistryScreenState();
}

class _StoresRegistryScreenState extends State<StoresRegistryScreen> {
  String _q = '';

  Future<void> _export(List<DbRow> rows) async {
    final b = StringBuffer('Shop,Owner phone,Category,Device,Plan,Expires,Credits given,Activated\n');
    String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    for (final r in rows) {
      b.writeln([
        esc(r['name']),
        esc(r['owner_phone']),
        esc(r['category']),
        esc(r['device']),
        esc(r['plan']),
        esc(asInt(r['expires']) == 0 ? 'Lifetime' : Fmt.date(asInt(r['expires']))),
        esc(r['credits']),
        esc(Fmt.date(asInt(r['created_at']))),
      ].join(','));
    }
    await Share.share(b.toString(), subject: 'BizPOS shops');
  }

  @override
  Widget build(BuildContext context) {
    return LiveData<List<DbRow>>(
      deps: [_q],
      load: () => Db.instance.s.q(
        "SELECT * FROM sa_stores WHERE deleted_at IS NULL AND (name LIKE ? OR IFNULL(owner_phone,'') LIKE ? OR device LIKE ?) ORDER BY name COLLATE NOCASE",
        ['%$_q%', '%$_q%', '%${_q.toUpperCase()}%'],
      ),
      builder: (context, rows) => Scaffold(
        appBar: AppBar(title: Text('${tr('My shops')} (${rows.length})'), actions: [
          IconButton(tooltip: tr('Export'), icon: const Icon(Icons.ios_share), onPressed: () => _export(rows)),
        ]),
        body: Column(children: [
          SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Shop, phone or device'),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.store, text: 'Shops you activate appear here.')
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final exp = asInt(r['expires']);
                      final daysLeft = exp == 0 ? 9999 : ((exp - nowMs()) / 86400000).ceil();
                      final color = daysLeft < 0 ? Colors.red : (daysLeft <= 7 ? Colors.orange.shade800 : Colors.green.shade700);
                      return ListTile(
                        leading: CircleAvatar(child: Text(((r['name'] as String?) ?? '?').characters.first.toUpperCase())),
                        title: Text(r['name'] as String),
                        subtitle: Text('${Plans.byKey(r['plan'] as String?).name} · ${r['category'] ?? ''} · ${r['device']}'),
                        trailing: Text(exp == 0 ? tr('Lifetime') : (daysLeft < 0 ? tr('Expired') : '$daysLeft d'),
                            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreRegistryDetail(store: r))),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class StoreRegistryDetail extends StatelessWidget {
  const StoreRegistryDetail({super.key, required this.store});
  final DbRow store;

  @override
  Widget build(BuildContext context) {
    final r = store;
    final phone = (r['owner_phone'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(r['name'] as String), actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (!await confirm(context, 'Remove shop', 'Remove ${r['name']} from your list? Their app keeps working.', danger: true)) return;
            await Db.instance.s.softDelete('sa_stores', r['id'] as String);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        KeyValue('Plan', Plans.byKey(r['plan'] as String?).name),
        KeyValue('Valid until', expiryLabel(asInt(r['expires']))),
        KeyValue('Category', '${r['category'] ?? ''}'),
        KeyValue('Device', '${r['device']}'),
        KeyValue('Owner phone', phone),
        KeyValue('Credits given', '${r['credits']}'),
        KeyValue('Activated', Fmt.date(asInt(r['created_at']))),
        const SizedBox(height: 12),
        Center(child: QrImageView(data: r['code'] as String, size: 240, backgroundColor: Colors.white)),
        Text(tr('Latest code for this shop'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.autorenew),
          label: Text(tr('Renew or upgrade')),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueCodeScreen(type: 'act', store: r))),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.toll),
          label: Text(tr('Give voice credits')),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => IssueCodeScreen(type: 'cred', store: r))),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat, color: Colors.green),
            label: Text('${tr('WhatsApp')} $phone'),
            onPressed: () => launchUrl(Uri.parse('https://wa.me/${Vendor.whatsappNumber(phone)}'), mode: LaunchMode.externalApplication),
          ),
        ],
      ]),
    );
  }
}

class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  final _footer = TextEditingController(text: _saFooter);
  final _phone = TextEditingController(text: _saPhone);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Branding'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Shown at the bottom of every screen, on the login screen and on receipts of every shop you activate. '
            'Changes reach a shop with its next activation or renewal code.')),
        const SizedBox(height: 16),
        TextField(controller: _footer, decoration: InputDecoration(labelText: tr('Footer text'))),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Support phone / WhatsApp'))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            await Local.prefs.setString('sa_footer', _footer.text.trim().isEmpty ? Vendor.defaultFooter : _footer.text.trim());
            await Local.prefs.setString('sa_phone', _phone.text.trim().isEmpty ? Vendor.defaultPhone : _phone.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(tr('Save')),
        ),
      ]),
    );
  }
}

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Packages and prices'))),
        body: const PackagesList(),
      );
}

/// Plans and credit packs, shared by the super admin and shop plan screens.
class PackagesList extends StatelessWidget {
  const PackagesList({super.key, this.shrink = false});
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final p in Plans.all)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(tr(p.name), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(p.price, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              Text(tr(p.description)),
              for (final f in p.features) Text('• ${tr(Feature.labels[f]!)}'),
              if (p.credits > 0) Text('• ${p.credits} ${tr('voice credits')}'),
            ]),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Voice credits'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text('${tr('One voice stock update uses')} ${Credits.voiceCost} ${tr('credit')}. '
                '${tr('Watch an ad for')} ${Credits.perAd} ${tr('free credits')} (${tr('up to')} ${Credits.adsPerDay} ${tr('a day')}).'),
            for (final c in Credits.packs) Text('• ${c.credits} ${tr('credits')}: ${c.price}'),
          ]),
        ),
      ),
    ];
    if (shrink) return Column(children: children);
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }
}

class AuthenticatorScreen extends StatelessWidget {
  const AuthenticatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final k = SuperAdmin.key;
    if (k == null) return const Scaffold(body: SizedBox());
    final uri = Totp.uri(secret: k.totpSecret, account: 'Super admin');
    return Scaffold(
      appBar: AppBar(title: Text(tr('Authenticator (2FA)'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Scan with Google Authenticator or Microsoft Authenticator on a phone you keep with you. '
            'Super admin sign-in needs the 6-digit code from it.')),
        const SizedBox(height: 16),
        Center(child: QrImageView(data: uri, size: 240, backgroundColor: Colors.white)),
        const SizedBox(height: 12),
        SelectableText(k.totpSecret, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
        const SizedBox(height: 8),
        Text(tr('Keep this secret private.'), textAlign: TextAlign.center),
      ]),
    );
  }
}
