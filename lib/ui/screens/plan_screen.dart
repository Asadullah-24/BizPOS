import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../core/packages.dart';
import '../../services/ads_service.dart';
import '../../services/alert_service.dart';
import '../common.dart';
import 'activation_screen.dart';
import 'scanner_screen.dart';
import 'super_admin/super_admin_console.dart';

/// Shop side: current plan, paid features, credits and upgrade codes.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _busy = false;

  Future<void> _apply(String? code) async {
    if (code == null || code.trim().isEmpty) return;
    await guard(context, () async {
      final msg = await LicenseService.instance.apply(code);
      if (mounted) showSnack(context, msg);
    });
  }

  Future<void> _watchAd() async {
    setState(() => _busy = true);
    await guard(context, () async {
      final got = await AdsService.watchForCredits();
      if (mounted) showSnack(context, got > 0 ? '+$got ${tr('credits')}' : tr('Watch the whole ad to earn credits.'));
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final cs = Theme.of(context).colorScheme;
    final status = !lic.active
        ? tr('Expired')
        : (lic.planExpires == 0 ? tr('Lifetime') : '${tr('Valid until')} ${Fmt.date(lic.planExpires)} (${lic.daysLeft} ${tr('days left')})');
    return Scaffold(
      appBar: AppBar(title: Text(tr('Plan and upgrades'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: lic.active ? cs.primaryContainer : cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(lic.plan.name), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(status),
              if (lic.storeName != null) Text('${tr('Shop')}: ${lic.storeName}'),
              Text('${tr('Device code')}: ${lic.deviceCodePretty}'),
            ]),
          ),
        ),
        const SectionTitle('Paid features'),
        for (final f in Feature.all)
          ListTile(
            dense: true,
            leading: Icon(lic.has(f) ? Icons.check_circle : Icons.lock, color: lic.has(f) ? Colors.green : cs.outline),
            title: Text(tr(Feature.labels[f]!)),
          ),
        const SectionTitle('Voice credits'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(lic.has(Feature.voice) ? tr('Unlimited (Pro)') : '${Fmt.qty(lic.credits)} ${tr('credits')}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _watchAd,
                icon: const Icon(Icons.ondemand_video),
                label: Text('${tr('Watch an ad')} (+${Credits.perAd})'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => VendorContact.whatsapp('I want to buy BizPOS voice credits. Device code: ${lic.deviceCodePretty}'),
                icon: const Icon(Icons.shopping_cart),
                label: Text(tr('Buy credits')),
              ),
            ]),
          ),
        ),
        const SectionTitle('Unlock code'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('After payment your BizPOS agent sends a code or QR. Show them this QR so they get the right device.')),
              const SizedBox(height: 8),
              Center(child: QrImageView(data: deviceQr(lic.deviceCode), size: 140, backgroundColor: Colors.white)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async => _apply(await ScannerScreen.scan(context)),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(tr('Scan code')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async => _apply(await enterCodeDialog(context, title: 'Enter unlock code')),
                icon: const Icon(Icons.key),
                label: Text(tr('Enter code')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => VendorContact.whatsapp('I want to upgrade BizPOS to ${Plans.pro.name}. Device code: ${lic.deviceCodePretty}'),
                icon: const Icon(Icons.chat, color: Colors.green),
                label: Text('${tr('Upgrade on WhatsApp')} ${Vendor.pretty(lic.phone)}'),
              ),
            ]),
          ),
        ),
        const SectionTitle('Packages'),
        const PackagesList(shrink: true),
      ]),
    );
  }
}
