import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import 'accounts_screen.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'employees_screen.dart';
import 'expenses_screen.dart';
import 'inventory_screen.dart';
import 'parties_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';

class _Item {
  const _Item(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget Function() page;
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = <_Item>[
      if (app.allowed(Mod.inventory, Perm.inventory) || app.allowed(Mod.inventory, Perm.products))
        _Item('Inventory', Icons.warehouse_outlined, () => const InventoryScreen()),
      if (app.can(Perm.products)) _Item('Categories', Icons.category_outlined, () => const CategoriesScreen(kind: 'product')),
      if (app.allowed(Mod.customers, Perm.customers)) _Item('Customers', Icons.people_outline, () => const PartiesScreen(kind: 'customer')),
      if (app.allowed(Mod.suppliers, Perm.suppliers))
        _Item('Suppliers', Icons.local_shipping_outlined, () => const PartiesScreen(kind: 'supplier')),
      if (app.allowed(Mod.purchases, Perm.purchases)) _Item('Purchases', Icons.add_shopping_cart, () => const PurchasesScreen()),
      if (app.allowed(Mod.expenses, Perm.expenses)) _Item('Expenses', Icons.money_off, () => const ExpensesScreen()),
      if (app.allowed(Mod.accounts, Perm.accounts)) _Item('Accounts', Icons.account_balance_outlined, () => const AccountsScreen()),
      if (app.allowed(Mod.reports, Perm.reports)) _Item('Reports', Icons.bar_chart, () => const ReportsScreen()),
      if (app.allowed(Mod.returns, Perm.returns)) _Item('Returns', Icons.assignment_return_outlined, () => const ReturnsScreen()),
      if (app.allowed(Mod.employees, Perm.employees)) _Item('Employees', Icons.badge_outlined, () => const EmployeesScreen()),
      if (app.can(Perm.employees)) _Item('Activity log', Icons.history, () => const ActivityLogScreen()),
      if (app.can(Perm.backup)) _Item('Backup & restore', Icons.cloud_outlined, () => const BackupScreen()),
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => it.page())),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(it.icon, size: 34, color: Theme.of(context).colorScheme.primary),
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
