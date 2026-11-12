import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/invoice_service.dart';
import '../../services/ledger_service.dart';
import '../../services/product_service.dart';
import '../../services/purchase_service.dart';
import '../common.dart';
import 'parties_screen.dart';
import 'product_form.dart';
import 'scanner_screen.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Purchases'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(tr('Receive stock')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseForm())),
      ),
      body: LiveData<List<DbRow>>(
        load: () => PurchaseService.list(limit: 500),
        builder: (ctx, list) => list.isEmpty
            ? const EmptyState(icon: Icons.local_shipping_outlined, text: 'Record stock you buy from suppliers here.')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final due = asDouble(p['total']) - asDouble(p['paid']);
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.local_shipping, size: 20)),
                    title: Text(p['purchase_no'] as String),
                    subtitle: Text([
                      (p['supplier_name'] as String?) ?? tr('No supplier'),
                      Fmt.date(asInt(p['created_at'])),
                      if (due > 0.009) '${tr('Due')} ${Fmt.money(due)}',
                    ].join(' · ')),
                    trailing: Text(Fmt.money(asDouble(p['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(id: p['id'] as String))),
                  );
                },
              ),
      ),
    );
  }
}

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key});

  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _LineCtl {
  _LineCtl(this.line)
      : qty = TextEditingController(text: Fmt.qty(line.qty)),
        cost = TextEditingController(text: numText(line.unitCost));
  final PurchaseLine line;
  final TextEditingController qty;
  final TextEditingController cost;
}

class _PurchaseFormState extends State<PurchaseForm> {
  Party? _supplier;
  final _ref = TextEditingController();
  final _discount = TextEditingController();
  final _tax = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  final List<_LineCtl> _lines = [];
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _busy = false;

  double get _subtotal => _lines.fold<double>(0, (a, l) => a + Fmt.parse(l.qty.text) * Fmt.parse(l.cost.text));
  double get _total => _subtotal - Fmt.parse(_discount.text) + Fmt.parse(_tax.text);

  @override
  void initState() {
    super.initState();
    LedgerService.defaultAccount().then((a) {
      if (mounted) setState(() => _accountId = a?.id);
    });
  }

  void _addProduct(Product p) {
    for (final l in _lines) {
      if (l.line.productId == p.id) {
        setState(() => l.qty.text = Fmt.qty(Fmt.parse(l.qty.text) + 1));
        return;
      }
    }
    setState(() => _lines.add(_LineCtl(PurchaseLine(
          productId: p.id,
          name: p.displayName,
          qty: 1,
          unitCost: p.costPrice,
          trackStock: p.trackStock,
        ))));
  }

