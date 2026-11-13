import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/license.dart';
import '../../../core/totp.dart';
import '../../brand.dart';
import '../../tokens.dart';
import '../auth/auth_widgets.dart';
import 'super_admin_console.dart';

/// Super admin sign-in: master password plus authenticator code (2FA).
class SuperAdminLogin extends StatefulWidget {
  const SuperAdminLogin({super.key});

  @override
  State<SuperAdminLogin> createState() => _SuperAdminLoginState();
}

class _SuperAdminLoginState extends State<SuperAdminLogin> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;
  int _fails = 0;
  DateTime? _lockedUntil;

  Future<void> _login() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      setState(() => _error = tr('Too many attempts. Wait 30 seconds.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final key = await LicenseKeys.derive(_password.text);
    if (!mounted) return;
    final ok = key.isTrusted && Totp.verify(key.totpSecret, _code.text);
    if (!ok) {
      _fails++;
      if (_fails >= 5) {
        _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _fails = 0;
      }
      setState(() {
        _busy = false;
        _error = tr(key.isTrusted ? 'Wrong authenticator code.' : 'Wrong password.');
      });
      return;
    }
    SuperAdmin.key = key;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SuperAdminConsole()));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      child: GlassCard(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: Tw.amber400.withOpacity(0.15), borderRadius: BorderRadius.circular(Tw.r2xl)),
              child: const Icon(Icons.qr_code_2_rounded, color: Tw.amber400, size: 30),
            ),
          ),
          const SizedBox(height: Tw.s3),
          Text(tr('Offline unlock codes'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: Tw.font, fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: Tw.s1),
          Text(tr('Master password and authenticator code'), textAlign: TextAlign.center, style: const TextStyle(color: Tw.slate400)),
          const SizedBox(height: Tw.s5),
          if (_error != null) ...[AuthBanner(text: _error!), const SizedBox(height: Tw.s3)],
          TextField(
            controller: _password,
            obscureText: !_show,
            decoration: InputDecoration(
              labelText: tr('Master password'),
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: Tw.s3),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(labelText: tr('Authenticator code (2FA)'), prefixIcon: const Icon(Icons.pin_outlined), counterText: ''),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: Tw.s5),
          GradientButton(label: tr('Sign in'), busy: _busy, onPressed: _login),
        ]),
      ),
    );
  }
}
