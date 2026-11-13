import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/access.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../core/packages.dart';
import '../../services/alert_service.dart';
import '../../services/cloud_service.dart';
import '../common.dart';
import 'activation_screen.dart';
import 'auth/welcome_screen.dart';
import 'scanner_screen.dart';

/// Shop side: current plan, packages, 24-hour ad unlocks and offline codes.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  Future<void> _apply(String? code) async {
    if (code == null || code.trim().isEmpty) return;
    await guard(context, () async {
      final msg = await LicenseService.instance.apply(code);
      if (mounted) showSnack(context, msg);
    });
  }

  Future<void> _request(Package p) async {
    final ok = await guard(context, () => CloudService.instance.requestUpgrade(p));
    if (!ok || !mounted) return;
    showSnack(context, tr('Request sent. BizPOS will activate it after payment.'));
    VendorContact.whatsapp('I requested the ${p.name} plan (${p.price}) for ${CloudService.instance.shop?['name'] ?? 'my shop'}. '
        'Device ${LicenseService.instance.deviceCodePretty}.');
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<Access>();
    final cloud = context.watch<CloudService>();
    final lic = LicenseService.instance;
    final cs = Theme.of(context).colorScheme;
    final status = !access.isPaid
        ? tr('Free')
        : (access.expiresAt == 0 ? tr('Lifetime') : '${tr('Valid until')} ${Fmt.date(access.expiresAt)} (${access.daysLeft} ${tr('days left')})');
    return Scaffold(
      appBar: AppBar(title: Text(tr('Plan and upgrades'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: access.blocked ? cs.errorContainer : (access.isPaid ? cs.primaryContainer : cs.surfaceContainerHighest),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(access.planName), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(access.blocked ? tr('Blocked. Contact BizPOS support.') : status),
              Text('${tr('Device code')}: ${lic.deviceCodePretty}'),
            ]),
          ),
        ),
        const SectionTitle('Features'),
        for (final f in Feature.all)
          ListTile(
            dense: true,
            leading: Icon(access.has(f) ? Icons.check_circle : Icons.lock, color: access.has(f) ? Colors.green : cs.outline),
            title: Text(tr(Feature.labels[f]!)),
          ),
        const SectionTitle('Plans'),
        if (!cloud.configured || !cloud.ready)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(tr('Online plans need an internet connection. You can also use an unlock code below.')))
        else if (!cloud.signedIn)
          Card(
            child: ListTile(
              leading: const Icon(Icons.login),
              title: Text(tr('Sign in to buy a plan')),
              subtitle: Text(tr('Your plan stays with your account, even on a new phone.')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelcomeScreen(linkOnly: true))),
            ),
          )
        else
          StreamBuilder<List<Package>>(
            stream: cloud.packages(),
            builder: (ctx, snap) {
              final list = snap.data ?? [];
              if (snap.connectionState == ConnectionState.waiting && list.isEmpty) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              if (list.isEmpty) return Text(tr('No plans published yet.'));
              return Column(children: [
                for (final p in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(p.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          Text(p.price, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                        ]),
                        if (p.description.isNotEmpty) Text(p.description),
                        for (final f in p.features) Text('• ${tr(Feature.labels[f] ?? f)}'),
                        Text('• ${p.days == 0 ? tr('Lifetime') : '${p.days} ${tr('days')}'}'),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton.tonal(onPressed: () => _request(p), child: Text(tr('Request this plan'))),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        const SectionTitle('Unlock code (offline)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('No internet at the shop? Your BizPOS agent can give a signed code for this phone.')),
              const SizedBox(height: 8),
              Center(child: QrImageView(data: deviceQr(lic.deviceCode), size: 130, backgroundColor: Colors.white)),
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
            ]),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => VendorContact.whatsapp('I want to upgrade BizPOS. Device code: ${lic.deviceCodePretty}'),
          icon: const Icon(Icons.chat, color: Colors.green),
          label: Text('${tr('WhatsApp')} ${Vendor.pretty(lic.phone)}'),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
