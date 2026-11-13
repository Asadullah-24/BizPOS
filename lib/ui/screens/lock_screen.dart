import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/i18n.dart';
import '../../core/totp.dart';
import '../../models/models.dart';
import '../../services/activity_log.dart';
import '../../services/alert_service.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/cloud_service.dart';
import '../../services/drive_service.dart';
import '../brand.dart';
import '../common.dart';
import 'super_admin/super_admin_login.dart';

/// Sign-in screen shown above the whole app while nobody is signed in.
/// PIN keypad, optional authenticator code (2FA), owner PIN recovery with
/// Google, and the super admin entrance.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  /// login | totp | new | confirm
  String _mode = 'login';
  String _newPin = '';
  Employee? _pending;
  String? _pendingSecret;

  /// Employee enrolled for fingerprint unlock on this phone, if any.
  Employee? _bioEmployee;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    final id = await BiometricService.enrolledEmployee();
    if (id == null) return;
    final rows = await Db.instance.s.q(
      'SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL AND active = 1',
      [id],
    );
    if (rows.isEmpty) {
      await BiometricService.disable();
      return;
    }
    if (!await BiometricService.available()) return;
    if (!mounted) return;
    setState(() => _bioEmployee = Employee.fromRow(rows.first));
    _biometricUnlock();
  }

  Future<void> _biometricUnlock() async {
    final e = _bioEmployee;
    if (e == null || _busy || _mode != 'login') return;
    final ok = await BiometricService.authenticate(tr('Unlock BizPOS'));
    if (!ok || !mounted) return;
    await _afterCredentials(e);
  }

  /// PIN or fingerprint accepted: ask for the authenticator code if 2FA is on.
  Future<void> _afterCredentials(Employee e) async {
    final row = await Db.instance.s.byId('employees', e.id);
    final secret = row?['totp_secret'] as String?;
    if (!mounted) return;
    if (secret != null && secret.isNotEmpty) {
      setState(() {
        _busy = false;
        _pin = '';
        _pending = e;
        _pendingSecret = secret;
        _mode = 'totp';
      });
      return;
    }
    await _finishLogin(e);
  }

  int get _maxLen => _mode == 'totp' ? 6 : 8;

  void _press(String d) {
    if (_busy || _pin.length >= _maxLen) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_mode == 'totp' && _pin.length == 6) _submit();
  }

  void _back() {
    if (_pin.isEmpty) {
      if (_mode != 'login') {
        setState(() {
          _mode = 'login';
          _pending = null;
        });
      }
      return;
    }
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _finishLogin(Employee e) async {
    await AppState.instance.login(e);
    DriveService.instance.start();
    AlertService.runChecks();
  }

  Future<void> _forgot() async {
    final cloud = CloudService.instance;
    if (cloud.signedIn) {
      String? password;
      if (cloud.usesPassword) {
        final c = TextEditingController();
        password = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Confirm it is you')),
            content: TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: '${tr('Account password for')} ${cloud.user?.email ?? ''}'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Continue'))),
            ],
          ),
        );
        if (password == null) return;
      }
      setState(() => _busy = true);
      try {
        await cloud.reauthenticate(password: password);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _pin = '';
          _mode = 'new';
          _error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = tr(authError(e));
        });
      }
      return;
    }
    setState(() => _busy = true);
    final ok = await DriveService.instance.verifyBackupAccount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      if (ok) {
        _mode = 'new';
        _error = null;
      } else {
        _error = tr('That is not the Google account used for backup.');
      }
    });
  }

  Future<void> _resetStep() async {
    if (_mode == 'new') {
      setState(() {
        _newPin = _pin;
        _pin = '';
        _mode = 'confirm';
      });
      return;
    }
    if (_pin != _newPin) {
      setState(() {
        _pin = '';
        _mode = 'new';
        _error = tr('PINs do not match.');
      });
      return;
    }
    setState(() => _busy = true);
    final r = await Db.instance.s.one('SELECT * FROM employees WHERE is_owner = 1 AND deleted_at IS NULL LIMIT 1');
    if (r == null || !mounted) return;
    final owner = Employee.fromRow(r);
    await Db.instance.s.update('employees', owner.id, AuthService.pinColumns(_pin));
    await ActivityLog.add('Owner PIN reset with Google account', entity: 'employee', entityId: owner.id);
    await _finishLogin(owner);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_mode == 'totp') {
      if (_pin.length != 6) return;
      if (Totp.verify(_pendingSecret!, _pin)) {
        await _finishLogin(_pending!);
      } else {
        setState(() {
          _pin = '';
          _error = tr('Wrong code');
        });
      }
      return;
    }
    if (_pin.length < 4) return;
    if (_mode != 'login') return _resetStep();
    setState(() => _busy = true);
    final e = await AuthService.login(_pin);
    if (!mounted) return;
    if (e == null) {
      setState(() {
        _busy = false;
        _pin = '';
        _error = tr('Wrong PIN');
      });
      return;
    }
    await _afterCredentials(e);
  }

  String get _prompt => switch (_mode) {
        'totp' => 'Enter the 6-digit authenticator code',
        'new' => 'Choose a new owner PIN',
        'confirm' => 'Confirm the new PIN',
        _ => 'Enter PIN',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = AppState.instance;
    final dots = _mode == 'totp' ? 6 : (_pin.length < 4 ? 4 : _pin.length);
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GlassCard(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
                          ),
                          child: (app.settings['logo'] ?? '').isNotEmpty
                              ? ClipOval(child: ProductThumb(image: app.settings['logo'], name: app.businessName, size: 76))
                              : CircleAvatar(
                                  radius: 38,
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.storefront, size: 40, color: cs.onPrimaryContainer),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Text(app.businessName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(tr(_prompt), style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            dots,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              width: 15,
                              height: 15,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _pin.length ? cs.primary : cs.outlineVariant,
                                boxShadow: i < _pin.length ? [BoxShadow(color: cs.primary.withOpacity(0.5), blurRadius: 6)] : null,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 30,
                          child: Center(child: Text(_error ?? '', style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final row in const [
                              ['1', '2', '3'],
                              ['4', '5', '6'],
                              ['7', '8', '9'],
                            ])
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                for (final d in row) Padding(padding: const EdgeInsets.all(6), child: Key3D(label: d, onTap: () => _press(d))),
                              ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Padding(padding: const EdgeInsets.all(6), child: Key3D(icon: Icons.backspace_outlined, onTap: _back)),
                              Padding(padding: const EdgeInsets.all(6), child: Key3D(label: '0', onTap: () => _press('0'))),
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Key3D(icon: _busy ? Icons.hourglass_top : Icons.arrow_forward, accent: true, onTap: _submit),
                              ),
                            ]),
                          ]),
                        ),
                        if (_bioEmployee != null && _mode == 'login')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _biometricUnlock,
                              icon: const Icon(Icons.fingerprint, size: 28),
                              label: Text('${tr('Unlock with fingerprint')} (${_bioEmployee!.name})'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          tr('Forgot your PIN? The owner can reset it in Employees.'),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        if (_mode == 'login' && (CloudService.instance.signedIn || DriveService.instance.enabled))
                          TextButton(
                            onPressed: _busy ? null : _forgot,
                            child: Text(tr(CloudService.instance.signedIn ? 'Owner forgot PIN? Sign in again' : 'Owner forgot PIN? Verify with Google')),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminLogin())),
              icon: const Icon(Icons.admin_panel_settings, size: 18),
              label: Text(tr('Super admin')),
            ),
            const VendorFooter(onDark: true),
          ]),
        ),
      ),
    );
  }
}
