import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/access.dart';
import '../../core/packages.dart';
import '../../core/permissions.dart';
import '../brand.dart';
import '../../models/models.dart';
import '../../services/drive_service.dart';
import '../../services/ledger_service.dart';
import '../../services/product_service.dart';
import '../../services/report_service.dart';
import '../../services/sales_service.dart';
import '../charts.dart';
import '../common.dart';
import '../../services/store_service.dart';
import '../tokens.dart';
import 'online_store_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'parties_screen.dart';
import 'pos_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'sale_detail_screen.dart';

class _DashData {
  _DashData(this.today, this.month, this.week, this.low, this.receivable, this.payable, this.recent, this.online, this.onlineCount);
  final ReportData today;
  final ReportData month;
  final ReportData week;
  final List<Product> low;
  final double receivable;
  final double payable;
  final List<DbRow> recent;

  /// Sales that came from the online store this month.
  final double online;
  final int onlineCount;
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
      await Db.instance.s.scalar(
          "SELECT COALESCE(SUM(total),0) FROM sales WHERE deleted_at IS NULL AND status != 'cancelled' AND source = 'online' AND created_at >= ?",
          [DateTime(now.year, now.month).millisecondsSinceEpoch]),
      (await Db.instance.s.scalar(
              "SELECT COUNT(*) FROM sales WHERE deleted_at IS NULL AND status != 'cancelled' AND source = 'online' AND created_at >= ?",
              [DateTime(now.year, now.month).millisecondsSinceEpoch]))
          .toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final drive = context.watch<DriveService>();
    final seeProfit = app.can(Perm.reports);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasLogo = (app.settings['logo'] ?? '').isNotEmpty && Access.instance.has(Feature.branding);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 16,
        title: Row(children: [
          if (hasLogo)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ProductThumb(image: app.settings['logo'], name: app.businessName, size: 42),
              ),
            )
          else
            Container(
              width: 42,
              height: 42,
              margin: const EdgeInsetsDirectional.only(end: 12),
              decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr(greeting)}, ${app.user?.name ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
              Text(app.businessName, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        actions: [
          if (drive.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                drive.busy ? Icons.cloud_sync : (drive.hasPendingChanges ? Icons.cloud_upload_outlined : Icons.cloud_done),
                color: drive.lastError != null ? cs.error : Tw.emerald400,
              ),
            ),
          IconButton(tooltip: tr('Lock'), icon: const Icon(Icons.lock_outline_rounded), onPressed: app.lock),
          const SizedBox(width: 4),
        ],
      ),
      body: LiveData<_DashData>(
        load: _load,
        builder: (context, d) {
          final wide = MediaQuery.sizeOf(context).width > 900;
          final cols = wide ? 4 : 2;
          final cards = <Widget>[
            StatCard(
              label: 'This month',
              value: Fmt.money(d.month.netSales),
              icon: Icons.calendar_month_rounded,
              color: Tw.indigo500,
              sub: '${d.month.salesCount} ${tr('sales')}',
              onTap: seeProfit
                  ? () => openFeature(context, Feature.reports,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())))
                  : null,
            ),
            if (seeProfit)
              StatCard(
                label: 'Net profit (month)',
                value: Fmt.money(d.month.netProfit),
                icon: Icons.trending_up_rounded,
                color: d.month.netProfit < 0 ? Tw.rose500 : Tw.emerald500,
              ),
            if (app.hasModule(Mod.customers))
              StatCard(label: 'Receivables', value: Fmt.money(d.receivable), icon: Icons.call_received_rounded, color: Tw.sky400),
            if (app.hasModule(Mod.suppliers))
              StatCard(label: 'Payables', value: Fmt.money(d.payable), icon: Icons.call_made_rounded, color: Tw.violet500),
            if (app.hasModule(Mod.inventory))
              StatCard(
                label: 'Low stock',
                value: '${d.low.length}${d.low.length >= 6 ? '+' : ''}',
                icon: Icons.inventory_2_rounded,
                color: d.low.isEmpty ? Tw.emerald500 : Tw.amber500,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen(lowOnly: true))),
              ),
            if (d.onlineCount > 0)
              StatCard(
                label: 'Online sales (month)',
                value: Fmt.money(d.online),
                icon: Icons.public_rounded,
                color: Tw.cyan400,
                sub: '${d.onlineCount} ${tr('orders')}',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen())),
              ),
            if (app.hasModule(Mod.expenses))
              StatCard(label: 'Expenses (month)', value: Fmt.money(d.month.expenses), icon: Icons.receipt_rounded, color: Tw.rose400),
          ];
          return RefreshIndicator(
            onRefresh: () async => Db.instance.refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              ListenableBuilder(
                listenable: StoreService.instance,
                builder: (context, _) {
                  final n = StoreService.instance.newOrders;
                  if (n == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Tw.emerald500.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        leading: const Icon(Icons.shopping_bag_rounded, color: Tw.emerald500),
                        title: Text('$n ${tr('new online orders')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen())),
                      ),
                    ),
                  );
                },
              ),
              _TodayHero(today: d.today, seeProfit: seeProfit, showExpenses: app.hasModule(Mod.expenses)),
              const SizedBox(height: 16),
              _QuickActions(app: app),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: wide ? 1.7 : 1.45,
                children: cards,
              ),
              const SizedBox(height: 16),
              _Panel(
                title: tr('Last 7 days'),
                trailing: ChartLegend(showProfit: seeProfit),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                  child: SalesBarChart(points: d.week.series, showProfit: seeProfit),
                ),
              ),
              if (d.low.isNotEmpty && app.hasModule(Mod.inventory)) ...[
                const SizedBox(height: 16),
                _Panel(
                  title: tr('Low stock'),
                  trailing: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen(lowOnly: true))),
                    child: Text(tr('View all')),
                  ),
                  child: Column(children: [
                    for (final p in d.low)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ProductThumb(image: p.image, name: p.name, size: 40),
                        title: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: _Pill(text: '${Fmt.qty(p.stock)} ${p.unit ?? ''}'.trim(), color: Tw.amber500),
                      ),
                  ]),
                ),
              ],
              if (d.recent.isNotEmpty && app.can(Perm.salesView)) ...[
                const SizedBox(height: 16),
                _Panel(
                  title: tr('Recent sales'),
                  child: Column(children: [
                    for (final s in d.recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: Tw.indigo500.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                          child: Icon(s['source'] == 'online' ? Icons.public_rounded : Icons.receipt_long_rounded,
                              color: s['source'] == 'online' ? Tw.cyan400 : Tw.indigo400, size: 20),
                        ),
                        title: Text(s['invoice_no'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${s['customer_name'] ?? tr('Walk-in customer')} · ${Fmt.time(asInt(s['created_at']))}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          Fmt.money(asDouble(s['total'])),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: s['status'] == 'cancelled' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s['id'] as String))),
                      ),
                  ]),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }
}

