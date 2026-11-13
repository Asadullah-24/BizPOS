import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/cloud_service.dart';
import '../../services/product_service.dart';
import '../../services/online_order_service.dart';
import '../../services/store_service.dart';
import '../common.dart';
import '../tokens.dart';
import 'account_screen.dart';
import 'plan_screen.dart';

/// The shop's page on the BizPOS website: turn it on, pick the products to
/// show, share the link, and see orders.
class OnlineStoreScreen extends StatefulWidget {
  const OnlineStoreScreen({super.key});

  @override
  State<OnlineStoreScreen> createState() => _OnlineStoreScreenState();
}

class _OnlineStoreScreenState extends State<OnlineStoreScreen> {
  String _q = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    StoreService.instance.syncAll().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: StoreService.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final store = StoreService.instance;
    final theme = Theme.of(context);
    if (!cloud.signedIn || cloud.shopId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Online store'))),
        body: EmptyState(
          icon: Icons.storefront_rounded,
          text: 'Sign in to your BizPOS account to open your online store.',
          action: FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
            child: Text(tr('Account')),
          ),
        ),
      );
    }
    final shopId = cloud.shopId!;
    final allowance = store.myAllowance;
    if (allowance == null) return const _Upsell();
    final url = StoreService.storeUrl(shopId);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Online store'))),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: store.storefront(shopId),
        builder: (context, cardSnap) {
          final card = cardSnap.data;
          final published = card?['published'] == true;
          final hidden = card?['adminHidden'] == true;
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: store.items(shopId),
            builder: (context, itemSnap) {
              final online = {for (final i in itemSnap.data ?? const <Map<String, dynamic>>[]) i['id'] as String};
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                _Header(
                  url: url,
                  published: published,
                  onToggle: (v) => guard(context, () => store.setPublished(v)),
                ),
                if (hidden)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Note(icon: Icons.visibility_off_rounded, color: Tw.rose500, text: tr('BizPOS support has hidden your store from the website. Call support.')),
                  ),
                if (!store.marketplaceOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Note(icon: Icons.construction_rounded, color: Tw.amber500, text: tr('The BizPOS website is closed for maintenance right now.')),
                  ),
                const SizedBox(height: 16),
                _OrdersTile(),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text(tr('Products on your store'), style: theme.textTheme.titleMedium)),
                  _Pill(
                    text: allowance == 0 ? '${online.length} / ∞' : '${online.length} / $allowance',
                    color: allowance > 0 && online.length >= allowance ? Tw.amber500 : Tw.indigo500,
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  allowance == 0
                      ? tr('Turn on the products customers can order.')
                      : '${tr('Your plan shows')} $allowance ${tr('products online. Ask BizPOS support for more.')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Search name, SKU or barcode'),
                LiveData<List<Product>>(
                  deps: [_q],
                  load: () => ProductService.catalogue(search: _q),
                  builder: (context, list) {
                    if (list.isEmpty) return const EmptyState(icon: Icons.inventory_2_outlined, text: 'No products yet');
                    final sorted = [...list]..sort((a, b) => (online.contains(b.id) ? 1 : 0) - (online.contains(a.id) ? 1 : 0));
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (var i = 0; i < sorted.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          SwitchListTile(
                            secondary: ProductThumb(image: sorted[i].image, name: sorted[i].name, size: 44),
                            title: Text(sorted[i].displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(Fmt.money(sorted[i].salePrice)),
                            value: online.contains(sorted[i].id),
                            onChanged: _busy.contains(sorted[i].id)
                                ? null
                                : (v) async {
                                    final p = sorted[i];
                                    setState(() => _busy.add(p.id));
                                    await guard(context,
                                        () => v ? store.publish(p, currentCount: online.length) : store.unpublish(p.id));
                                    if (mounted) setState(() => _busy.remove(p.id));
                                  },
                          ),
                        ],
                      ]),
                    );
                  },
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.url, required this.published, required this.onToggle});
  final String url;
  final bool published;
  final ValueChanged<bool> onToggle;

  Future<void> _qr(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppState.instance.businessName, textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SizedBox(width: 220, height: 220, child: QrImageView(data: url, backgroundColor: Colors.white)),
          ),
          const SizedBox(height: 12),
          Text(tr('Customers scan this to open your store.'), textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_rounded),
            label: Text(tr('Share')),
            onPressed: () async {
              final data = await QrPainter(data: url, version: QrVersions.auto, gapless: true, emptyColor: Colors.white)
                  .toImageData(900, format: ui.ImageByteFormat.png);
              if (data == null) return;
              await Share.shareXFiles([XFile.fromData(data.buffer.asUint8List(), name: 'store-qr.png', mimeType: 'image/png')], text: url);
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = AppState.instance.businessName;
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
            child: Text(published ? tr('Your store is online') : tr('Your store is offline'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Switch(
            value: published,
            onChanged: onToggle,
            activeColor: Colors.white,
            activeTrackColor: Tw.emerald500,
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            IconButton(
              tooltip: tr('Copy'),
              icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                showSnack(context, tr('Link copied'));
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _HeaderButton(
              icon: Icons.share_rounded,
              label: tr('Share link'),
              onTap: () => Share.share('${tr('Order from')} $name: $url'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _HeaderButton(icon: Icons.qr_code_2_rounded, label: tr('QR code'), onTap: () => _qr(context))),
          const SizedBox(width: 8),
          Expanded(
            child: _HeaderButton(
              icon: Icons.open_in_new_rounded,
              label: tr('Open'),
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.onTap});
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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _OrdersTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: StoreService.instance,
        builder: (context, _) => _tile(context, StoreService.instance.newOrders),
      );

  Widget _tile(BuildContext context, int n) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Tw.emerald500.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.shopping_bag_rounded, color: Tw.emerald500),
        ),
        title: Text(tr('Online orders')),
        subtitle: Text(n == 0 ? tr('No new orders') : '$n ${tr('new orders')}'),
        trailing: n == 0 ? const Icon(Icons.chevron_right_rounded) : _Pill(text: '$n', color: Tw.rose500),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen())),
      ),
    );
  }
}

