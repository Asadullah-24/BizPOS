import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/ids.dart';
import '../../../services/cloud_service.dart';
import '../../../services/store_service.dart';
import '../../common.dart';
import '../../tokens.dart';

/// Super admin: the public website, every online store, hot products and deals.
class StoreAdmin extends StatelessWidget {
  const StoreAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreService.instance;
    final cloud = CloudService.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _WebsiteCard(open: store.marketplaceOpen, defaultLimit: store.defaultLimit),
        const SizedBox(height: 16),
        const _BrandCard(),
        const SizedBox(height: 16),
        const _CoinsCard(),
        const SizedBox(height: 16),
        const _Featured(),
        const SizedBox(height: 16),
        const _Stores(),
      ]),
    );
  }
}

class _WebsiteCard extends StatelessWidget {
  const _WebsiteCard({required this.open, required this.defaultLimit});
  final bool open;
  final int defaultLimit;

  Future<void> _editDefault(BuildContext context) async {
    final c = TextEditingController(text: '$defaultLimit');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Default online products')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Products a paid store may show online when its package does not say. 0 = unlimited.')),
          const SizedBox(height: 12),
          TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final v = int.tryParse(c.text.trim());
    if (ok == true && v != null && context.mounted) {
      await guard(context, () => StoreService.instance.saveMarketSettings(defaultLimit: v), success: 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Tw.indigo600, Tw.violet600, Color(0xFF9333EA)]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.public_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(open ? tr('Website is open') : tr('Website is closed'),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: open,
            activeColor: Colors.white,
            activeTrackColor: Tw.emerald500,
            onChanged: (v) => guard(context, () => StoreService.instance.saveMarketSettings(open: v)),
          ),
        ]),
        Text(StoreService.webBase, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _WhiteButton(
              icon: Icons.inventory_2_rounded,
              label: '${tr('Default products')}: ${defaultLimit == 0 ? '∞' : defaultLimit}',
              onTap: () => _editDefault(context),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _WhiteButton(
              icon: Icons.open_in_new_rounded,
              label: tr('Open website'),
              onTap: () => launchUrl(Uri.parse(StoreService.webBase), mode: LaunchMode.externalApplication),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Brand name, logo and website address, changeable any time without an update.
class _BrandCard extends StatelessWidget {
  const _BrandCard();

  Future<void> _text(BuildContext context, String title, String current, String hint, Future<void> Function(String) save) async {
    final c = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok == true && context.mounted) await guard(context, () => save(c.text.trim()), success: 'Saved');
  }

  Future<void> _logo(BuildContext context) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (x == null || !context.mounted) return;
    await guard(context, () async {
      final data = await StoreService.logoFromBytes(await x.readAsBytes());
      if (data == null) throw StateError('That image could not be read.');
      await StoreService.instance.saveMarketSettings(brandLogo: data);
    }, success: 'Logo updated');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreService.instance;
    final custom = '${CloudService.instance.appSettings['websiteUrl'] ?? ''}'.trim();
    final logo = store.brandLogo;
    Widget icon(IconData i, Color c) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, color: c, size: 20),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          leading: icon(Icons.badge_rounded, Tw.indigo500),
          title: Text(tr('Brand name on the website')),
          subtitle: Text(store.brandName),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _text(context, 'Brand name on the website', store.brandName, 'BizPOS',
              (v) => StoreService.instance.saveMarketSettings(brandName: v)),
        ),
        const Divider(height: 1, indent: 64),
        ListTile(
          leading: logo.startsWith('data:image')
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(UriData.parse(logo).contentAsBytes(), width: 36, height: 36, fit: BoxFit.cover),
                )
              : icon(Icons.image_rounded, Tw.fuchsia500),
          title: Text(tr('Website logo')),
          subtitle: Text(tr(logo.isEmpty ? 'Default BizPOS logo' : 'Your logo')),
          trailing: logo.isEmpty
              ? const Icon(Icons.upload_rounded)
              : IconButton(
                  tooltip: tr('Remove'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => guard(context, () => StoreService.instance.saveMarketSettings(brandLogo: '')),
                ),
          onTap: () => _logo(context),
        ),
        const Divider(height: 1, indent: 64),
        ListTile(
          leading: icon(Icons.language_rounded, Tw.sky400),
          title: Text(tr('Website address')),
          subtitle: Text(custom.isEmpty ? '${StoreService.defaultWebBase} (${tr('free address')})' : StoreService.webBase),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _text(context, 'Website address', custom, 'https://shop.yourdomain.com',
              (v) => StoreService.instance.saveMarketSettings(websiteUrl: v)),
        ),
      ]),
    );
  }
}

