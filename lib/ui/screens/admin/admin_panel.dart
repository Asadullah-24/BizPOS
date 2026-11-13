import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/ids.dart';
import '../../../core/license.dart';
import '../../../core/packages.dart';
import '../../../core/totp.dart';
import '../../../services/cloud_service.dart';
import '../../common.dart';
import '../auth/sign_in_screen.dart';
import '../super_admin/super_admin_login.dart';

int _ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : (v is num ? v.toInt() : 0);

/// Checks the super admin role and, when enabled, the authenticator code.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  static int _verifiedAt = 0;

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  final _code = TextEditingController();
  String? _error;

  bool get _needsCode {
    final a = CloudService.instance.adminDoc;
    final fresh = nowMs() - AdminGate._verifiedAt < 30 * 60 * 1000;
    return a['totpEnabled'] == true && (a['totpSecret'] as String?) != null && !fresh;
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    if (!cloud.isAdmin) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.block, text: 'Super admin only.'));
    }
    if (!_needsCode) return const AdminHome();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Super admin'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.security, size: 56),
        const SizedBox(height: 12),
        Text(tr('Enter the 6-digit code from your authenticator app.'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 8),
          onSubmitted: (_) => _check(),
        ),
        if (_error != null) Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _check, child: Text(tr('Continue'))),
      ]),
    );
  }

  void _check() {
    final secret = CloudService.instance.adminDoc['totpSecret'] as String;
    if (Totp.verify(secret, _code.text)) {
      AdminGate._verifiedAt = nowMs();
      setState(() => _error = null);
    } else {
      setState(() => _error = tr('Wrong code'));
    }
  }
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const _Overview(), const _Shops(), const _Packages(), const _Requests(), const _AdminSettings()];
    return Scaffold(
      appBar: AppBar(title: Text(tr(['Overview', 'Shops', 'Packages', 'Requests', 'Settings'][_tab]))),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.insights_outlined), label: tr('Overview')),
          NavigationDestination(icon: const Icon(Icons.store_outlined), label: tr('Shops')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: tr('Packages')),
          NavigationDestination(icon: const Icon(Icons.mark_email_unread_outlined), label: tr('Requests')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: tr('Settings')),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ overview

