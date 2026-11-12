import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/ledger_service.dart';
import '../../services/product_service.dart';
import '../../services/purchase_service.dart';
import '../../services/report_service.dart';
import '../common.dart';
import 'categories_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Period _period = Period.of(PeriodKind.month);
  String? _cat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Expenses')), actions: [
        IconButton(
          tooltip: tr('Categories'),
          icon: const Icon(Icons.category_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen(kind: 'expense'))),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr('Add expense')),
        onPressed: () => showExpenseForm(context),
      ),
      body: Column(children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _period = _period.shift(-1))),
          Expanded(child: Text(_period.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _period = _period.shift(1))),
        ]),
        SizedBox(
          height: 48,
          child: LiveData<List<Category>>(
            load: () => ProductService.categories('expense'),
            builder: (ctx, cats) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(label: Text(tr('All')), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                ),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(c.name), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LiveData<List<DbRow>>(
            deps: [_period.fromMs, _cat],
            load: () => ExpenseService.list(from: _period.fromMs, to: _period.toMs, categoryId: _cat),
            builder: (ctx, list) {
              if (list.isEmpty) return const EmptyState(icon: Icons.money_off, text: 'No expenses in this period');
              final total = list.fold<double>(0, (a, e) => a + asDouble(e['amount']));
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return ListTile(
                      dense: true,
                      title: Text(tr('Total')),
                      trailing: Text(Fmt.money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  }
                  final e = list[i - 1];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.receipt, size: 20)),
                    title: Text((e['category_name'] as String?) ?? tr('Other')),
                    subtitle: Text([
                      Fmt.date(asInt(e['date'])),
                      if (e['account_name'] != null) e['account_name'] as String,
                      if ((e['note'] ?? '') != '') e['note'] as String,
                    ].join(' · ')),
                    trailing: Text(Fmt.money(asDouble(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onLongPress: () async {
                      if (await confirm(context, 'Delete expense', 'Delete this expense? The money goes back to its account.', danger: true)) {
                        await ExpenseService.delete(e['id'] as String);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

Future<void> showExpenseForm(BuildContext context) async {
  final cats = await ProductService.categories('expense');
  final def = await LedgerService.defaultAccount();
  if (!context.mounted) return;
  String? catId = cats.firstOrNull?.id;
  String? accId = def?.id;
  var date = DateTime.now();
  final amount = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(tr('Add expense')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: catId,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Category')),
              items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setS(() => catId = v),
            ),
            const SizedBox(height: 12),
            NumField(controller: amount, label: 'Amount', autofocus: true),
            const SizedBox(height: 12),
            AccountPicker(value: accId, label: 'Paid from', onChanged: (a) => setS(() => accId = a?.id)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(Fmt.date(date.millisecondsSinceEpoch)),
              onPressed: () async {
                final d = await pickDate(ctx, date);
                if (d != null) setS(() => date = d);
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
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
  final v = Fmt.parse(amount.text);
  if (v <= 0 || accId == null) return showSnack(context, tr('Enter an amount and choose an account.'), error: true);
  final now = DateTime.now();
  final when = DateTime(date.year, date.month, date.day, now.hour, now.minute);
  await guard(context, () => ExpenseService.add(
        categoryId: catId,
        amount: v,
        accountId: accId!,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        date: when.millisecondsSinceEpoch,
      ), success: 'Expense saved');
}