/// BizPOS coins: shoppers earn coins on delivered orders and spend them as a
/// discount that BizPOS pays to the shop.
class _CoinsCard extends StatelessWidget {
  const _CoinsCard();

  Future<void> _number(BuildContext context, String title, num current, String help, Future<void> Function(num) save) async {
    final c = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(help)),
          const SizedBox(height: 12),
          TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final v = num.tryParse(c.text.trim());
    if (ok == true && v != null && v >= 0 && context.mounted) await guard(context, () => save(v), success: 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreService.instance;
    final theme = Theme.of(context);
    Widget icon(IconData i, Color c) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(i, color: c, size: 20),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SwitchListTile(
          secondary: icon(Icons.toll_rounded, Tw.amber500),
          title: Text(tr('BizPOS coins for shoppers')),
          subtitle: Text(tr(store.coinsEnabled ? 'On: shoppers earn and spend coins' : 'Off')),
          value: store.coinsEnabled,
          onChanged: (v) => guard(context, () => store.saveCoins(enabled: v)),
        ),
        const Divider(height: 1, indent: 64),
        ListTile(
          leading: icon(Icons.add_circle_rounded, Tw.emerald500),
          title: Text(tr('Coins earned per Rs 100')),
          subtitle: Text('${store.coinsPerHundred}'),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _number(context, 'Coins earned per Rs 100', store.coinsPerHundred,
              'Given when the shop marks an order delivered.', (v) => store.saveCoins(perHundred: v)),
        ),
        const Divider(height: 1, indent: 64),
        ListTile(
          leading: icon(Icons.payments_rounded, Tw.sky400),
          title: Text(tr('Value of 1 coin (Rs)')),
          subtitle: Text('Rs ${store.coinValue}'),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _number(context, 'Value of 1 coin (Rs)', store.coinValue, 'Discount for each coin spent.', (v) => store.saveCoins(value: v)),
        ),
        const Divider(height: 1, indent: 64),
        ListTile(
          leading: icon(Icons.percent_rounded, Tw.violet500),
          title: Text(tr('Most of an order paid with coins')),
          subtitle: Text('${store.coinsMaxPercent}%'),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _number(context, 'Most of an order paid with coins', store.coinsMaxPercent,
              'Percent of the order total.', (v) => store.saveCoins(maxPercent: v)),
        ),
        const Divider(height: 1),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: store.coinOrders(),
          builder: (context, snap) {
            final list = (snap.data ?? const []).where((o) => o['status'] != 'cancelled').toList();
            final total = list.fold<num>(0, (a, o) => a + ((o['coinDiscount'] ?? 0) as num));
            final byShop = <String, num>{};
            for (final o in list.where((o) => o['status'] == 'delivered')) {
              final k = '${o['shopName'] ?? o['shopId']}';
              byShop[k] = (byShop[k] ?? 0) + ((o['coinDiscount'] ?? 0) as num);
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr('Coin discounts given')}: Rs ${total.toStringAsFixed(0)} (${list.length} ${tr('orders')})',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(tr('BizPOS pays these to the shops. Delivered orders by shop:'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                for (final e in byShop.entries) Text('• ${e.key}: Rs ${e.value.toStringAsFixed(0)}'),
              ]),
            );
          },
        ),
      ]),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  const _WhiteButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
}

class _Featured extends StatelessWidget {
  const _Featured();

