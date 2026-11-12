import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/activity_log.dart';
import '../../services/ledger_service.dart';
import '../common.dart';
import 'purchases_screen.dart';
import 'sale_detail_screen.dart';

String _title(String kind) => kind == 'supplier' ? 'Suppliers' : 'Customers';
String _table(String kind) => kind == 'supplier' ? 'suppliers' : 'customers';

/// Pick a customer or supplier, or add a new one.
Future<Party?> pickParty(BuildContext context, String kind) => showModalBottomSheet<Party>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PartyPicker(kind: kind),
    );

class _PartyPicker extends StatefulWidget {
  const _PartyPicker({required this.kind});
  final String kind;

  @override
  State<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<_PartyPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scroll) => Column(children: [
        ListTile(
          title: Text(tr(widget.kind == 'supplier' ? 'Choose supplier' : 'Choose customer'),
              style: Theme.of(context).textTheme.titleLarge),
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.person_add),
            label: Text(tr('New')),
            onPressed: () async {
              final p = await Navigator.push<Party>(
                  context, MaterialPageRoute(builder: (_) => PartyForm(kind: widget.kind, initialName: _q)));
              if (p != null && context.mounted) Navigator.pop(context, p);
            },
          ),
        ),
        SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Name or phone'),
        Expanded(
          child: LiveData<List<Party>>(
            deps: [_q],
            load: () => LedgerService.parties(widget.kind, search: _q),
            builder: (ctx, list) => list.isEmpty
                ? const EmptyState(icon: Icons.person_search, text: 'No match. Add a new one.')
                : ListView.builder(
                    controller: scroll,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(p.name.characters.first.toUpperCase())),
                        title: Text(p.name),
                        subtitle: p.phone == null ? null : Text(p.phone!),
                        trailing: p.balance.abs() > 0.009 ? Text(Fmt.money(p.balance)) : null,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, required this.kind});
  final String kind;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.kind == 'customer';
    return Scaffold(
      appBar: AppBar(title: Text(tr(_title(widget.kind)))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: Text(tr('Add')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PartyForm(kind: widget.kind))),
      ),
      body: Column(children: [
        SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Name or phone'),
        Expanded(
          child: LiveData<List<Party>>(
            deps: [_q],
            load: () => LedgerService.parties(widget.kind, search: _q),
            builder: (ctx, list) {
              if (list.isEmpty) {
                return EmptyState(icon: isCustomer ? Icons.people_outline : Icons.local_shipping_outlined, text: 'Nothing here yet');
              }
              final total = list.fold<double>(0, (a, p) => a + p.balance);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return ListTile(
                      dense: true,
                      title: Text(tr(isCustomer ? 'Total receivable' : 'Total payable')),
                      trailing: Text(Fmt.money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  }
                  final p = list[i - 1];
                  return ListTile(
                    leading: CircleAvatar(child: Text(p.name.characters.first.toUpperCase())),
                    title: Text(p.name),
                    subtitle: p.phone == null || p.phone!.isEmpty ? null : Text(p.phone!),
                    trailing: Text(
                      Fmt.money(p.balance),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.balance > 0.009 ? Colors.red.shade700 : (p.balance < -0.009 ? Colors.green.shade700 : null),
                      ),
                    ),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => PartyDetailScreen(kind: widget.kind, id: p.id))),
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

class PartyForm extends StatefulWidget {
  const PartyForm({super.key, required this.kind, this.party, this.initialName = ''});
  final String kind;
  final Party? party;
  final String initialName;

  @override
  State<PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<PartyForm> {
  late final _name = TextEditingController(text: widget.party?.name ?? widget.initialName);
  late final _phone = TextEditingController(text: widget.party?.phone ?? '');
  late final _email = TextEditingController(text: widget.party?.email ?? '');
  late final _address = TextEditingController(text: widget.party?.address ?? '');
  late final _opening = TextEditingController(text: numText(widget.party?.openingBalance ?? 0));
  late final _notes = TextEditingController(text: widget.party?.notes ?? '');

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, tr('Enter a name.'), error: true);
    final row = <String, Object?>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'opening_balance': Fmt.parse(_opening.text),
      'notes': _notes.text.trim(),
    };
    final table = _table(widget.kind);
    String id;
    if (widget.party == null) {
      id = await Db.instance.s.insert(table, row);
      await ActivityLog.add('${widget.kind == 'supplier' ? 'Supplier' : 'Customer'} added', entity: widget.kind, entityId: id, detail: _name.text);
    } else {
      id = widget.party!.id;
      await Db.instance.s.update(table, id, row);
    }
    final p = await LedgerService.party(widget.kind, id);
    if (mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.kind == 'customer';
    return Scaffold(
      appBar: AppBar(title: Text(tr(widget.party == null ? (isCustomer ? 'New customer' : 'New supplier') : 'Edit'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, autofocus: widget.party == null, decoration: InputDecoration(labelText: tr('Name'))),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Phone'))),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Email'))),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: InputDecoration(labelText: tr('Address'))),
        const SizedBox(height: 12),
        NumField(controller: _opening, label: isCustomer ? 'Opening balance (they owe you)' : 'Opening balance (you owe them)'),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: tr('Notes'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ]),
    );
  }
}

