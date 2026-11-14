import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../core/packages.dart';
import '../../services/cloud_service.dart';
import '../../services/notice_service.dart';
import '../common.dart';
import '../tokens.dart';

const _kindColor = {'info': Tw.sky400, 'update': Tw.indigo500, 'offer': Tw.emerald500, 'warning': Tw.amber500};
const _kindIcon = {
  'info': Icons.campaign_rounded,
  'update': Icons.system_update_rounded,
  'offer': Icons.local_offer_rounded,
  'warning': Icons.warning_amber_rounded,
};

/// Super admin announcements shown at the top of the dashboard.
class AnnouncementBanners extends StatelessWidget {
  const AnnouncementBanners({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NoticeService.instance,
      builder: (context, _) {
        final list = NoticeService.instance.announcements;
        final offers = Access.instance.isPaid ? const <Map<String, dynamic>>[] : NoticeService.instance.offers;
        if (list.isEmpty && offers.isEmpty) return const SizedBox.shrink();
        return Column(children: [
          for (final a in list) _Banner(a: a),
          for (final o in offers.take(1)) _OfferBanner(offer: o),
        ]);
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final kind = '${a['kind'] ?? 'info'}';
    final color = _kindColor[kind] ?? Tw.sky400;
    final link = '${a['link'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(Tw.r2xl),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_kindIcon[kind] ?? Icons.campaign_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if ('${a['message'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('${a['message']}'),
              ],
              if (link.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => launchUrl(Uri.parse(link.startsWith('http') ? link : 'https://$link'),
                      mode: LaunchMode.externalApplication),
                  child: Text(tr('Open')),
                ),
            ]),
          ),
          IconButton(
            tooltip: tr('Hide'),
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => NoticeService.instance.dismiss(a['id'] as String),
          ),
        ]),
      ),
    );
  }
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.offer});
  final Map<String, dynamic> offer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OfferCard(offer: offer),
    );
  }
}

