import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../services/invoice_service.dart';
import '../../services/ledger_service.dart';
import '../../services/printer_service.dart';
import '../../services/return_service.dart';
import '../../services/sales_service.dart';
import '../common.dart';
import 'pos_screen.dart';

class _SaleView {
  _SaleView(this.sale, this.items, this.payments, this.returns, this.returned);
  final DbRow? sale;
  final List<DbRow> items;
  final List<DbRow> payments;
  final List<DbRow> returns;
  final Map<String, double> returned;
}

class SaleDetailScreen extends StatelessWidget {
  const SaleDetailScreen({super.key, required this.saleId});
  final String saleId;

  Future<_SaleView> _load() async => _SaleView(
        await SalesService.sale(saleId),
        await SalesService.items(saleId),
        await SalesService.payments(saleId),
        await ReturnService.forSale(saleId),
        await SalesService.returnedQty(saleId),
      );

  Future<void> _cancel(BuildContext context) async {
    final reason = await promptText(context, 'Cancel sale', label: 'Reason');
    if (reason == null || !context.mounted) return;
    if (!await confirm(context, 'Cancel sale',
        'Stock goes back and every payment is refunded to its account. This cannot be undone.', danger: true)) {
      return;
    }
    if (!context.mounted) return;
    await guard(context, () => SalesService.cancelSale(saleId, reason: reason), success: 'Sale cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return LiveData<_SaleView>(
      load: _load,
      builder: (context, v) {
        final s = v.sale;
        if (s == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.receipt_long, text: 'Not found'));
        final cancelled = s['status'] == 'cancelled';
        final total = asDouble(s['total']);
        final paid = asDouble(s['paid']);
        final returnedAll = v.items.every((i) => (v.returned[i['id']] ?? 0) >= asDouble(i['qty']) - 0.0001);
        final canReturn = !cancelled && !returnedAll && app.allowed(Mod.returns, Perm.returns);
        return Scaffold(
          appBar: AppBar(
            title: Text(s['invoice_no'] as String),
            actions: [
              IconButton(
                tooltip: tr('Print'),
                icon: const Icon(Icons.print),
                onPressed: () => guard(context, () async => PrinterService.printReceipt(await InvoiceData.forSale(saleId))),
              ),
              IconButton(
                tooltip: tr('Share'),
                icon: const Icon(Icons.share),
                onPressed: () => guard(context, () async => InvoicePdf.share(await InvoiceData.forSale(saleId))),
              ),
              if (!cancelled && v.returns.isEmpty && app.can(Perm.salesCancel))
                PopupMenuButton<String>(
                  onSelected: (k) => _cancel(context),
                  itemBuilder: (_) => [PopupMenuItem(value: 'cancel', child: Text(tr('Cancel sale')))],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            if (cancelled)
              Container(
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(tr('This sale was cancelled.'), textAlign: TextAlign.center),
              ),
            ListTile(
              title: Text((s['customer_name'] as String?) ?? tr('Walk-in customer')),
              subtitle: Text([
                Fmt.dateTime(asInt(s['created_at'])),
                if (s['employee_name'] != null) '${tr('By')} ${s['employee_name']}',
              ].join(' · ')),
            ),
            const Divider(),
            for (final i in v.items)
              ListTile(
                dense: true,
                title: Text(i['name'] as String),
                subtitle: Text([
                  '${Fmt.qty(asDouble(i['qty']))} x ${Fmt.money(asDouble(i['unit_price']))}',
                  if (asDouble(i['discount']) > 0.0001) '${tr('Discount')} ${Fmt.money(asDouble(i['discount']))}',
                  if ((v.returned[i['id']] ?? 0) > 0) '${tr('Returned')} ${Fmt.qty(v.returned[i['id']]!)}',
                ].join(' · ')),
                trailing: Text(Fmt.money(asDouble(i['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                KeyValue('Subtotal', Fmt.money(asDouble(s['subtotal']))),
                if (asDouble(s['discount']) > 0) KeyValue('Discount', '-${Fmt.money(asDouble(s['discount']))}'),
                if (asDouble(s['tax']) > 0) KeyValue('Tax', Fmt.money(asDouble(s['tax']))),
                KeyValue('Total', Fmt.money(total), bold: true),
                for (final p in v.payments)
                  KeyValue(
                    '${p['direction'] == 'in' ? '' : '${tr('Refund')} '}${p['account_name'] ?? ''}',
                    '${p['direction'] == 'in' ? '' : '-'}${Fmt.money(asDouble(p['amount']))}',
                  ),
                if (asDouble(s['credit_applied']) > 0) KeyValue('Exchange credit', Fmt.money(asDouble(s['credit_applied']))),
                if (!cancelled && total - paid > 0.009)
                  KeyValue('Balance due', Fmt.money(total - paid), bold: true, color: Theme.of(context).colorScheme.error),
                if (s['note'] != null && (s['note'] as String).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(s['note'] as String)),
              ]),
            ),
            if (v.returns.isNotEmpty) ...[
              const SectionTitle('Returns'),
              for (final r in v.returns)
                ListTile(
                  leading: const Icon(Icons.assignment_return),
                  title: Text('${r['return_no']} · ${r['type']}'),
                  subtitle: Text(Fmt.dateTime(asInt(r['created_at']))),
                  trailing: Text('-${Fmt.money(asDouble(r['total']))}'),
                ),
            ],
            const SizedBox(height: 16),
            if (canReturn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.assignment_return),
                  label: Text(tr('Return / exchange items')),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReturnForm(sale: s, items: v.items, returned: v.returned)),
                  ),
                ),
              ),
            if (!cancelled && total - paid > 0.009 && s['customer_id'] != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  tr('To collect the balance, open the customer and tap Receive payment.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ]),
        );
      },
    );
  }
}

class ReturnForm extends StatefulWidget {
  const ReturnForm({super.key, required this.sale, required this.items, required this.returned});
  final DbRow sale;
  final List<DbRow> items;
  final Map<String, double> returned;

  @override
  State<ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<ReturnForm> {
  late final List<ReturnLineInput> _lines = [
    for (final i in widget.items)
      if (asDouble(i['qty']) - (widget.returned[i['id']] ?? 0) > 0.0001) ReturnLineInput(saleItem: i, qty: 0),
  ];
  String _type = 'refund';
  String? _accountId;
  final _note = TextEditingController();
  bool _busy = false;

  double _left(ReturnLineInput l) => asDouble(l.saleItem['qty']) - (widget.returned[l.saleItem['id']] ?? 0);
  double get _value => _lines.fold<double>(
      0, (a, l) => a + asDouble(l.saleItem['total']) / asDouble(l.saleItem['qty']) * l.qty);

  @override
  void initState() {
    super.initState();
    LedgerService.defaultAccount().then((a) {
      if (mounted) setState(() => _accountId = a?.id);
    });
  }

  Future<void> _submit() async {
    if (_type == 'refund' && _accountId == null) return showSnack(context, tr('Choose the refund account.'), error: true);
    setState(() => _busy = true);
    try {
      final r = await ReturnService.create(
        saleId: widget.sale['id'] as String,
        lines: _lines,
        type: _type,
        refundAccountId: _accountId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      if (_type == 'exchange') {
        PosController.instance.startExchange(
          returnId: r.id,
          credit: r.total,
          customerId: r.customerId,
          customerName: widget.sale['customer_name'] as String?,
        );
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
        showSnack(context, '${tr('Exchange credit')} ${Fmt.money(r.total)}. ${tr('Add the new items.')}');
      } else {
        Navigator.pop(context);
        showSnack(context, tr('Return saved'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, tr(errorText(e)), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomer = widget.sale['customer_id'] != null;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Return')} · ${widget.sale['invoice_no']}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final l in _lines)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.saleItem['name'] as String),
                  subtitle: Text('${tr('Can return')} ${Fmt.qty(_left(l))}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: l.qty <= 0 ? null : () => setState(() => l.qty = (l.qty - 1).clamp(0, _left(l)).toDouble()),
                    ),
                    Text(Fmt.qty(l.qty), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: l.qty >= _left(l) ? null : () => setState(() => l.qty = (l.qty + 1).clamp(0, _left(l)).toDouble()),
                    ),
                  ]),
                ),
                if (l.saleItem['product_id'] != null)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: l.restock,
                    onChanged: (v) => setState(() => l.restock = v ?? true),
                    title: Text(tr('Put back in stock')),
                  ),
              ]),
            ),
          ),
        const SectionTitle('What does the customer get?'),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'refund', label: Text(tr('Refund')), icon: const Icon(Icons.payments_outlined)),
            if (hasCustomer) ButtonSegment(value: 'credit', label: Text(tr('Credit')), icon: const Icon(Icons.account_balance_wallet_outlined)),
            ButtonSegment(value: 'exchange', label: Text(tr('Exchange')), icon: const Icon(Icons.swap_horiz)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 12),
        if (_type == 'refund') AccountPicker(value: _accountId, label: 'Refund from', onChanged: (a) => setState(() => _accountId = a?.id)),
        if (_type == 'credit') Text(tr('The amount is taken off what the customer owes.')),
        if (_type == 'exchange') Text(tr('The value becomes credit for a new sale. Pick the new items next.')),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: InputDecoration(labelText: tr('Reason / note'))),
        const SizedBox(height: 16),
        KeyValue('Return value', Fmt.money(Fmt.round(_value)), bold: true),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _value <= 0 ? null : _submit,
          child: Text(tr(_type == 'exchange' ? 'Continue to exchange' : 'Save return')),
        ),
      ]),
    );
  }
}