class _Upsell extends StatelessWidget {
  const _Upsell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Online store'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.symmetric(horizontal: 120),
          decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 20),
        Text(tr('Sell online with your own store page'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        for (final t in [
          'Your products on the BizPOS website',
          'Customers order from their phone, no app needed',
          'New orders arrive in BizPOS with a notification',
          'Share your store link and QR code on WhatsApp',
        ])
          ListTile(leading: const Icon(Icons.check_circle_rounded, color: Tw.emerald500), title: Text(tr(t))),
        const SizedBox(height: 12),
        Text(tr('The online store comes with the paid plans.'), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.workspace_premium_rounded),
          label: Text(tr('See plans')),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
        ),
      ]),
    );
  }
}

/// Orders placed on the website.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  static const statuses = ['new', 'confirmed', 'delivered', 'cancelled'];
  static const colors = {'new': Tw.amber500, 'confirmed': Tw.sky400, 'delivered': Tw.emerald500, 'cancelled': Tw.rose500};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Online orders'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: StoreService.instance.orders(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyState(icon: Icons.error_outline, text: '${snap.error}');
          final list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return const EmptyState(icon: Icons.shopping_bag_outlined, text: 'No online orders yet');
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _OrderCard(order: list[i]),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = '${order['status'] ?? 'new'}';
    final color = OrdersScreen.colors[status] ?? Tw.slate400;
    final items = ((order['items'] as List?) ?? []).cast<Map>();
    final phone = '${order['customerPhone'] ?? ''}';
    final created = order['createdAt'] is Timestamp ? (order['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
    final cur = '${order['currency'] ?? 'Rs'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${order['customerName'] ?? ''}', style: theme.textTheme.titleMedium),
                Text('#${OnlineOrderService.code(order['id'] as String)} · ${tr('Website')}${'${order['customerUid'] ?? ''}'.isEmpty ? '' : ' · ${tr('account')}'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Tw.indigo400, fontWeight: FontWeight.w600)),
                Text('$phone${created == 0 ? '' : ' · ${Fmt.dateTime(created)}'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            _Pill(text: tr(status[0].toUpperCase() + status.substring(1)), color: color),
          ]),
          if ('${order['address'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(child: Text('${order['address']}')),
            ]),
          ],
          const Divider(height: 20),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text('${it['qty']} × ${it['name']}')),
                Text('$cur ${(((it['price'] ?? 0) as num) * ((it['qty'] ?? 1) as num)).toStringAsFixed(0)}'),
              ]),
            ),
          if ('${order['note'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${tr('Note')}: ${order['note']}', style: theme.textTheme.bodySmall),
            ),
          if (((order['coinDiscount'] ?? 0) as num) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.toll_rounded, size: 16, color: Tw.amber500),
                const SizedBox(width: 4),
                Expanded(child: Text('${tr('BizPOS coins discount (paid by BizPOS)')}: $cur ${((order['coinDiscount'] ?? 0) as num).toStringAsFixed(0)}')),
              ]),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Text(tr('Total'), style: theme.textTheme.titleSmall),
            const Spacer(),
            Text('$cur ${((order['total'] ?? 0) as num).toStringAsFixed(0)}', style: theme.textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (status == 'new')
              FilledButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(tr('Confirm')),
                onPressed: () => _act(context, 'confirmed', () => OnlineOrderService.confirm(order)),
              ),
            if (status == 'new' || status == 'confirmed')
              OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_rounded, size: 18),
                label: Text(tr('Delivered')),
                onPressed: () => _act(context, 'delivered', () => OnlineOrderService.deliver(order)),
              ),
            if (status == 'new' || status == 'confirmed')
              TextButton(
                onPressed: () async {
                  if (await confirm(context, 'Cancel order', 'Cancel this order? If it was confirmed, the stock goes back.', danger: true) &&
                      context.mounted) {
                    await _act(context, 'cancelled', () => OnlineOrderService.cancel(order));
                  }
                },
                child: Text(tr('Cancel order')),
              ),
            if (phone.isNotEmpty) ...[
              IconButton.filledTonal(
                tooltip: tr('Call'),
                icon: const Icon(Icons.call_rounded),
                onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              ),
              IconButton.filledTonal(
                tooltip: tr('WhatsApp'),
                icon: const Icon(Icons.chat_rounded),
                onPressed: () => OnlineOrderService.whatsapp(phone, OnlineOrderService.message(order, status)),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  /// Runs the status change, then offers to tell the customer on WhatsApp.
  Future<void> _act(BuildContext context, String status, Future<void> Function() run) async {
    final ok = await guard(context, run, success: status == 'confirmed' ? 'Order confirmed, sale saved' : null);
    if (!ok || !context.mounted) return;
    final phone = '${order['customerPhone'] ?? ''}';
    if (phone.isEmpty) return;
    final send = await confirm(context, 'Tell the customer?', 'Send the customer a WhatsApp message about this order?', ok: 'Send');
    if (send) await OnlineOrderService.whatsapp(phone, OnlineOrderService.message(order, status));
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}
