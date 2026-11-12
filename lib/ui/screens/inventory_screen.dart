import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/inventory_service.dart';
import '../../services/product_service.dart';
import '../common.dart';

Future<void> showAdjustStock(BuildContext context, Product p) async {
  if (!AppState.instance.can(Perm.inventory)) {
    return showSnack(context, tr('You do not have permission to adjust stock.'), error: true);
  }
  var mode = 'add';
  final qty = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(p.displayName),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${tr('Current stock')}: ${Fmt.qty(p.stock)} ${p.unit ?? ''}'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'add', label: Text(tr('Add')), icon: const Icon(Icons.add)),
                ButtonSegment(value: 'remove', label: Text(tr('Remove')), icon: const Icon(Icons.remove)),
                ButtonSegment(value: 'set', label: Text(tr('Count')), icon: const Icon(Icons.fact_check_outlined)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setS(() => mode = s.first),
            ),
            const SizedBox(height: 12),
            NumField(controller: qty, label: mode == 'set' ? 'Counted quantity' : 'Quantity', autofocus: true),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: tr('Reason (damaged, expired, recount...)')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final q = Fmt.parse(qty.text);
  if (q < 0 || (q == 0 && mode != 'set')) return;
  await guard(context, () => InventoryService.adjust(
        productId: p.id,
        mode: mode,
        qty: q,
        note: note.text.trim(),
        employeeId: AppState.instance.user?.id,
      ), success: 'Stock updated');
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.lowOnly = false});
  final bool lowOnly;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _q = '';
  late bool _low = widget.lowOnly;

  Future<(List<Product>, double)> _load() async {
    var list = await ProductService.sellable(search: _q);
    list = list.where((p) => p.trackStock).toList();
    if (_low) list = list.where((p) => p.stock <= p.lowStock).toList();
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final value = await Db.instance.s.scalar(
      'SELECT COALESCE(SUM(stock * cost_price), 0) FROM products WHERE deleted_at IS NULL AND has_variants = 0 AND track_stock = 1 AND stock > 0',
    );
    return (list, value);
  }

  @override
  Widget build(BuildContext context) {
    final canSeeCost = AppState.instance.can(Perm.reports);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Inventory'))),
      body: Column(children: [
        SearchField(onChanged: (v) => setState(() => _q = v)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            FilterChip(
              label: Text(tr('Low stock only')),
              selected: _low,
              onSelected: (v) => setState(() => _low = v),
            ),
          ]),
        ),
        Expanded(
          child: LiveData<(List<Product>, double)>(
            deps: [_q, _low],
            load: _load,
            builder: (ctx, data) {
              final list = data.$1;
              return Column(children: [
                if (canSeeCost)
                  ListTile(
                    dense: true,
                    title: Text(tr('Stock value at cost')),
                    trailing: Text(Fmt.money(data.$2), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                Expanded(
                  child: list.isEmpty
                      ? EmptyState(icon: Icons.inventory, text: _low ? 'No low-stock items' : 'Nothing here yet')
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                          itemBuilder: (_, i) {
                            final p = list[i];
                            final low = p.stock <= p.lowStock;
                            return ListTile(
                              leading: ProductThumb(image: p.image, name: p.name),
                              title: Text(p.displayName),
                              subtitle: Text('${tr('Alert at')} ${Fmt.qty(p.lowStock)}${p.sku == null ? '' : ' · ${p.sku}'}'),
                              trailing: Text(
                                '${Fmt.qty(p.stock)} ${p.unit ?? ''}',
                                style: TextStyle(fontWeight: FontWeight.w700, color: low ? Colors.red : null),
                              ),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockHistoryScreen(product: p))),
                              onLongPress: () => showAdjustStock(context, p),
                            );
                          },
                        ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class StockHistoryScreen extends StatelessWidget {
  const StockHistoryScreen({super.key, required this.product});
  final Product product;

  static const _labels = {
    'opening': 'Opening stock',
    'sale': 'Sold',
    'purchase': 'Purchased',
    'adjustment': 'Adjustment',
    'return': 'Returned by customer',
    'cancel': 'Sale cancelled',
  };

  @override
  Widget build(BuildContext context) {
    return LiveData<(Product?, List<DbRow>)>(
      load: () async => (await ProductService.byId(product.id), await InventoryService.movements(product.id)),
      builder: (context, data) {
        final p = data.$1 ?? product;
        return Scaffold(
          appBar: AppBar(title: Text(p.displayName)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showAdjustStock(context, p),
            icon: const Icon(Icons.tune),
            label: Text(tr('Adjust stock')),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            ListTile(
              title: Text(tr('Current stock')),
              trailing: Text('${Fmt.qty(p.stock)} ${p.unit ?? ''}', style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(),
            for (final m in data.$2)
              ListTile(
                leading: Icon(asDouble(m['qty']) >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    color: asDouble(m['qty']) >= 0 ? Colors.green : Colors.red),
                title: Text(tr(_labels[m['type']] ?? '${m['type']}')),
                subtitle: Text([Fmt.dateTime(asInt(m['created_at'])), if ((m['note'] ?? '') != '') m['note'] as String].join(' · ')),
                trailing: Text(
                  '${asDouble(m['qty']) > 0 ? '+' : ''}${Fmt.qty(asDouble(m['qty']))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ]),
        );
      },
    );
  }
}
