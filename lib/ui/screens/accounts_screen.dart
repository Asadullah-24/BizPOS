import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/ledger_service.dart';
import '../common.dart';

const accountTypes = {'cash': 'Cash', 'bank': 'Bank', 'digital': 'Digital wallet / card'};

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _edit(BuildContext context, [Account? a]) async {
    final name = TextEditingController(text: a?.name ?? '');
    final opening = TextEditingController(text: numText(a?.openingBalance ?? 0));
    var type = a?.type ?? 'cash';
    var isDefault = a?.isDefault ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr(a == null ? 'New account' : 'Edit account')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('Name (e.g. Meezan Bank, JazzCash)'))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
                decoration: InputDecoration(labelText: tr('Type')),
                items: [for (final e in accountTypes.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
                onChanged: (v) => setS(() => type = v ?? 'cash'),
              ),
              const SizedBox(height: 12),
              NumField(controller: opening, label: 'Opening balance'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Default for sales')),
                value: isDefault,
                onChanged: (v) => setS(() => isDefault = v),
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
    if (ok != true || name.text.trim().isEmpty) return;
    await Db.instance.tx((s) async {
      if (isDefault) await s.ex.rawUpdate('UPDATE accounts SET is_default = 0, updated_at = ? WHERE is_default = 1', [DateTime.now().millisecondsSinceEpoch]);
      final row = {
        'name': name.text.trim(),
        'type': type,
        'opening_balance': Fmt.parse(opening.text),
        'is_default': isDefault ? 1 : 0,
      };
      if (a == null) {
        await s.insert('accounts', row);
      } else {
        await s.update('accounts', a.id, row);
      }
    });
  }

  Future<void> _transfer(BuildContext context, List<Account> accounts) async {
    if (accounts.length < 2) return showSnack(context, tr('Add a second account first.'), error: true);
    String? from = accounts.first.id;
    String? to = accounts[1].id;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('Transfer money')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AccountPicker(value: from, label: 'From', onChanged: (a) => setS(() => from = a?.id)),
              const SizedBox(height: 12),
              AccountPicker(value: to, label: 'To', onChanged: (a) => setS(() => to = a?.id)),
              const SizedBox(height: 12),
              NumField(controller: amount, label: 'Amount'),
              const SizedBox(height: 12),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Transfer'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = Fmt.parse(amount.text);
    if (from == null || to == null || from == to || v <= 0) {
      return showSnack(context, tr('Choose two different accounts and an amount.'), error: true);
    }
    await guard(context, () => LedgerService.transfer(
          fromId: from!,
          toId: to!,
          amount: v,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          employeeId: AppState.instance.user?.id,
        ), success: 'Transfer saved');
  }

  @override
  Widget build(BuildContext context) {
    return LiveData<List<Account>>(
      load: LedgerService.accounts,
      builder: (context, list) {
        final total = list.fold<double>(0, (a, b) => a + b.balance);
        return Scaffold(
          appBar: AppBar(title: Text(tr('Accounts')), actions: [
            IconButton(tooltip: tr('Transfer'), icon: const Icon(Icons.swap_horiz), onPressed: () => _transfer(context, list)),
          ]),
          floatingActionButton: FloatingActionButton(onPressed: () => _edit(context), child: const Icon(Icons.add)),
          body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            ListTile(
              title: Text(tr('Total in all accounts')),
              trailing: Text(Fmt.money(total), style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(),
            for (final a in list)
              ListTile(
                leading: CircleAvatar(child: Icon(accountIcon(a.type), size: 20)),
                title: Text(a.name),
                subtitle: Text([tr(accountTypes[a.type] ?? a.type), if (a.isDefault) tr('Default')].join(' · ')),
                trailing: Text(Fmt.money(a.balance), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountStatementScreen(account: a))),
                onLongPress: () => _edit(context, a),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Tap an account to see its transactions. Long-press to edit.'), style: Theme.of(context).textTheme.bodySmall),
            ),
          ]),
        );
      },
    );
  }
}

class AccountStatementScreen extends StatelessWidget {
  const AccountStatementScreen({super.key, required this.account});
  final Account account;

  static const _labels = {
    'sale': 'Sale',
    'sale_cancel': 'Sale cancelled (refund)',
    'return': 'Return refund',
    'purchase': 'Purchase',
    'expense': 'Expense',
    'receivable': 'Customer payment',
    'payable': 'Supplier payment',
    'transfer': 'Transfer',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: LiveData<List<DbRow>>(
        load: () => LedgerService.accountTransactions(account.id),
        builder: (ctx, list) => list.isEmpty
            ? const EmptyState(icon: Icons.account_balance_wallet_outlined, text: 'No transactions yet')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final isIn = p['direction'] == 'in';
                  return ListTile(
                    leading: Icon(isIn ? Icons.arrow_downward : Icons.arrow_upward, color: isIn ? Colors.green : Colors.red),
                    title: Text(tr(_labels[p['ref_type']] ?? '${p['ref_type'] ?? 'Payment'}')),
                    subtitle: Text([Fmt.dateTime(asInt(p['created_at'])), if ((p['note'] ?? '') != '') p['note'] as String].join(' · ')),
                    trailing: Text(
                      '${isIn ? '+' : '-'}${Fmt.money(asDouble(p['amount']))}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: isIn ? Colors.green.shade700 : Colors.red.shade700),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