class PartyDetailScreen extends StatelessWidget {
  const PartyDetailScreen({super.key, required this.kind, required this.id});
  final String kind;
  final String id;

  Future<void> _settle(BuildContext context, Party p) async {
    final isCustomer = kind == 'customer';
    final amount = TextEditingController(text: p.balance > 0 ? Fmt.qty(Fmt.round(p.balance)) : '');
    final note = TextEditingController();
    String? accountId = (await LedgerService.defaultAccount())?.id;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr(isCustomer ? 'Receive payment' : 'Pay supplier')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              NumField(controller: amount, label: 'Amount', autofocus: true),
              const SizedBox(height: 12),
              AccountPicker(value: accountId, onChanged: (a) => setS(() => accountId = a?.id)),
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
    if (v <= 0 || accountId == null) return showSnack(context, tr('Enter an amount and choose an account.'), error: true);
    await guard(context, () => LedgerService.settle(
          kind: kind,
          partyId: id,
          accountId: accountId!,
          amount: v,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
          employeeId: AppState.instance.user?.id,
        ), success: 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = kind == 'customer';
    return LiveData<(Party?, List<DbRow>)>(
      load: () async => (await LedgerService.party(kind, id), await LedgerService.statement(kind, id)),
      builder: (context, data) {
        final p = data.$1;
        if (p == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, text: 'Not found'));
        return Scaffold(
          appBar: AppBar(title: Text(p.name), actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PartyForm(kind: kind, party: p))),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, 'Delete', 'Delete ${p.name}? Their past sales stay in reports.', danger: true)) return;
                await Db.instance.s.softDelete(_table(kind), p.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ]),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(isCustomer ? 'They owe you' : 'You owe them'), style: Theme.of(context).textTheme.labelLarge),
                    Text(Fmt.money(p.balance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (p.phone != null && p.phone!.isNotEmpty) Text('${tr('Phone')}: ${p.phone}'),
                    if (p.email != null && p.email!.isNotEmpty) Text('${tr('Email')}: ${p.email}'),
                    if (p.address != null && p.address!.isNotEmpty) Text('${tr('Address')}: ${p.address}'),
                    if (p.notes != null && p.notes!.isNotEmpty) Text(p.notes!),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _settle(context, p),
                      icon: Icon(isCustomer ? Icons.call_received : Icons.call_made),
                      label: Text(tr(isCustomer ? 'Receive payment' : 'Pay supplier')),
                    ),
                  ]),
                ),
              ),
            ),
            SectionTitle(isCustomer ? 'Purchase history and payments' : 'Purchases and payments'),
            if (data.$2.isEmpty) const EmptyState(icon: Icons.history, text: 'Nothing here yet'),
            for (final r in data.$2) _statementTile(context, r),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  Widget _statementTile(BuildContext context, DbRow r) {
    final kindStr = r['kind'] as String;
    final amount = asDouble(r['amount']);
    IconData icon;
    String title;
    VoidCallback? onTap;
    switch (kindStr) {
      case 'sale':
        icon = Icons.receipt_long;
        title = '${tr('Sale')} ${r['ref']}${r['status'] == 'cancelled' ? ' (${tr('cancelled')})' : ''}';
        onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: r['id'] as String)));
        break;
      case 'return':
        icon = Icons.assignment_return;
        title = '${tr('Return')} ${r['ref']}';
        break;
      case 'purchase':
        icon = Icons.shopping_cart;
        title = '${tr('Purchase')} ${r['ref']}';
        onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseDetailScreen(id: r['id'] as String)));
        break;
      case 'payment_in':
        icon = Icons.call_received;
        title = tr('Payment received');
        break;
      default:
        icon = Icons.call_made;
        title = tr('Payment made');
    }
    final ref = r['ref'] as String?;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text([Fmt.dateTime(asInt(r['created_at'])), if (kindStr.startsWith('payment') && ref != null && ref.isNotEmpty) ref].join(' · ')),
      trailing: Text(Fmt.money(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
