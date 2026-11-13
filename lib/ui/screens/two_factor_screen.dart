import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/totp.dart';
import '../../services/activity_log.dart';
import '../common.dart';

/// Turns on authenticator (TOTP) codes for the signed-in employee. After the
/// PIN, sign-in then asks for the 6-digit code. Works offline.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _secret = Totp.newSecret();
  final _code = TextEditingController();
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.instance.s.byId('employees', AppState.instance.user!.id);
    setState(() => _enabled = (r?['totp_secret'] as String?)?.isNotEmpty ?? false);
  }

  Future<void> _enable() async {
    if (!Totp.verify(_secret, _code.text)) return showSnack(context, tr('Wrong code. Check the time on this phone.'), error: true);
    await Db.instance.s.update('employees', AppState.instance.user!.id, {'totp_secret': _secret});
    await ActivityLog.add('Two-factor sign-in enabled', entity: 'employee', entityId: AppState.instance.user!.id);
    if (mounted) {
      showSnack(context, tr('Two-factor sign-in is on'));
      Navigator.pop(context);
    }
  }

  Future<void> _disable() async {
    if (!await confirm(context, 'Turn off two-factor', 'Sign-in will only need your PIN.')) return;
    await Db.instance.s.update('employees', AppState.instance.user!.id, {'totp_secret': null});
    await ActivityLog.add('Two-factor sign-in disabled', entity: 'employee', entityId: AppState.instance.user!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = AppState.instance.user!;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Two-factor sign-in'))),
      body: _enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_enabled!) ...[
                const Icon(Icons.verified_user, size: 64, color: Colors.green),
                Text(tr('Two-factor sign-in is on for your account.'), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                OutlinedButton(onPressed: _disable, child: Text(tr('Turn off'))),
              ] else ...[
                Text(tr('1. Install Google Authenticator or Microsoft Authenticator.\n2. Scan this QR.\n3. Enter the 6-digit code it shows.')),
                const SizedBox(height: 16),
                Center(
                  child: QrImageView(
                    data: Totp.uri(secret: _secret, account: '${AppState.instance.businessName} - ${user.name}'),
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
                SelectableText(_secret, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: tr('6-digit code')),
                ),
                FilledButton(onPressed: _enable, child: Text(tr('Turn on'))),
              ],
            ]),
    );
  }
}
