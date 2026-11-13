import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../core/packages.dart';
import '../../services/alert_service.dart';
import '../brand.dart';
import '../common.dart';
import 'scanner_screen.dart';
import 'super_admin/super_admin_login.dart';

/// QR payload that identifies a phone to the super admin's scanner.
String deviceQr(String deviceCode) => 'BIZPOS-DEVICE:$deviceCode';

/// Parses a device code from a scanned QR or typed text.
String? parseDeviceCode(String raw) {
  final s = raw.trim().toUpperCase().replaceFirst('BIZPOS-DEVICE:', '').replaceAll('-', '').replaceAll(' ', '');
  return RegExp(r'^[0-9A-F]{8}$').hasMatch(s) ? s : null;
}

Future<String?> enterCodeDialog(BuildContext context, {String title = 'Enter activation code'}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(title)),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(hintText: tr('Paste the code starting with BZ1.')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Apply'))),
      ],
    ),
  );
}

/// Shown until the super admin activates this phone.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, this.expired = false});
  final bool expired;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  bool _busy = false;

  Future<void> _apply(String? code) async {
    if (code == null || code.trim().isEmpty) return;
    setState(() => _busy = true);
    await guard(context, () async {
      final msg = await LicenseService.instance.apply(code);
      if (mounted) showSnack(context, msg);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scan() async {
    final code = await ScannerScreen.scan(context);
    await _apply(code);
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(children: [
                  const Icon(Icons.storefront, size: 56, color: Colors.white),
                  const SizedBox(height: 8),
                  Text('BizPOS',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text(
                    tr(widget.expired ? 'Your plan has ended' : 'Activate this phone'),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  GlassCard(
                    child: Column(children: [
                      Text(tr('Device code'), style: Theme.of(context).textTheme.labelLarge),
                      SelectableText(lic.deviceCodePretty,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      QrImageView(data: deviceQr(lic.deviceCode), size: 170, backgroundColor: Colors.white),
                      const SizedBox(height: 8),
                      Text(
                        tr('Show this QR to your BizPOS agent. They will give you an activation code or QR.'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(tr('Scan activation QR')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () async => _apply(await enterCodeDialog(context)),
                          icon: const Icon(Icons.key),
                          label: Text(tr('Enter activation code')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => VendorContact.whatsapp(
                              'Assalam o Alaikum, please ${widget.expired ? 'renew' : 'activate'} BizPOS for my shop. Device code: ${lic.deviceCodePretty}'),
                          icon: const Icon(Icons.chat, color: Colors.green),
                          label: Text('${tr('WhatsApp')} ${Vendor.pretty(lic.phone)}'),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminLogin())),
                    icon: const Icon(Icons.admin_panel_settings),
                    label: Text(tr('Super admin')),
                  ),
                  const VendorFooter(onDark: true),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