/// One offer with its claim button (dashboard and plan screen).
class OfferCard extends StatefulWidget {
  const OfferCard({super.key, required this.offer});
  final Map<String, dynamic> offer;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  bool? _claimed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    NoticeService.instance.claimed(widget.offer['id'] as String).then((v) {
      if (mounted) setState(() => _claimed = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final days = ((o['days'] ?? 0) as num).toInt();
    final need = ((o['minProducts'] ?? 0) as num).toInt();
    final end = ((o['endAt'] ?? 0) as num).toInt();
    if (_claimed == true) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(Tw.r2xl)),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.card_giftcard_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${o['title'] ?? tr('Special offer')}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          [
            if ('${o['message'] ?? ''}'.isNotEmpty) '${o['message']}',
            '${tr('Free paid plan for')} $days ${tr('days')}'
                '${need > 0 ? ' · ${tr('add at least')} $need ${tr('products')}' : ''}',
            if (end > 0) '${tr('Offer ends')} ${Fmt.date(end)}',
          ].join('\n'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Tw.indigo700),
          onPressed: _busy || _claimed == null || !CloudService.instance.signedIn
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await guard(context, () => NoticeService.instance.claim(o), success: 'Offer activated');
                  if (mounted) setState(() {
                    _busy = false;
                    if (ok) _claimed = true;
                  });
                },
          child: Text(CloudService.instance.signedIn ? tr('Get this offer') : tr('Sign in to get this offer')),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ super admin

/// Super admin: announcements to all apps and the website, and plan offers.
class NoticesAdmin extends StatelessWidget {
  const NoticesAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Announcements and offers')),
          bottom: TabBar(tabs: [Tab(text: tr('Announcements')), Tab(text: tr('Offers'))]),
        ),
        body: const TabBarView(children: [_List(collection: 'announcements'), _List(collection: 'offers')]),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () {
              final tab = DefaultTabController.of(context).index;
              tab == 0 ? _announcementForm(context, null) : _offerForm(context, null);
            },
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('New')),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.collection});
  final String collection;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: NoticeService.instance.all(collection),
      builder: (context, snap) {
        if (snap.hasError) return EmptyState(icon: Icons.error_outline, text: '${snap.error}');
        final list = snap.data;
        if (list == null) return const Center(child: CircularProgressIndicator());
        if (list.isEmpty) {
          return EmptyState(
            icon: collection == 'offers' ? Icons.local_offer_outlined : Icons.campaign_outlined,
            text: collection == 'offers' ? 'No offers yet' : 'No announcements yet',
          );
        }
        final now = nowMs();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = list[i];
            final live = NoticeService.liveAt(m, now);
            final end = ((m['endAt'] ?? 0) as num).toInt();
            final sub = collection == 'offers'
                ? '${m['packageId']} · ${m['days']} ${tr('days')} · ${tr('min')} ${m['minProducts'] ?? 0} ${tr('products')}'
                : '${tr(m['kind'] ?? 'info')} · ${tr(m['audience'] ?? 'all')}';
            return Card(
              child: ListTile(
                leading: Icon(live ? Icons.circle : Icons.circle_outlined, size: 14, color: live ? Tw.emerald500 : Tw.slate400),
                title: Text('${m['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('$sub\n${Fmt.date(((m['startAt'] ?? 0) as num).toInt())} → ${end == 0 ? tr('no end') : Fmt.date(end)}'),
                isThreeLine: true,
                onTap: () => collection == 'offers' ? _offerForm(context, m) : _announcementForm(context, m),
                trailing: collection == 'offers'
                    ? FutureBuilder<int>(
                        future: NoticeService.instance.claimCount(m['id'] as String),
                        builder: (_, s) => Text('${s.data ?? '·'}\n${tr('claimed')}', textAlign: TextAlign.center),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

/// Start date and number of days, shared by both forms.
class _When {
  _When(Map<String, dynamic>? m)
      : start = DateTime.fromMillisecondsSinceEpoch(((m?['startAt'] ?? nowMs()) as num).toInt()),
        days = TextEditingController(text: () {
          final s = ((m?['startAt'] ?? 0) as num).toInt();
          final e = ((m?['endAt'] ?? 0) as num).toInt();
          if (m == null) return '7';
          return e == 0 ? '0' : '${((e - s) / 86400000).round()}';
        }()),
        active = (m?['active'] ?? true) as bool;

  DateTime start;
  final TextEditingController days;
  bool active;

  Map<String, dynamic> get fields {
    final d = int.tryParse(days.text.trim()) ?? 0;
    final s = start.millisecondsSinceEpoch;
    return {'startAt': s, 'endAt': d <= 0 ? 0 : s + d * 86400000, 'active': active};
  }

  List<Widget> widgets(BuildContext context, StateSetter set, String daysLabel) => [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text('${tr('Starts')}: ${Fmt.date(start.millisecondsSinceEpoch)}'),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: start,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null) set(() => start = d);
          },
        ),
        NumField(controller: days, label: daysLabel),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Active')),
          value: active,
          onChanged: (v) => set(() => active = v),
        ),
      ];
}

Future<void> _announcementForm(BuildContext context, Map<String, dynamic>? m) async {
  final title = TextEditingController(text: '${m?['title'] ?? ''}');
  final message = TextEditingController(text: '${m?['message'] ?? ''}');
  final link = TextEditingController(text: '${m?['link'] ?? ''}');
  var kind = '${m?['kind'] ?? 'info'}';
  var audience = '${m?['audience'] ?? 'all'}';
  final when = _When(m);
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(m == null ? tr('New announcement') : tr('Announcement')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: InputDecoration(labelText: tr('Title'))),
            const SizedBox(height: 8),
            TextField(controller: message, maxLines: 3, decoration: InputDecoration(labelText: tr('Message'))),
            const SizedBox(height: 8),
            TextField(controller: link, decoration: InputDecoration(labelText: tr('Link (optional)'))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: InputDecoration(labelText: tr('Type')),
              items: [for (final k in NoticeService.kinds) DropdownMenuItem(value: k, child: Text(tr(k)))],
              onChanged: (v) => set(() => kind = v!),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: audience,
              decoration: InputDecoration(labelText: tr('Show to')),
              items: [
                DropdownMenuItem(value: 'all', child: Text(tr('Everyone (apps and website)'))),
                DropdownMenuItem(value: 'shops', child: Text(tr('Shop apps only'))),
                DropdownMenuItem(value: 'shoppers', child: Text(tr('Website only'))),
              ],
              onChanged: (v) => set(() => audience = v!),
            ),
            ...when.widgets(ctx, set, 'Show for how many days (0 = until turned off)'),
          ]),
        ),
        actions: [
          if (m != null)
            TextButton(
              onPressed: () async {
                if (await guard(ctx, () => NoticeService.instance.remove('announcements', m['id'] as String)) && ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: Text(tr('Delete'), style: const TextStyle(color: Tw.rose500)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) {
                showSnack(ctx, tr('Type a title'), error: true);
                return;
              }
              final ok = await guard(ctx, () => NoticeService.instance.save('announcements', m?['id'] as String?, {
                    'title': title.text.trim(),
                    'message': message.text.trim(),
                    'link': link.text.trim(),
                    'kind': kind,
                    'audience': audience,
                    ...when.fields,
                  }));
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _offerForm(BuildContext context, Map<String, dynamic>? m) async {
  final packages = await FirebaseFirestore.instance.collection('packages').get().then(
        (q) => q.docs.map((d) => Package.fromMap(d.id, d.data())).where((p) => p.active || p.id == m?['packageId']).toList(),
        onError: (_) => <Package>[],
      );
  if (!context.mounted) return;
  if (packages.isEmpty) {
    showSnack(context, tr('Save at least one package in the Packages tab first.'), error: true);
    return;
  }
  final title = TextEditingController(text: '${m?['title'] ?? ''}');
  final message = TextEditingController(text: '${m?['message'] ?? ''}');
  final days = TextEditingController(text: '${m?['days'] ?? 15}');
  final minProducts = TextEditingController(text: '${m?['minProducts'] ?? 50}');
  var packageId = packages.any((p) => p.id == m?['packageId']) ? m!['packageId'] as String : packages.first.id;
  final when = _When(m);
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(m == null ? tr('New offer') : tr('Offer')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              tr('Free shops that meet the condition can activate this package once, for the days you set.'),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(controller: title, decoration: InputDecoration(labelText: tr('Title'), hintText: tr('e.g. Add 50 products, get 15 days Pro free'))),
            const SizedBox(height: 8),
            TextField(controller: message, maxLines: 2, decoration: InputDecoration(labelText: tr('Message'))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: packageId,
              decoration: InputDecoration(labelText: tr('Package')),
              items: [for (final p in packages) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => set(() => packageId = v!),
            ),
            NumField(controller: days, label: 'Free days (1-60)'),
            NumField(controller: minProducts, label: 'Products the shop must have'),
            ...when.widgets(ctx, set, 'Offer open for how many days (0 = until turned off)'),
          ]),
        ),
        actions: [
          if (m != null)
            TextButton(
              onPressed: () async {
                if (await guard(ctx, () => NoticeService.instance.remove('offers', m['id'] as String)) && ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: Text(tr('Delete'), style: const TextStyle(color: Tw.rose500)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () async {
              final d = int.tryParse(days.text.trim()) ?? 0;
              if (title.text.trim().isEmpty) {
                showSnack(ctx, tr('Type a title'), error: true);
                return;
              }
              if (d < 1 || d > 60) {
                showSnack(ctx, tr('Free days must be 1 to 60'), error: true);
                return;
              }
              final ok = await guard(ctx, () => NoticeService.instance.save('offers', m?['id'] as String?, {
                    'title': title.text.trim(),
                    'message': message.text.trim(),
                    'packageId': packageId,
                    'days': d,
                    'minProducts': int.tryParse(minProducts.text.trim()) ?? 0,
                    ...when.fields,
                  }));
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
}
