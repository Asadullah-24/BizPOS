import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/alert_service.dart';
import '../../services/ledger_service.dart';
import '../common.dart';

/// Paid feature: customers who owe money, with one-tap WhatsApp / SMS reminders.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Payment reminders'))),
      body: LiveData<List<Party>>(
        load: () async {
          final list = (await LedgerService.parties('customer')).where((p) => p.balance > 0.009).toList();
          list.sort((a, b) => b.balance.compareTo(a.balance));
          return list;
        },
        builder: (ctx, list) {
          if (list.isEmpty) return const EmptyState(icon: Icons.verified, text: 'No customer owes you money.');
          final total = list.fold<double>(0, (a, p) => a + p.balance);
          return ListView(children: [
            ListTile(
              title: Text('${list.length} ${tr('customers')}'),
              trailing: Text(Fmt.money(total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const Divider(height: 1),
            for (final p in list)
              ListTile(
                title: Text(p.name),
                subtitle: Text('${p.phone ?? tr('No phone')} · ${Fmt.money(p.balance)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'WhatsApp',
                    icon: const Icon(Icons.chat, color: Colors.green),
                    onPressed: () => guard(context, () => ReminderService.whatsapp(p)),
                  ),
                  IconButton(
                    tooltip: 'SMS',
                    icon: const Icon(Icons.sms_outlined),
                    onPressed: () => guard(context, () => ReminderService.sms(p)),
                  ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
