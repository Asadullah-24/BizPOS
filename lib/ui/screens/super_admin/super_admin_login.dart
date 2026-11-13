import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/license.dart';
import '../../../core/totp.dart';
import '../../brand.dart';
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.admin_panel_settings, size: 52),
                    const SizedBox(height: 8),
                    Text(tr('Super admin'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      obscureText: !_show,
                      decoration: InputDecoration(
                        labelText: tr('Master password'),
                        suffixIcon: IconButton(
                          icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(labelText: tr('Authenticator code (2FA)')),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _login,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('Sign in')),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
