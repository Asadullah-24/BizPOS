import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/i18n.dart';
import '../../core/access.dart';
import '../../core/packages.dart';
import '../../core/permissions.dart';
import '../brand.dart';
import '../../services/cloud_service.dart';
import '../tokens.dart';
import 'account_screen.dart';
import 'accounts_screen.dart';
import 'admin/admin_panel.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'employees_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'parties_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'plan_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'stock_scan_screen.dart';
import 'store_qr_screen.dart';
import 'voice_stock_screen.dart';

class _Item {
  const _Item(this.label, this.icon, this.page, {this.feature, this.group = 'Business', this.color = Tw.indigo500});
  final String label;
  final IconData icon;
  final Widget Function() page;
  final String group;
  final Color color;

  /// Paid feature needed to open the page.
  final String? feature;
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    context.watch<Access>();
    final cloud = context.watch<CloudService>();
    final items = <_Item>[
      if (app.allowed(Mod.inventory, Perm.inventory) || app.allowed(Mod.inventory, Perm.products))
        _Item('Inventory', Icons.warehouse_rounded, () => const InventoryScreen(), group: 'Stock', color: Tw.amber500),
      if (app.allowed(Mod.inventory, Perm.inventory) && app.hasModule(Mod.barcode))
        _Item('Scan stock', Icons.qr_code_scanner_rounded, () => const StockScanScreen(), group: 'Stock', color: Tw.sky400),
      if (app.allowed(Mod.inventory, Perm.inventory))
        _Item('Voice stock', Icons.mic_rounded, () => const VoiceStockScreen(), feature: Feature.voice, group: 'Stock', color: Tw.fuchsia500),
      if (app.allowed(Mod.customers, Perm.customers))
        _Item('Reminders', Icons.notifications_active_rounded, () => const RemindersScreen(), feature: Feature.reminders, group: 'People', color: Tw.amber500),
      if (app.can(Perm.products)) _Item('Categories', Icons.category_rounded, () => const CategoriesScreen(kind: 'product'), group: 'Stock', color: Tw.violet500),
      if (app.allowed(Mod.customers, Perm.customers)) _Item('Customers', Icons.people_alt_rounded, () => const PartiesScreen(kind: 'customer'), group: 'People', color: Tw.sky400),
      if (app.allowed(Mod.suppliers, Perm.suppliers))
        _Item('Suppliers', Icons.local_shipping_rounded, () => const PartiesScreen(kind: 'supplier'), group: 'People', color: Tw.emerald500),
      if (app.allowed(Mod.purchases, Perm.purchases)) _Item('Purchases', Icons.add_shopping_cart_rounded, () => const PurchasesScreen(), group: 'Stock', color: Tw.emerald500),
      if (app.allowed(Mod.expenses, Perm.expenses)) _Item('Expenses', Icons.receipt_rounded, () => const ExpensesScreen(), group: 'Money', color: Tw.rose500),
      if (app.allowed(Mod.accounts, Perm.accounts)) _Item('Accounts', Icons.account_balance_rounded, () => const AccountsScreen(), group: 'Money', color: Tw.indigo500),
      if (app.allowed(Mod.reports, Perm.reports))
        _Item('Reports', Icons.insights_rounded, () => const ReportsScreen(), feature: Feature.reports, group: 'Money', color: Tw.violet500),
      if (app.allowed(Mod.returns, Perm.returns)) _Item('Returns', Icons.assignment_return_rounded, () => const ReturnsScreen(), group: 'Money', color: Tw.amber500),
      if (app.allowed(Mod.employees, Perm.employees))
        _Item('Employees', Icons.badge_rounded, () => const EmployeesScreen(), feature: Feature.employees, group: 'People', color: Tw.indigo500),
      if (app.can(Perm.employees))
        _Item('Activity log', Icons.history_rounded, () => const ActivityLogScreen(), feature: Feature.employees, group: 'People', color: Tw.slate400),
      if (app.can(Perm.backup)) _Item('Backup & restore', Icons.cloud_sync_rounded, () => const BackupScreen(), color: Tw.sky400),
      if (cloud.configured) _Item('Account', Icons.account_circle_rounded, () => const AccountScreen(), color: Tw.indigo500),
      if (cloud.isAdmin) _Item('Super admin', Icons.admin_panel_settings_rounded, () => const AdminGate(), color: Tw.fuchsia500),
      _Item('Shop QR', Icons.qr_code_2_rounded, () => const StoreQrScreen(), color: Tw.slate400),
      _Item('Plan & upgrades', Icons.workspace_premium_rounded, () => const PlanScreen(), color: Tw.amber500),
      _Item('Settings', Icons.settings_rounded, () => const SettingsScreen(), color: Tw.slate400),
    ];
    final cols = (MediaQuery.sizeOf(context).width / 100).floor().clamp(4, 8).toInt();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final access = Access.instance;
    void openItem(_Item it) {
      void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => it.page()));
      if (it.feature == null) return open();
      openFeature(context, it.feature!, open);
    }

    Widget tile(_Item it) {
      final locked = it.feature != null && !access.has(it.feature!);
      return Material(
        color: theme.cardTheme.color,
        shape: theme.cardTheme.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openItem(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [it.color.withOpacity(0.28), it.color.withOpacity(0.12)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(it.icon, size: 24, color: it.color),
                ),
                if (locked)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Tw.amber500, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_rounded, size: 11, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(tr(it.label),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface, height: 1.2)),
            ]),
          ),
        ),
      );
    }

    const groups = ['Stock', 'People', 'Money', 'Business'];
    final name = app.user?.name ?? '?';
    return Scaffold(
      appBar: AppBar(title: Text(tr('More'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [Tw.indigo500.withOpacity(0.22), Tw.violet600.withOpacity(0.10)]),
            border: Border.all(color: Tw.indigo500.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text(name.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text('${app.businessName} · ${tr(access.planName)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
              ]),
            ),
            FilledButton.tonalIcon(
              onPressed: app.lock,
              icon: const Icon(Icons.lock_outline_rounded, size: 18),
              label: Text(tr('Lock')),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ]),
        ),
        for (final g in groups)
          if (items.any((i) => i.group == g)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
              child: Text(tr(g).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
            ),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [for (final it in items.where((i) => i.group == g)) tile(it)],
            ),
          ],
        ]),
      ),
    );
  }
}