  Future<void> _random(BuildContext context) async {
    final c = TextEditingController(text: '8');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Random hot products')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Replaces the hot list with random products from online stores.')),
          const SizedBox(height: 12),
          TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('How many'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Pick'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var n = 0;
    final done = await guard(context, () async => n = await StoreService.instance.randomHot(int.tryParse(c.text) ?? 8));
    if (done && context.mounted) showSnack(context, '$n ${tr('hot products picked')}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr('Hot products and deals'), style: theme.textTheme.titleMedium)),
            TextButton.icon(onPressed: () => _random(context), icon: const Icon(Icons.casino_rounded, size: 18), label: Text(tr('Random'))),
          ]),
          Text(tr('Shown on the website home. Add more from a store below.'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: StoreService.instance.featured(),
            builder: (context, snap) {
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('Nothing featured yet.'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              return Column(children: [
                for (final f in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _Thumb(data: '${f['thumb'] ?? ''}', name: '${f['name']}'),
                    title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f['storeName']} · ${f['kind'] == 'deal' ? '${tr('Deal')} ${f['currency']} ${f['dealPrice']}' : tr('Hot')}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => guard(context, () => StoreService.instance.unfeature(f['id'] as String)),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _Stores extends StatelessWidget {
  const _Stores();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StoreService.instance.allStorefronts(),
      builder: (context, snap) {
        final list = [...(snap.data ?? const <Map<String, dynamic>>[])]
          ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
        final now = nowMs();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${tr('Online stores')} (${list.length})', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Text(tr('No shop has opened an online store yet.'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          for (final s in list) ...[
            Card(
              child: ListTile(
                title: Text('${s['name'] ?? ''}'),
                subtitle: Text(_status(s, now)),
                leading: Icon(Icons.storefront_rounded, color: _visible(s, now) ? Tw.emerald500 : Tw.slate400),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreAdminDetail(shopId: s['id'] as String))),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ]);
      },
    );
  }
}

bool _visible(Map<String, dynamic> s, int now) {
  final until = ((s['paidUntil'] ?? 0) as num).toInt();
  return s['published'] == true && s['adminHidden'] != true && (until == 0 || until > now);
}

String _status(Map<String, dynamic> s, int now) {
  if (s['adminHidden'] == true) return tr('Hidden by you');
  if (s['published'] != true) return tr('Turned off by the shop');
  final until = ((s['paidUntil'] ?? 0) as num).toInt();
  if (until != 0 && until < now) return tr('Plan expired, not shown');
  return '${tr('Live on the website')}${until == 0 ? '' : ' · ${tr('until')} ${Fmt.date(until)}'}';
}

/// One store: show/hide, product limit, hot/deal products, orders.
class StoreAdminDetail extends StatelessWidget {
  const StoreAdminDetail({super.key, required this.shopId});
  final String shopId;

  Future<void> _limit(BuildContext context, num? current) async {
    final c = TextEditingController(text: current == null ? '' : '${current.toInt()}');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Online products for this store')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('0 = unlimited. "Follow plan" uses the package, or the default.')),
          const SizedBox(height: 12),
          TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('Follow plan'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Save'))),
        ],
      ),
    );
    if (r == null || !context.mounted) return;
    await guard(context, () => StoreService.instance.setOnlineLimit(shopId, r.isEmpty ? null : int.tryParse(r)), success: 'Saved');
  }

  Future<void> _deal(BuildContext context, Map<String, dynamic> store, Map<String, dynamic> item) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr('Deal price for')} ${item['name']}'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(labelText: '${tr('Normal price')}: ${item['price']}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final price = double.tryParse(c.text.trim());
    if (ok == true && price != null && context.mounted) {
      await guard(context, () => StoreService.instance.feature(store, item, kind: 'deal', dealPrice: price), success: 'Added to deals');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudService.instance;
    final theme = Theme.of(context);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cloud.db.doc('storefronts/$shopId').snapshots(),
      builder: (context, snap) {
        final s = snap.data?.data();
        if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        final store = {'id': shopId, ...s};
        final now = nowMs();
        return Scaffold(
          appBar: AppBar(title: Text('${s['name'] ?? ''}'), actions: [
            IconButton(
              tooltip: tr('Open store'),
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => launchUrl(Uri.parse(StoreService.storeUrl(shopId)), mode: LaunchMode.externalApplication),
            ),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(Icons.circle, size: 14, color: _visible(s, now) ? Tw.emerald500 : Tw.rose500),
                  title: Text(_status(s, now)),
                  subtitle: Text('${s['phone'] ?? ''}  ${s['city'] ?? ''}'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(tr('Show on the website')),
                  subtitle: Text(tr('Turn off to hide this store, whatever the shop does.')),
                  value: s['adminHidden'] != true,
                  onChanged: (v) => guard(context, () => StoreService.instance.setHidden(shopId, !v)),
                ),
                const Divider(height: 1),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: cloud.db.doc('shops/$shopId').snapshots(),
                  builder: (context, shopSnap) {
                    final shop = shopSnap.data?.data();
                    final allowance = StoreService.instance.allowanceFor(shop);
                    return ListTile(
                      leading: const Icon(Icons.inventory_2_rounded, color: Tw.amber500),
                      title: Text(tr('Online products allowed')),
                      subtitle: Text(allowance == null
                          ? tr('Not allowed (free plan)')
                          : (allowance == 0 ? tr('Unlimited') : '$allowance')),
                      trailing: const Icon(Icons.edit_rounded),
                      onTap: () => _limit(context, shop?['onlineLimit'] as num?),
                    );
                  },
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(tr('Products online'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: StoreService.instance.items(shopId),
              builder: (context, itemsSnap) {
                final items = itemsSnap.data ?? const [];
                if (items.isEmpty) return Text(tr('No products online yet.'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant));
                return Card(
                  child: Column(children: [
                    for (final i in items)
                      ListTile(
                        leading: _Thumb(data: '${i['thumb'] ?? ''}', name: '${i['name']}'),
                        title: Text('${i['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${s['currency'] ?? 'Rs'} ${i['price']}${i['inStock'] == false ? ' · ${tr('Out of stock')}' : ''}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'hot') guard(context, () => StoreService.instance.feature(store, i, kind: 'hot'), success: 'Added to hot');
                            if (v == 'deal') _deal(context, store, i);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'hot', child: Text(tr('Add to hot'))),
                            PopupMenuItem(value: 'deal', child: Text(tr('Add to deals'))),
                          ],
                        ),
                      ),
                  ]),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(tr('Orders'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: StoreService.instance.ordersOf(shopId),
              builder: (context, o) {
                final orders = o.data ?? const [];
                if (orders.isEmpty) return Text(tr('No orders yet.'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant));
                final total = orders.where((x) => x['status'] != 'cancelled').fold<num>(0, (a, x) => a + ((x['total'] ?? 0) as num));
                return Card(
                  child: Column(children: [
                    ListTile(
                      title: Text('${orders.length} ${tr('orders')}'),
                      trailing: Text('${s['currency'] ?? 'Rs'} ${total.toStringAsFixed(0)}', style: theme.textTheme.titleMedium),
                    ),
                    for (final x in orders.take(20))
                      ListTile(
                        dense: true,
                        title: Text('${x['customerName']} · ${x['customerPhone']}'),
                        subtitle: Text('${x['status']} · ${(x['items'] as List?)?.length ?? 0} ${tr('items')}'),
                        trailing: Text('${((x['total'] ?? 0) as num).toStringAsFixed(0)}'),
                      ),
                  ]),
                );
              },
            ),
          ]),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.data, required this.name});
  final String data;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (data.startsWith('data:image')) {
      try {
        final bytes = UriData.parse(data).contentAsBytes();
        return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover));
      } catch (_) {}
    }
    return ProductThumb(image: null, name: name, size: 44);
  }
}

/// Opens the mail app to write to one owner or to every owner.
Future<void> emailOwners(BuildContext context, List<String> emails, {String subject = 'BizPOS'}) async {
  final list = emails.where((e) => e.contains('@')).toSet().toList();
  if (list.isEmpty) return showSnack(context, tr('No owner emails yet.'), error: true);
  final uri = list.length == 1
      ? Uri(scheme: 'mailto', path: list.first, query: 'subject=${Uri.encodeComponent(subject)}')
      : Uri(scheme: 'mailto', query: 'bcc=${list.join(',')}&subject=${Uri.encodeComponent(subject)}');
  if (!await launchUrl(uri) && context.mounted) showSnack(context, tr('No email app found.'), error: true);
}
