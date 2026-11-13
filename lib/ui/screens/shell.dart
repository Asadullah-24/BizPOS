import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/i18n.dart';
import '../../core/access.dart';
import '../../core/license.dart';
import '../../services/cloud_service.dart';
import '../../core/packages.dart';
import '../brand.dart';
import 'plan_screen.dart';
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
    // Nothing is shown behind the lock screen.
    if (app.locked) return const Scaffold(body: SizedBox.expand());
    final dests = _dests(app);
    if (_index >= dests.length) _index = 0;
    final lic = context.watch<LicenseService>();
    final access = context.watch<Access>();
    final cloud = context.watch<CloudService>();
    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      child: KeyedSubtree(key: ValueKey(dests[_index].label), child: dests[_index].builder()),
    );
    final Widget? banner;
    if (cloud.revokedNotice) {
      banner = _PlanBanner(text: tr('This phone was removed from your account, so its data was erased.'), error: true);
    } else if (access.blocked) {
      banner = _PlanBanner(text: '${tr('This shop is blocked.')} ${tr('Call')} ${Vendor.pretty(lic.phone)}', error: true);
    } else if (access.isPaid && access.expiresAt != 0 && access.daysLeft <= 3) {
      banner = _PlanBanner(text: '${tr(access.planName)}: ${access.daysLeft} ${tr('days left')}. ${tr('Renew to keep paid features.')}');
    } else {
      banner = null;
    }
    final body = Column(children: [
      if (banner != null) banner,
      Expanded(child: page),
      const Material(child: SafeArea(top: false, bottom: false, child: VendorFooter())),
    ]);

    if (isWide(context) && dests.length >= 2) {
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
    if (dests.length < 2) return Scaffold(body: body);
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

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: error ? cs.errorContainer : cs.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          leading: Icon(error ? Icons.block : Icons.timer_outlined),
          title: Text(text),
          trailing: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
            child: Text(tr('Renew')),
          ),
        ),
      ),
    );
  }
}