class _Overview extends StatelessWidget {
  const _Overview();

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month).millisecondsSinceEpoch;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: cloud.shops(),
      builder: (ctx, shopsSnap) {
        final shops = shopsSnap.data ?? [];
        final t = nowMs();
        final plans = shops.map((s) => (s, CloudPlan.fromShop(s))).toList();
        final paid = plans.where((p) => p.$2.activeAt(t)).length;
        final blocked = plans.where((p) => p.$2.blocked).length;
        final expiring = plans
            .where((p) => p.$2.activeAt(t) && p.$2.expiresAt != 0 && p.$2.expiresAt - t < 7 * 86400000)
            .toList()
          ..sort((a, b) => a.$2.expiresAt.compareTo(b.$2.expiresAt));
        return ListView(padding: const EdgeInsets.all(12), children: [
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              StatCard(label: 'Shops', value: '${shops.length}', icon: Icons.store),
              StatCard(label: 'Paid', value: '$paid', icon: Icons.workspace_premium, color: Colors.green.shade700),
              StatCard(label: 'Free', value: '${shops.length - paid - blocked}', icon: Icons.storefront, color: Colors.blueGrey),
              StatCard(label: 'Blocked', value: '$blocked', icon: Icons.block, color: Colors.red),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: cloud.subscriptionsSince(monthStart),
                builder: (ctx, s) => StatCard(
                  label: 'Revenue this month',
                  value: Fmt.money((s.data ?? []).fold<double>(0, (a, r) => a + ((r['amount'] ?? 0) as num).toDouble())),
                  icon: Icons.payments,
                  color: Colors.teal,
                ),
              ),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: cloud.requests(),
                builder: (ctx, s) => StatCard(label: 'Pending requests', value: '${(s.data ?? []).length}', icon: Icons.mark_email_unread, color: Colors.orange.shade800),
              ),
            ],
          ),
          SectionTitle('Expiring in 7 days (${expiring.length})'),
          if (expiring.isEmpty) const ListTile(title: Text('—')),
          for (final e in expiring)
            ListTile(
              title: Text('${e.$1['name']}'),
              subtitle: Text('${e.$2.name} · ${Fmt.date(e.$2.expiresAt)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopAdminDetail(shopId: e.$1['id'] as String))),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ shops

class _Shops extends StatefulWidget {
  const _Shops();

  @override
  State<_Shops> createState() => _ShopsState();
}

class _ShopsState extends State<_Shops> {
  String _q = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CloudService.instance.shops(),
      builder: (ctx, snap) {
        final t = nowMs();
        var list = snap.data ?? [];
        final q = _q.toLowerCase();
        list = list.where((s) {
          final p = CloudPlan.fromShop(s);
          final text = '${s['name']} ${s['ownerEmail']} ${s['phone']} ${s['category']}'.toLowerCase();
          if (q.isNotEmpty && !text.contains(q)) return false;
          return switch (_filter) {
            'paid' => p.activeAt(t),
            'free' => !p.activeAt(t) && !p.blocked,
            'expiring' => p.activeAt(t) && p.expiresAt != 0 && p.expiresAt - t < 7 * 86400000,
            'blocked' => p.blocked,
            _ => true,
          };
        }).toList();
        return Column(children: [
          SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Shop, email, phone or category'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final f in const ['all', 'paid', 'free', 'expiring', 'blocked'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(tr(f[0].toUpperCase() + f.substring(1))),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: snap.connectionState == ConnectionState.waiting && list.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const EmptyState(icon: Icons.store, text: 'No shops')
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = list[i];
                          final p = CloudPlan.fromShop(s);
                          final color = p.blocked ? Colors.red : (p.activeAt(t) ? Colors.green.shade700 : Colors.blueGrey);
                          return ListTile(
                            leading: CircleAvatar(child: Text(('${s['name'] ?? '?'}').characters.first.toUpperCase())),
                            title: Text('${s['name'] ?? ''}'),
                            subtitle: Text('${s['ownerEmail'] ?? ''} · ${s['category'] ?? ''}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(p.blocked ? tr('Blocked') : (p.activeAt(t) ? p.name : tr('Free')),
                                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                              if (p.activeAt(t)) Text(p.expiresAt == 0 ? tr('Lifetime') : Fmt.date(p.expiresAt), style: const TextStyle(fontSize: 11)),
                            ]),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopAdminDetail(shopId: s['id'] as String))),
                          );
                        },
                      ),
          ),
        ]);
      },
    );
  }
}

/// Picks a package and records a payment for a shop.
Future<void> assignDialog(BuildContext context, Map<String, dynamic> shop, {String? packageId, String? requestId}) async {
  final cloud = CloudService.instance;
  final packages = await cloud.packages().first;
  if (!context.mounted) return;
  if (packages.isEmpty) return showSnack(context, tr('Create packages first (Packages tab).'), error: true);
  var selected = packages.firstWhere((p) => p.id == packageId, orElse: () => packages.first);
  final amount = TextEditingController(text: Fmt.qty(selected.amount));
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${tr('Subscription for')} ${shop['name']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selected.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Package')),
              items: [for (final p in packages) DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.price}'))],
              onChanged: (v) => setS(() {
                selected = packages.firstWhere((p) => p.id == v);
                amount.text = Fmt.qty(selected.amount);
              }),
            ),
            const SizedBox(height: 8),
            Text(selected.days == 0 ? tr('Lifetime') : '${selected.days} ${tr('days, added to any time left')}',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            NumField(controller: amount, label: 'Amount received'),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (JazzCash ref, cash...)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Activate'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await guard(context, () async {
    await cloud.assignSubscription(shop, selected, amount: Fmt.parse(amount.text), note: note.text.trim());
    if (requestId != null) await cloud.resolveRequest(requestId, 'approved');
  }, success: 'Subscription activated');
}

