import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/cart.dart';
import '../../services/ledger_service.dart';
import '../../services/sales_service.dart';
import '../common.dart';
import 'parties_screen.dart';
import 'pos_screen.dart';
import 'receipt_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _PayRow {
  _PayRow(this.account, double amount) : controller = TextEditingController(text: amount <= 0 ? '' : Fmt.qty(amount));
  Account? account;
  final TextEditingController controller;
  double get amount => Fmt.parse(controller.text);
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final pos = PosController.instance;
  List<Account> _accounts = [];
  final List<_PayRow> _rows = [];
  final _note = TextEditingController();
  bool _busy = false;

  double get _total => Fmt.round(pos.totals.total);
  double get _credit => pos.cart.exchangeCredit > _total ? _total : pos.cart.exchangeCredit;
  double get _due => _total - _credit;
  double get _entered => _rows.fold<double>(0, (a, r) => a + r.amount);

  @override
  void initState() {
    super.initState();
    _note.text = pos.cart.note;
    _load();
  }

  Future<void> _load() async {
    final acc = await LedgerService.accounts();
    if (!mounted) return;
    setState(() {
      _accounts = acc;
      final def = acc.where((a) => a.isDefault).firstOrNull ?? acc.firstOrNull;
      _rows.add(_PayRow(def, _due));
    });
  }

  void _addRow() {
    final left = _due - _entered;
    final used = _rows.map((r) => r.account?.id).toSet();
    final next = _accounts.where((a) => !used.contains(a.id)).firstOrNull ?? _accounts.firstOrNull;
    setState(() => _rows.add(_PayRow(next, left > 0 ? left : 0)));
  }

  List<double> _quickAmounts() {
    final due = _due;
    if (due <= 0) return [];
    final out = <double>{due};
    for (final step in [10, 50, 100, 500, 1000, 5000]) {
      final v = (due / step).ceil() * step.toDouble();
      if (v > due) out.add(v);
      if (out.length >= 5) break;
    }
    return out.toList()..sort();
  }

  Future<void> _complete() async {
    if (_busy) return;
    for (final r in _rows) {
      if (r.amount > 0 && r.account == null) {
        return showSnack(context, tr('Choose an account for each payment.'), error: true);
      }
    }
    final remaining = _due - _entered;
    if (remaining > 0.009 && pos.cart.customerId == null) {
      return showSnack(context, tr('Not fully paid. Choose a customer to sell on credit.'), error: true);
    }
    setState(() => _busy = true);
    pos.cart.note = _note.text.trim();
    try {
      final res = await SalesService.completeSale(
        pos.cart,
        [
          for (final r in _rows)
            if (r.amount > 0 && r.account != null)
              PaymentLine(accountId: r.account!.id, accountName: r.account!.name, amount: r.amount),
        ],
      );
      pos.clear();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ReceiptScreen(saleId: res.saleId, change: res.change)),
        result: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, tr(errorText(e)), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final remaining = _due - _entered;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Checkout'))),
      body: _accounts.isEmpty && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    color: cs.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(children: [
                        Text(tr('Amount due'), style: TextStyle(color: cs.onPrimaryContainer)),
                        Text(Fmt.money(_due),
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onPrimaryContainer,
                                )),
                        if (_credit > 0)
                          Text('${tr('Total')} ${Fmt.money(_total)} - ${tr('Exchange credit')} ${Fmt.money(_credit)}',
                              style: TextStyle(color: cs.onPrimaryContainer)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (app.hasModule(Mod.customers))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(pos.cart.customerName ?? tr('Walk-in customer')),
                        subtitle: Text(tr('Needed for credit (unpaid) sales')),
                        trailing: const Icon(Icons.edit),
                        onTap: () async {
                          final p = await pickParty(context, 'customer');
                          if (p != null) setState(() => pos.setCustomer(p));
                        },
                      ),
                    ),
                  const SectionTitle('Payment'),
                  for (var i = 0; i < _rows.length; i++) _payRow(i),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add),
                      label: Text(tr('Split payment')),
                    ),
                  ),
                  if (_rows.isNotEmpty)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final q in _quickAmounts())
                        ActionChip(
                          label: Text(q == _due ? '${tr('Exact')} ${Fmt.amount(q)}' : Fmt.amount(q)),
                          onPressed: () => setState(() {
                            for (var i = 1; i < _rows.length; i++) {
                              _rows[i].controller.clear();
                            }
                            _rows.first.controller.text = Fmt.qty(q);
                          }),
                        ),
                    ]),
                  const SizedBox(height: 16),
                  KeyValue('Paid', Fmt.money(_entered)),
                  if (remaining > 0.009)
                    KeyValue('Remaining (on credit)', Fmt.money(remaining), color: cs.error, bold: true)
                  else
                    KeyValue('Change', Fmt.money(-remaining), bold: true, color: Colors.green.shade700),
                  const SizedBox(height: 12),
                  TextField(controller: _note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _complete,
                    icon: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(tr('Complete sale')),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _payRow(int i) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<String>(
            value: r.account?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Paid by')),
            items: [
              for (final a in _accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Row(children: [
                    Icon(accountIcon(a.type), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            onChanged: (id) => setState(() => r.account = _accounts.where((a) => a.id == id).firstOrNull),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(flex: 4, child: NumField(controller: r.controller, label: 'Amount', onChanged: (_) => setState(() {}))),
        if (_rows.length > 1)
          IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _rows.removeAt(i))),
      ]),
    );
  }
}
