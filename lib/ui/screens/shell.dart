import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../common.dart';
import 'dashboard_screen.dart';
import 'more_screen.dart';
import 'pos_screen.dart';
import 'products_screen.dart';
import 'sales_screen.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  List<_Dest> _dests(AppState app) => [
        if (app.can(Perm.dashboard))
          _Dest('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard, () => const DashboardScreen()),
        if (app.allowed(Mod.pos, Perm.sell))
          _Dest('Sell', Icons.point_of_sale_outlined, Icons.point_of_sale, () => const PosScreen()),
        if (app.allowed(Mod.products, Perm.products))
          _Dest('Products', Icons.inventory_2_outlined, Icons.inventory_2, () => const ProductsScreen()),
        if (app.can(Perm.salesView))
          _Dest('Sales', Icons.receipt_long_outlined, Icons.receipt_long, () => const SalesScreen()),
        _Dest('More', Icons.apps_outlined, Icons.apps, () => const MoreScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dests = _dests(app);
    if (_index >= dests.length) _index = 0;
    final body = KeyedSubtree(key: ValueKey(dests[_index].label), child: dests[_index].builder());

    if (isWide(context)) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary, size: 32),
            ),
            destinations: [
              for (final d in dests)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(tr(d.label))),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: tr(d.label)),
        ],
      ),
    );
  }
}
