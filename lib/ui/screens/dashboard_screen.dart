import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/drive_service.dart';
import '../../services/ledger_service.dart';
import '../../services/product_service.dart';
import '../../services/report_service.dart';
import '../../services/sales_service.dart';
import '../charts.dart';
import '../common.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import 'sale_detail_screen.dart';

class _DashData {
  _DashData(this.today, this.month, this.week, this.low, this.receivable, this.payable, this.recent);
  final ReportData today;
  final ReportData month;
  final ReportData week;
  final List<Product> low;
  final double receivable;
  final double payable;
  final List<DbRow> recent;
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static Future<_DashData> _load() async {
    final now = DateTime.now();
    final week = Period.custom(now.subtract(const Duration(days: 6)), now);
    return _DashData(
      await ReportService.build(Period.of(PeriodKind.day), details: false),
      await ReportService.build(Period.of(PeriodKind.month), details: false),
      await ReportService.build(week, details: false),
      await ProductService.lowStock(limit: 6),
      await LedgerService.totalBalance('customer'),
      await LedgerService.totalBalance('supplier'),
      await SalesService.list(limit: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final drive = context.watch<DriveService>();
    final seeProfit = app.can(Perm.reports);
    return Scaffold(
      appBar: AppBar(
        title: Text(app.businessName),
        actions: [
          if (drive.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                drive.busy ? Icons.cloud_sync : (drive.hasPendingChanges ? Icons.cloud_upload_outlined : Icons.cloud_done),
                color: drive.lastError != null ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          IconButton(tooltip: tr('Lock'), icon: const Icon(Icons.lock_outline), onPressed: app.lock),
        ],
      ),
      body: LiveData<_DashData>(
        load: _load,
        builder: (context, d) {
          final cols = MediaQuery.sizeOf(context).width > 900 ? 4 : 2;
          final cards = <Widget>[
            StatCard(label: 'Today', value: Fmt.money(d.today.sales), icon: Icons.today, sub: '${d.today.salesCount} ${tr('sales')}'),
            if (seeProfit)
              StatCard(
                label: 'Profit today',
                value: Fmt.money(d.today.netProfit),
                icon: Icons.trending_up,
                color: d.today.netProfit < 0 ? Colors.red : Colors.green.shade700,
              ),
            if (app.hasModule(Mod.expenses))
              StatCard(label: 'Expenses today', value: Fmt.money(d.today.expenses), icon: Icons.money_off, color: Colors.orange.shade800),
            StatCard(
              label: 'This month',
              value: Fmt.money(d.month.netSales),
              icon: Icons.calendar_month,
              sub: '${d.month.salesCount} ${tr('sales')}',
              onTap: seeProfit ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())) : null,
            ),
            if (seeProfit)
              StatCard(
                label: 'Net profit (month)',
                value: Fmt.money(d.month.netProfit),
                icon: Icons.account_balance_wallet,
                color: d.month.netProfit < 0 ? Colors.red : Colors.green.shade700,
              ),
            if (app.hasModule(Mod.customers))
              StatCard(label: 'Receivables', value: Fmt.money(d.receivable), icon: Icons.call_received, color: Colors.indigo),
            if (app.hasModule(Mod.suppliers))
              StatCard(label: 'Payables', value: Fmt.money(d.payable), icon: Icons.call_made, color: Colors.brown),
            if (app.hasModule(Mod.inventory))
              StatCard(
                label: 'Low stock',
                value: '${d.low.length}${d.low.length >= 6 ? '+' : ''}',
                icon: Icons.warning_amber,
                color: d.low.isEmpty ? Colors.green.shade700 : Colors.red,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen(lowOnly: true))),
              ),
          ];
          return RefreshIndicator(
            onRefresh: () async => Db.instance.refresh(),
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (app.hasModule(Mod.inventory) && d.low.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: MaterialBanner(
                    content: Text('${d.low.length >= 6 ? '6+' : d.low.length} ${tr('items are low on stock')}'),
                    leading: const Icon(Icons.warning_amber, color: Colors.red),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen(lowOnly: true))),
                        child: Text(tr('View')),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: cards,
                ),
              ),
              SectionTitle('Last 7 days', trailing: ChartLegend(showProfit: seeProfit)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                    child: SalesBarChart(points: d.week.series, showProfit: seeProfit),
                  ),
                ),
              ),
              if (d.low.isNotEmpty) ...[
                const SectionTitle('Low stock'),
                for (final p in d.low)
                  ListTile(
                    leading: ProductThumb(image: p.image, name: p.name, size: 40),
                    title: Text(p.displayName),
                    trailing: Text('${Fmt.qty(p.stock)} ${p.unit ?? ''}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ),
              ],
              if (d.recent.isNotEmpty && app.can(Perm.salesView)) ...[
                const SectionTitle('Recent sales'),
                for (final s in d.recent)
                  ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text(s['invoice_no'] as String),
                    subtitle: Text('${s['customer_name'] ?? tr('Walk-in customer')} · ${Fmt.time(asInt(s['created_at']))}'),
                    trailing: Text(
                      Fmt.money(asDouble(s['total'])),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: s['status'] == 'cancelled' ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s['id'] as String))),
                  ),
              ],
            ]),
          );
        },
      ),
    );
  }
}
