import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/report_service.dart';
import '../../services/return_service.dart';
import '../../services/sales_service.dart';
import '../common.dart';
import 'sale_detail_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _q = '';
  Period? _period = Period.of(PeriodKind.day);
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sales')), actions: [
        IconButton(
          tooltip: tr('Returns'),
          icon: const Icon(Icons.assignment_return_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen())),
        ),
      ]),
      body: Column(children: [
        SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Invoice no, customer or phone'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final e in {
              'Today': PeriodKind.day,
              'This week': PeriodKind.week,
              'This month': PeriodKind.month,
              'This year': PeriodKind.year,
            }.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(tr(e.key)),
                  selected: _period?.kind == e.value,
                  onSelected: (_) => setState(() => _period = Period.of(e.value)),
                ),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(label: Text(tr('All time')), selected: _period == null, onSelected: (_) => setState(() => _period = null)),
            ),
            FilterChip(
              label: Text(tr('Cancelled')),
              selected: _status == 'cancelled',
              onSelected: (v) => setState(() => _status = v ? 'cancelled' : null),
            ),
          ]),
        ),
        Expanded(
          child: LiveData<List<DbRow>>(
            deps: [_q, _period?.fromMs, _period?.kind, _status],
            load: () => SalesService.list(from: _period?.fromMs, to: _period?.toMs, search: _q, status: _status, limit: 500),
            builder: (ctx, list) {
              if (list.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, text: 'No sales in this period');
              final total = list.where((s) => s['status'] == 'completed').fold<double>(0, (a, s) => a + asDouble(s['total']));
              return ListView.separated(
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return ListTile(
                      dense: true,
                      title: Text('${list.length} ${tr('sales')}'),
                      trailing: Text(Fmt.money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    );
                  }
                  final s = list[i - 1];
                  final cancelled = s['status'] == 'cancelled';
                  final due = asDouble(s['total']) - asDouble(s['paid']);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cancelled ? Colors.grey.shade300 : null,
                      child: Icon(cancelled ? Icons.block : (s['source'] == 'online' ? Icons.public_rounded : Icons.receipt_long), size: 20),
                    ),
                    title: Text(s['invoice_no'] as String),
                    subtitle: Text([
                      if (s['source'] == 'online') tr('Online store'),
                      (s['customer_name'] as String?) ?? tr('Walk-in customer'),
                      Fmt.dateTime(asInt(s['created_at'])),
                      if (!cancelled && due > 0.009) '${tr('Due')} ${Fmt.money(due)}',
                    ].join(' · ')),
                    trailing: Text(
                      Fmt.money(asDouble(s['total'])),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s['id'] as String))),
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

class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});

  static const typeLabels = {'refund': 'Refund', 'credit': 'Store credit', 'exchange': 'Exchange'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Returns'))),
      body: LiveData<List<DbRow>>(
        load: () => ReturnService.list(limit: 500),
        builder: (ctx, list) => list.isEmpty
            ? const EmptyState(icon: Icons.assignment_return_outlined, text: 'No returns yet. Open a sale to return items.')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return ListTile(
                    leading: const Icon(Icons.assignment_return),
                    title: Text('${r['return_no']} · ${tr(typeLabels[r['type']] ?? '${r['type']}')}'),
                    subtitle: Text([
                      '${tr('Invoice')} ${r['invoice_no'] ?? '-'}',
                      if (r['customer_name'] != null) r['customer_name'] as String,
                      Fmt.dateTime(asInt(r['created_at'])),
                    ].join(' · ')),
                    trailing: Text(Fmt.money(asDouble(r['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: r['sale_id'] == null
                        ? null
                        : () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: r['sale_id'] as String))),
                  );
                },
              ),
      ),
    );
  }
}
