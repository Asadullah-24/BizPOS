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
  const _Item(this.label, this.icon, this.page, {this.feature});
  final String label;
  final IconData icon;
  final Widget Function() page;

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
        _Item('Inventory', Icons.warehouse_outlined, () => const InventoryScreen()),
      if (app.allowed(Mod.inventory, Perm.inventory) && app.hasModule(Mod.barcode))
        _Item('Scan stock', Icons.qr_code_scanner, () => const StockScanScreen()),
      if (app.allowed(Mod.inventory, Perm.inventory))
        _Item('Voice stock', Icons.mic, () => const VoiceStockScreen(), feature: Feature.voice),
      if (app.allowed(Mod.customers, Perm.customers))
        _Item('Reminders', Icons.notifications_active_outlined, () => const RemindersScreen(), feature: Feature.reminders),
      if (app.can(Perm.products)) _Item('Categories', Icons.category_outlined, () => const CategoriesScreen(kind: 'product')),
      if (app.allowed(Mod.customers, Perm.customers)) _Item('Customers', Icons.people_outline, () => const PartiesScreen(kind: 'customer')),
      if (app.allowed(Mod.suppliers, Perm.suppliers))
        _Item('Suppliers', Icons.local_shipping_outlined, () => const PartiesScreen(kind: 'supplier')),
      if (app.allowed(Mod.purchases, Perm.purchases)) _Item('Purchases', Icons.add_shopping_cart, () => const PurchasesScreen()),
      if (app.allowed(Mod.expenses, Perm.expenses)) _Item('Expenses', Icons.money_off, () => const ExpensesScreen()),
      if (app.allowed(Mod.accounts, Perm.accounts)) _Item('Accounts', Icons.account_balance_outlined, () => const AccountsScreen()),
      if (app.allowed(Mod.reports, Perm.reports))
        _Item('Reports', Icons.bar_chart, () => const ReportsScreen(), feature: Feature.reports),
      if (app.allowed(Mod.returns, Perm.returns)) _Item('Returns', Icons.assignment_return_outlined, () => const ReturnsScreen()),
      if (app.allowed(Mod.employees, Perm.employees))
        _Item('Employees', Icons.badge_outlined, () => const EmployeesScreen(), feature: Feature.employees),
      if (app.can(Perm.employees))
        _Item('Activity log', Icons.history, () => const ActivityLogScreen(), feature: Feature.employees),
      if (app.can(Perm.backup)) _Item('Backup & restore', Icons.cloud_outlined, () => const BackupScreen()),
      if (cloud.configured) _Item('Account', Icons.account_circle_outlined, () => const AccountScreen()),
      if (cloud.isAdmin) _Item('Super admin', Icons.admin_panel_settings, () => const AdminGate()),
      _Item('Shop QR', Icons.qr_code_2, () => const StoreQrScreen()),
      _Item('Plan & upgrades', Icons.workspace_premium_outlined, () => const PlanScreen()),
      _Item('Settings', Icons.settings_outlined, () => const SettingsScreen()),
    ];
    final cols = (MediaQuery.sizeOf(context).width / 150).floor().clamp(3, 6).toInt();
    return Scaffold(
      appBar: AppBar(title: Text(tr('More'))),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(child: Text((app.user?.name ?? '?').characters.first.toUpperCase())),
          title: Text(app.user?.name ?? ''),
          subtitle: Text(app.businessType?.name ?? ''),
          trailing: FilledButton.tonalIcon(onPressed: app.lock, icon: const Icon(Icons.lock_outline), label: Text(tr('Lock'))),
        ),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final it in items)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => it.page()));
                    if (it.feature == null) return open();
                    openFeature(context, it.feature!, open);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(it.icon, size: 34, color: Theme.of(context).colorScheme.primary),
                        if (it.feature != null && !Access.instance.has(it.feature!))
                          const Positioned(right: -10, top: -6, child: Icon(Icons.lock, size: 14, color: Colors.amber)),
                      ]),
                      const SizedBox(height: 8),
                      Text(tr(it.label), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