/// Gradient card with today's sales, profit and expenses.
class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.today, required this.seeProfit, required this.showExpenses});
  final ReportData today;
  final bool seeProfit;
  final bool showExpenses;

  @override
  Widget build(BuildContext context) {
    Widget mini(String label, String value, IconData icon) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Row(children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(label), style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Tw.indigo600, Tw.violet600, Color(0xFF9333EA)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: Tw.glow(Tw.indigo600, opacity: 0.3),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.07)),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(999)),
              child: Text(tr('Today'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            Text('${today.salesCount} ${tr('sales')}', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          Text(tr("Today's sales"), style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(Fmt.money(today.sales),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
          ),
          if (seeProfit || showExpenses) ...[
            const SizedBox(height: 16),
            Row(children: [
              if (seeProfit) mini('Profit', Fmt.money(today.netProfit), Icons.trending_up_rounded),
              if (seeProfit && showExpenses) const SizedBox(width: 10),
              if (showExpenses) mini('Expenses', Fmt.money(today.expenses), Icons.receipt_rounded),
            ]),
          ],
        ]),
      ]),
    );
  }
}

/// Round shortcut buttons under the hero card.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    void go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    final actions = <(String, IconData, Color, VoidCallback)>[
      if (app.allowed(Mod.pos, Perm.sell)) ('New sale', Icons.point_of_sale_rounded, Tw.indigo500, () => go(const PosScreen())),
      if (app.allowed(Mod.products, Perm.products)) ('Add product', Icons.add_box_rounded, Tw.emerald500, () => openProductForm(context)),
      if (app.allowed(Mod.expenses, Perm.expenses)) ('Expense', Icons.receipt_rounded, Tw.rose500, () => showExpenseForm(context)),
      if (app.allowed(Mod.inventory, Perm.inventory) || app.allowed(Mod.inventory, Perm.products))
        ('Stock', Icons.warehouse_rounded, Tw.amber500, () => go(const InventoryScreen())),
      if (app.allowed(Mod.customers, Perm.customers))
        ('Customers', Icons.people_alt_rounded, Tw.sky400, () => go(const PartiesScreen(kind: 'customer'))),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      for (final a in actions.take(5))
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: a.$4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: a.$3.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: a.$3.withOpacity(0.28)),
                  ),
                  child: Icon(a.$2, color: a.$3, size: 24),
                ),
                const SizedBox(height: 6),
                Text(tr(a.$1),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Card with a title row, used for the chart and lists.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 4),
          child,
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}