class ShopAdminDetail extends StatelessWidget {
  const ShopAdminDetail({super.key, required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cloud.db.doc('shops/$shopId').snapshots(),
      builder: (ctx, snap) {
        final d = snap.data?.data();
        if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        final s = {'id': shopId, ...d};
        final p = CloudPlan.fromShop(s);
        final t = nowMs();
        final devices = ((d['devices'] as Map?) ?? {}).map((k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)));
        final phone = '${d['phone'] ?? ''}';
        return Scaffold(
          appBar: AppBar(title: Text('${d['name'] ?? ''}')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.blocked ? tr('Blocked') : (p.activeAt(t) ? p.name : tr('Free')),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (p.activeAt(t)) Text(p.expiresAt == 0 ? tr('Lifetime') : '${tr('Valid until')} ${Fmt.date(p.expiresAt)}'),
                  if (p.features.isNotEmpty) Text(p.features.map((f) => tr(Feature.labels[f] ?? f)).join(', '), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
            KeyValue('Owner', '${d['ownerEmail'] ?? ''}'),
            KeyValue('Phone', phone),
            KeyValue('Category', '${d['category'] ?? ''}'),
            KeyValue('Joined', _ms(d['createdAt']) == 0 ? '' : Fmt.date(_ms(d['createdAt']))),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.workspace_premium),
              label: Text(tr('Activate or extend subscription')),
              onPressed: () => assignDialog(context, s),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    if (await confirm(context, 'Move to free', 'Remove the paid plan from this shop now?')) {
                      if (context.mounted) await guard(context, () => cloud.setFree(shopId));
                    }
                  },
                  child: Text(tr('Set free')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: p.blocked ? null : Colors.red),
                  onPressed: () async {
                    final block = !p.blocked;
                    if (block && !await confirm(context, 'Block shop', 'The shop will not be able to sell until you unblock it.', danger: true)) return;
                    if (context.mounted) await guard(context, () => cloud.setBlocked(shopId, block));
                  },
                  child: Text(tr(p.blocked ? 'Unblock' : 'Block')),
                ),
              ),
            ]),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.chat, color: Colors.green),
                label: Text('${tr('WhatsApp')} $phone'),
                onPressed: () => launchUrl(Uri.parse('https://wa.me/${Vendor.whatsappNumber(phone)}'), mode: LaunchMode.externalApplication),
              ),
            ],
            const SectionTitle('Devices'),
            for (final e in devices.entries)
              ListTile(
                dense: true,
                leading: Icon(e.value['revoked'] == true ? Icons.phonelink_erase : Icons.phone_android),
                title: Text(e.key),
                subtitle: Text('${e.value['name'] ?? ''}${_ms(e.value['lastSeen']) == 0 ? '' : ' · ${Fmt.dateTime(_ms(e.value['lastSeen']))}'}'),
                trailing: TextButton(
                  onPressed: () => guard(context, () => cloud.db.doc('shops/$shopId').update({'devices.${e.key}.revoked': e.value['revoked'] != true})),
                  child: Text(tr(e.value['revoked'] == true ? 'Restore' : 'Remove')),
                ),
              ),
            const SectionTitle('Payments'),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: cloud.shopSubscriptions(shopId),
              builder: (ctx, s) => Column(children: [
                for (final r in s.data ?? [])
                  ListTile(
                    dense: true,
                    title: Text('${r['packageName']} · ${Fmt.money(((r['amount'] ?? 0) as num).toDouble())}'),
                    subtitle: Text('${_ms(r['createdAt']) == 0 ? '' : Fmt.dateTime(_ms(r['createdAt']))}${(r['note'] ?? '') == '' ? '' : ' · ${r['note']}'}'),
                  ),
                if ((s.data ?? []).isEmpty) const ListTile(dense: true, title: Text('—')),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ packages

class _Packages extends StatelessWidget {
  const _Packages();

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr('New package')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditor(package: Package(id: newId().substring(0, 8), name: '')))),
      ),
      body: StreamBuilder<List<Package>>(
        stream: cloud.packages(includeInactive: true),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting && list.isEmpty) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2,
              text: 'No packages yet.',
              action: FilledButton(
                onPressed: () => guard(context, cloud.seedPackages, success: 'Default packages created'),
                child: Text(tr('Create default packages')),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            for (final p in list)
              ListTile(
                leading: Icon(p.active ? Icons.inventory_2 : Icons.visibility_off),
                title: Text(p.name),
                subtitle: Text('${p.price} · ${p.days == 0 ? tr('Lifetime') : '${p.days} ${tr('days')}'} · ${p.features.length} ${tr('features')}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PackageEditor(package: p, existing: true))),
              ),
          ]);
        },
      ),
    );
  }
}

class PackageEditor extends StatefulWidget {
  const PackageEditor({super.key, required this.package, this.existing = false});
  final Package package;
  final bool existing;

