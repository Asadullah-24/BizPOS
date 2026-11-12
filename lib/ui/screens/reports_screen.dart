import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/report_pdf.dart';
import '../../services/report_service.dart';
import '../charts.dart';
import '../common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _p = Period.of(PeriodKind.day);
  ReportData? _last;

  static const _kinds = {
    PeriodKind.day: 'Daily',
    PeriodKind.week: 'Weekly',
    PeriodKind.month: 'Monthly',
    PeriodKind.year: 'Yearly',
    PeriodKind.custom: 'Custom',
  };

  Future<void> _setKind(PeriodKind k) async {
    if (k == PeriodKind.custom) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(start: _p.from, end: _p.to.subtract(const Duration(days: 1))),
      );
      if (r == null) return;
      setState(() => _p = Period.custom(r.start, r.end));
      return;
    }
    setState(() => _p = Period.of(k));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reports')), actions: [
        IconButton(
          tooltip: tr('Share PDF'),
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: () {
            final d = _last;
            if (d != null) guard(context, () => ReportPdf.share(_p, d));
          },
        ),
      ]),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            for (final e in _kinds.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(tr(e.value)), selected: _p.kind == e.key, onSelected: (_) => _setKind(e.key)),
              ),
          ]),
        ),
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _p = _p.shift(-1))),
          Expanded(child: Text(_p.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _p = _p.shift(1))),
        ]),
        Expanded(
          child: LiveData<ReportData>(
            deps: [_p.fromMs, _p.toMs],
            load: () async {
              final d = await ReportService.build(_p);
              _last = d;
              return d;
            },
            builder: (ctx, d) => _body(context, d),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, ReportData d) {
    final cols = MediaQuery.sizeOf(context).width > 900 ? 4 : 2;
    final green = Colors.green.shade700;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            StatCard(label: 'Net sales', value: Fmt.money(d.netSales), icon: Icons.point_of_sale, sub: '${d.salesCount} ${tr('sales')}'),
            StatCard(label: 'Gross profit', value: Fmt.money(d.grossProfit), icon: Icons.trending_up, color: green),
            StatCard(label: 'Expenses', value: Fmt.money(d.expenses), icon: Icons.money_off, color: Colors.orange.shade800),
            StatCard(
              label: 'Net profit',
              value: Fmt.money(d.netProfit),
              icon: Icons.account_balance_wallet,
              color: d.netProfit < 0 ? Colors.red : green,
            ),
          ],
        ),
      ),
      SectionTitle('Sales', trailing: const ChartLegend(showProfit: true)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: SalesBarChart(points: d.series, showProfit: true, height: 220),
          ),
        ),
      ),
      const SectionTitle('Profit and loss'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          KeyValue('Sales', Fmt.money(d.sales)),
          KeyValue('Returns', '-${Fmt.money(d.returns)}'),
          KeyValue('Net sales', Fmt.money(d.netSales), bold: true),
          KeyValue('Tax collected', '-${Fmt.money(d.tax)}'),
          KeyValue('Cost of goods sold', '-${Fmt.money(d.cogs)}'),
          KeyValue('Gross profit', Fmt.money(d.grossProfit), bold: true),
          KeyValue('Expenses', '-${Fmt.money(d.expenses)}'),
          KeyValue('Net profit', Fmt.money(d.netProfit), bold: true, color: d.netProfit < 0 ? Colors.red : green),
          const Divider(),
          KeyValue('Average sale', Fmt.money(d.avgSale)),
          KeyValue('Discounts given', Fmt.money(d.discount)),
          KeyValue('Cancelled sales', '${d.cancelledCount}'),
          KeyValue('Purchases', Fmt.money(d.purchases)),
          KeyValue('Money in', Fmt.money(d.moneyIn)),
          KeyValue('Money out', Fmt.money(d.moneyOut)),
        ]),
      ),
      if (d.topProducts.isNotEmpty) ...[
        const SectionTitle('Top products'),
        for (final r in d.topProducts)
          ListTile(
            dense: true,
            title: Text('${r['name']}'),
            subtitle: Text('${tr('Qty')} ${Fmt.qty(asDouble(r['qty']))} · ${tr('Profit')} ${Fmt.money(asDouble(r['profit']))}'),
            trailing: Text(Fmt.money(asDouble(r['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
      ],
      if (d.byCategory.isNotEmpty) ...[
        const SectionTitle('Sales by category'),
        for (final r in d.byCategory)
          ListTile(
            dense: true,
            title: Text(tr('${r['name']}')),
            subtitle: Text('${tr('Qty')} ${Fmt.qty(asDouble(r['qty']))}'),
            trailing: Text(Fmt.money(asDouble(r['total']))),
          ),
      ],
      if (d.byAccount.isNotEmpty) ...[
        const SectionTitle('Accounts'),
        for (final r in d.byAccount)
          ListTile(
            dense: true,
            title: Text(tr('${r['name']}')),
            trailing: Text('+${Fmt.money(asDouble(r['money_in']))}  /  -${Fmt.money(asDouble(r['money_out']))}'),
          ),
      ],
      if (d.expensesByCategory.isNotEmpty) ...[
        const SectionTitle('Expenses by category'),
        for (final r in d.expensesByCategory)
          ListTile(dense: true, title: Text(tr('${r['name']}')), trailing: Text(Fmt.money(asDouble(r['total'])))),
      ],
    ]);
  }
}