  Future<void> _pickProduct() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ProductPicker(),
    );
    if (p != null) _addProduct(p);
  }

  Future<void> _scan() async {
    final code = await ScannerScreen.scan(context);
    if (code == null) return;
    final p = await ProductService.findByCode(code);
    if (!mounted) return;
    if (p == null) return showSnack(context, '${tr('No product with code')} $code', error: true);
    _addProduct(p);
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return showSnack(context, tr('Add at least one item.'), error: true);
    for (final l in _lines) {
      l.line.qty = Fmt.parse(l.qty.text);
      l.line.unitCost = Fmt.parse(l.cost.text);
    }
    final valid = _lines.map((l) => l.line).where((l) => l.qty > 0).toList();
    setState(() => _busy = true);
    final now = DateTime.now();
    final isToday = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    final ok = await guard(context, () async {
      await PurchaseService.create(
        supplierId: _supplier?.id,
        refNo: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        lines: valid,
        discount: Fmt.parse(_discount.text),
        tax: Fmt.parse(_tax.text),
        paid: Fmt.parse(_paid.text),
        accountId: _accountId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        date: isToday ? null : DateTime(_date.year, _date.month, _date.day, 12).millisecondsSinceEpoch,
      );
    }, success: 'Purchase saved. Stock updated.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Receive stock')), actions: [
        IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(_supplier?.name ?? tr('Choose supplier')),
            subtitle: _supplier == null ? Text(tr('Needed when buying on credit')) : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final p = await pickParty(context, 'supplier');
              if (p != null) setState(() => _supplier = p);
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _ref, decoration: InputDecoration(labelText: tr('Supplier invoice no')))),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(Fmt.date(_date.millisecondsSinceEpoch)),
              onPressed: () async {
                final d = await pickDate(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
        ]),
        SectionTitle('Items', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('New product')),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm())),
          ),
          FilledButton.tonalIcon(onPressed: _pickProduct, icon: const Icon(Icons.search), label: Text(tr('Add item'))),
        ])),
        if (_lines.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, text: 'Add the items you received.'),
        for (var i = 0; i < _lines.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text(_lines[i].line.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
                ]),
                Row(children: [
                  Expanded(child: NumField(controller: _lines[i].qty, label: 'Quantity', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: NumField(controller: _lines[i].cost, label: 'Unit cost', onChanged: (_) => setState(() {}))),
                ]),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: NumField(controller: _discount, label: 'Discount', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 12),
          Expanded(child: NumField(controller: _tax, label: 'Tax / freight', onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 12),
        KeyValue('Subtotal', Fmt.money(_subtotal)),
        KeyValue('Total', Fmt.money(_total), bold: true),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: NumField(controller: _paid, label: 'Paid now', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          TextButton(onPressed: () => setState(() => _paid.text = Fmt.qty(Fmt.round(_total))), child: Text(tr('Full'))),
        ]),
        const SizedBox(height: 12),
        if (Fmt.parse(_paid.text) > 0)
          AccountPicker(value: _accountId, label: 'Paid from', onChanged: (a) => setState(() => _accountId = a?.id)),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: InputDecoration(labelText: tr('Note'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Save purchase'))),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker();

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (ctx, scroll) => Column(children: [
          SearchField(onChanged: (v) => setState(() => _q = v)),
          Expanded(
            child: LiveData<List<Product>>(
              deps: [_q],
              load: () => ProductService.sellable(search: _q),
              builder: (ctx, list) => ListView.builder(
                controller: scroll,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return ListTile(
                    leading: ProductThumb(image: p.image, name: p.name, size: 40),
                    title: Text(p.displayName),
                    subtitle: Text('${tr('Stock')} ${Fmt.qty(p.stock)} · ${tr('Cost')} ${Fmt.money(p.costPrice)}'),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ),
        ]),
      );
}

class PurchaseDetailScreen extends StatelessWidget {
  const PurchaseDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return LiveData<(DbRow?, List<DbRow>)>(
      load: () async => (await PurchaseService.purchase(id), await PurchaseService.items(id)),
      builder: (context, d) {
        final p = d.$1;
        if (p == null || p['deleted_at'] != null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.local_shipping, text: 'Not found'));
        }
        final due = asDouble(p['total']) - asDouble(p['paid']);
        return Scaffold(
          appBar: AppBar(title: Text(p['purchase_no'] as String), actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => guard(context, () async => InvoicePdf.share(await InvoiceData.forPurchase(id))),
            ),
            PopupMenuButton<String>(
              onSelected: (_) async {
                if (!await confirm(context, 'Void purchase', 'Remove this purchase, its stock and its payment?', danger: true)) return;
                if (!context.mounted) return;
                final ok = await guard(context, () => PurchaseService.voidPurchase(id), success: 'Purchase voided');
                if (ok && context.mounted) Navigator.pop(context);
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'void', child: Text(tr('Void purchase')))],
            ),
          ]),
          body: ListView(children: [
            ListTile(
              title: Text((p['supplier_name'] as String?) ?? tr('No supplier')),
              subtitle: Text([Fmt.dateTime(asInt(p['created_at'])), if (p['ref_no'] != null) '${tr('Ref')} ${p['ref_no']}'].join(' · ')),
            ),
            const Divider(),
            for (final i in d.$2)
              ListTile(
                dense: true,
                title: Text(i['name'] as String),
                subtitle: Text('${Fmt.qty(asDouble(i['qty']))} x ${Fmt.money(asDouble(i['unit_cost']))}'),
                trailing: Text(Fmt.money(asDouble(i['total']))),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                KeyValue('Subtotal', Fmt.money(asDouble(p['subtotal']))),
                if (asDouble(p['discount']) > 0) KeyValue('Discount', '-${Fmt.money(asDouble(p['discount']))}'),
                if (asDouble(p['tax']) > 0) KeyValue('Tax / freight', Fmt.money(asDouble(p['tax']))),
                KeyValue('Total', Fmt.money(asDouble(p['total'])), bold: true),
                KeyValue('Paid', Fmt.money(asDouble(p['paid']))),
                if (due > 0.009) KeyValue('Balance due', Fmt.money(due), bold: true, color: Theme.of(context).colorScheme.error),
                if (p['note'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p['note'] as String)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