  @override
  State<PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends State<PackageEditor> {
  late final p = widget.package;
  late final _name = TextEditingController(text: p.name);
  late final _price = TextEditingController(text: p.price);
  late final _amount = TextEditingController(text: numText(p.amount));
  late final _days = TextEditingController(text: '${p.days}');
  late final _sort = TextEditingController(text: '${p.sort}');
  late final _desc = TextEditingController(text: p.description);
  late final Set<String> _features = {...p.features};
  late bool _active = p.active;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, tr('Enter a name.'), error: true);
    p
      ..name = _name.text.trim()
      ..price = _price.text.trim()
      ..amount = Fmt.parse(_amount.text)
      ..days = int.tryParse(_days.text.trim()) ?? 30
      ..sort = int.tryParse(_sort.text.trim()) ?? 0
      ..description = _desc.text.trim()
      ..features = _features.toList()
      ..active = _active;
    final ok = await guard(context, () => CloudService.instance.savePackage(p), success: 'Saved');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: Text(tr(widget.existing ? 'Edit package' : 'New package')), actions: [
        if (widget.existing)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'Delete package', 'Shops already on it keep their plan until it expires.', danger: true)) return;
              if (!context.mounted) return;
              final ok = await guard(context, () => CloudService.instance.deletePackage(p.id));
              if (ok && context.mounted) Navigator.pop(context);
            },
          ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('Package name'))),
        gap,
        TextField(controller: _price, decoration: InputDecoration(labelText: tr('Price shown to shops'), hintText: 'Rs 1,000 / month')),
        gap,
        Row(children: [
          Expanded(child: NumField(controller: _amount, label: 'Amount (PKR)')),
          const SizedBox(width: 12),
          Expanded(child: NumField(controller: _days, label: 'Days (0 = lifetime)')),
        ]),
        gap,
        TextField(controller: _desc, maxLines: 2, decoration: InputDecoration(labelText: tr('Description'))),
        gap,
        NumField(controller: _sort, label: 'Order in list'),
        const SectionTitle('Features'),
        for (final f in Feature.all)
          CheckboxListTile(
            title: Text(tr(Feature.labels[f]!)),
            value: _features.contains(f),
            onChanged: (v) => setState(() => v == true ? _features.add(f) : _features.remove(f)),
          ),
        SwitchListTile(title: Text(tr('Visible to shops')), value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ]),
    );
  }
}

// ------------------------------------------------------------------ requests

class _Requests extends StatelessWidget {
  const _Requests();

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: cloud.requests(),
      builder: (ctx, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) return const EmptyState(icon: Icons.mark_email_read_outlined, text: 'No pending requests');
        list.sort((a, b) => _ms(b['createdAt']).compareTo(_ms(a['createdAt'])));
        return ListView(children: [
          for (final r in list)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['shopName']}', style: Theme.of(context).textTheme.titleMedium),
                  Text('${r['packageName']} · ${r['price'] ?? ''}'),
                  Text('${r['ownerEmail'] ?? ''}${_ms(r['createdAt']) == 0 ? '' : ' · ${Fmt.dateTime(_ms(r['createdAt']))}'}',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => guard(context, () => cloud.resolveRequest(r['id'] as String, 'rejected')),
                      child: Text(tr('Reject')),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final shop = await cloud.db.doc('shops/${r['shopId']}').get();
                        if (!context.mounted || shop.data() == null) return;
                        await assignDialog(context, {'id': shop.id, ...shop.data()!},
                            packageId: r['packageId'] as String?, requestId: r['id'] as String);
                      },
                      child: Text(tr('Approve')),
                    ),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ settings

class _AdminSettings extends StatelessWidget {
  const _AdminSettings();

  Future<void> _branding(BuildContext context) async {
    final lic = LicenseService.instance;
    final footer = TextEditingController(text: lic.footer);
    final phone = TextEditingController(text: lic.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Branding for all shops')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: footer, decoration: InputDecoration(labelText: tr('Footer text'))),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Support phone / WhatsApp'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guard(context, () => CloudService.instance.saveBranding(footer: footer.text.trim(), phone: phone.text.trim()),
        success: 'Branding updated in every shop app');
  }

  Future<void> _twoFactor(BuildContext context) async {
    final cloud = CloudService.instance;
    if (cloud.adminDoc['totpEnabled'] == true) {
      if (await confirm(context, 'Turn off 2FA', 'The super admin panel will open without an authenticator code.')) {
        if (context.mounted) await guard(context, () => cloud.setAdminTotp(null), success: '2FA turned off');
      }
      return;
    }
    final secret = Totp.newSecret();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Turn on 2FA')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Scan with Google Authenticator, then enter the code.')),
            const SizedBox(height: 12),
            SizedBox(width: 200, height: 200, child: QrImageView(data: Totp.uri(secret: secret, account: 'BizPOS super admin'), backgroundColor: Colors.white)),
            SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
            TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: tr('6-digit code'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Turn on'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!Totp.verify(secret, code.text)) return showSnack(context, tr('Wrong code'), error: true);
    await guard(context, () => cloud.setAdminTotp(secret), success: '2FA is on');
  }

  Future<void> _offlinePassword(BuildContext context) async {
    final pw = TextEditingController();
    final pw2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('New offline code password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Used to sign offline unlock codes. Shops receive the new key the next time they are online.')),
          const SizedBox(height: 12),
          TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: tr('New password'))),
          const SizedBox(height: 12),
          TextField(controller: pw2, obscureText: true, decoration: InputDecoration(labelText: tr('Confirm password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (pw.text.length < 12 || pw.text != pw2.text) {
      return showSnack(context, tr('Use at least 12 characters and type it twice the same.'), error: true);
    }
    SuperAdminKey? key;
    final done = await guard(context, () async {
      key = await LicenseKeys.derive(pw.text);
      await CloudService.instance.addTrustedKey(key!.publicKey);
      if (!LicenseKeys.trusted.contains(key!.publicKey)) LicenseKeys.trusted.add(key!.publicKey);
    });
    if (!done || !context.mounted || key == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Password changed')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Add this to your authenticator for the offline code screen:')),
          const SizedBox(height: 12),
          SizedBox(width: 200, height: 200, child: QrImageView(data: Totp.uri(secret: key!.totpSecret, account: 'BizPOS offline codes'), backgroundColor: Colors.white)),
          SelectableText(key!.totpSecret, style: const TextStyle(fontFamily: 'monospace')),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done')))],
      ),
    );
  }

  Future<void> _accountPassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Change account password')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: current, obscureText: true, decoration: InputDecoration(labelText: tr('Current password'))),
          const SizedBox(height: 12),
          TextField(controller: next, obscureText: true, decoration: InputDecoration(labelText: tr('New password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = validatePassword(next.text);
    if (err != null) return showSnack(context, err, error: true);
    try {
      await CloudService.instance.changePassword(current.text, next.text);
      if (context.mounted) showSnack(context, tr('Password changed'));
    } catch (e) {
      if (context.mounted) showSnack(context, tr(authError(e)), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final on = cloud.adminDoc['totpEnabled'] == true;
    return ListView(children: [
      ListTile(
        leading: const Icon(Icons.brush),
        title: Text(tr('Branding for all shops')),
        subtitle: Text('${LicenseService.instance.footer} · ${Vendor.pretty(LicenseService.instance.phone)}'),
        onTap: () => _branding(context),
      ),
      const SectionTitle('Security'),
      SwitchListTile(
        secondary: const Icon(Icons.security),
        title: Text(tr('Two-factor (authenticator) for this panel')),
        subtitle: Text(tr(on ? 'On' : 'Off')),
        value: on,
        onChanged: (_) => _twoFactor(context),
      ),
      if (cloud.usesPassword)
        ListTile(leading: const Icon(Icons.password), title: Text(tr('Change account password')), onTap: () => _accountPassword(context)),
      if (!cloud.usesPassword)
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr('You sign in with Google')),
          subtitle: Text(tr('Change the password and turn on 2-Step Verification in your Google account.')),
        ),
      const SectionTitle('Offline shops'),
      ListTile(
        leading: const Icon(Icons.qr_code_2),
        title: Text(tr('Offline unlock codes')),
        subtitle: Text(tr('For shops without internet')),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminLogin())),
      ),
      ListTile(
        leading: const Icon(Icons.key),
        title: Text(tr('Change offline code password')),
        onTap: () => _offlinePassword(context),
      ),
    ]);
  }
}
