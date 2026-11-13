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
import '../tokens.dart';
import 'auth/auth_widgets.dart';
import 'account_screen.dart';
import 'admin/super_admin_hub.dart';

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

  /// Employees enrolled for fingerprint unlock on this phone (owner and staff).
  List<Employee> _bioEmployees = [];
  bool _pendingViaPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    final ids = await BiometricService.enrolled();
    if (ids.isEmpty || !await BiometricService.available()) return;
    final list = <Employee>[];
    for (final id in ids) {
      final rows = await Db.instance.s.q('SELECT * FROM employees WHERE id = ? AND deleted_at IS NULL AND active = 1', [id]);
      if (rows.isEmpty) {
        await BiometricService.remove(id);
      } else {
        list.add(Employee.fromRow(rows.first));
      }
    }
    if (list.isEmpty || !mounted) return;
    final last = await BiometricService.last();
    list.sort((a, b) => a.id == last ? -1 : (b.id == last ? 1 : a.name.compareTo(b.name)));
    if (!mounted) return;
    setState(() => _bioEmployees = list);
    _biometricUnlock(list.first);
  }

  Future<void> _biometricUnlock(Employee e) async {
    if (_busy || _mode != 'login') return;
    final ok = await BiometricService.authenticate('${tr('Unlock BizPOS')}: ${e.name}');
    if (!ok || !mounted) return;
    await BiometricService.setLast(e.id);
    await _afterCredentials(e);
  }

  /// After a PIN sign-in, offers fingerprint unlock once per person.
  Future<void> _offerBiometric(Employee e) async {
    if (await BiometricService.isEnrolled(e.id) || await BiometricService.offered(e.id)) return;
    if (!await BiometricService.available() || !mounted) return;
    await BiometricService.markOffered(e.id);
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint_rounded, size: 44, color: Tw.indigo400),
        title: Text(tr('Unlock with fingerprint next time?')),
        content: Text('${e.name}: ${tr('use your fingerprint instead of typing the PIN. You can turn it off in Settings.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Not now'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Turn on'))),
        ],
      ),
    );
    if (yes != true) return;
    if (await BiometricService.authenticate(tr('Confirm your fingerprint to turn on fingerprint unlock'))) {
      await BiometricService.enroll(e.id);
      await BiometricService.setLast(e.id);
    }
  }

  /// PIN or fingerprint accepted: ask for the authenticator code if 2FA is on.
  Future<void> _afterCredentials(Employee e, {bool viaPin = false}) async {
    final row = await Db.instance.s.byId('employees', e.id);
    final secret = row?['totp_secret'] as String?;
    if (!mounted) return;
    if (secret != null && secret.isNotEmpty) {
      setState(() {
        _busy = false;
        _pin = '';
        _pending = e;
        _pendingSecret = secret;
        _pendingViaPin = viaPin;
        _mode = 'totp';
      });
      return;
    }
    if (viaPin) await _offerBiometric(e);
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
        if (_pendingViaPin) await _offerBiometric(_pending!);
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
    await _afterCredentials(e, viaPin: true);
  }

  String get _prompt => switch (_mode) {
        'totp' => 'Enter the 6-digit authenticator code',
        'new' => 'Choose a new owner PIN',
        'confirm' => 'Confirm the new PIN',
        _ => 'Enter PIN',
      };

  @override
  Widget build(BuildContext context) {
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
                            boxShadow: Tw.glow(Tw.indigo500, opacity: 0.4),
                          ),
                          child: (app.settings['logo'] ?? '').isNotEmpty
                              ? ClipOval(child: ProductThumb(image: app.settings['logo'], name: app.businessName, size: 76))
                              : const BrandMark(size: 76),
                        ),
                        const SizedBox(height: 12),
                        Text(app.businessName,
                            style: const TextStyle(fontFamily: Tw.font, fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(tr(_prompt), style: const TextStyle(fontSize: 15, color: Tw.slate400), textAlign: TextAlign.center),
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
                                color: i < _pin.length ? Tw.indigo400 : Tw.slate700,
                                boxShadow: i < _pin.length ? [BoxShadow(color: Tw.indigo500.withOpacity(0.6), blurRadius: 8)] : null,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 30,
                          child: Center(child: Text(_error ?? '', style: const TextStyle(color: Tw.rose400, fontWeight: FontWeight.w600))),
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
                        if (_bioEmployees.isNotEmpty && _mode == 'login')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                              for (final e in _bioEmployees)
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _biometricUnlock(e),
                                  icon: const Icon(Icons.fingerprint_rounded, size: 24),
                                  label: Text(e.name),
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                                ),
                            ]),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          tr('Forgot your PIN? The owner can reset it in Employees.'),
                          style: const TextStyle(fontSize: 12, color: Tw.slate500),
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
            Wrap(alignment: WrapAlignment.center, children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Tw.slate400),
                onPressed: () async {
                  if (await confirm(context, 'Switch store',
                      'Sign out of this store? Its data stays on this phone. You can open another store or sign in with another account.')) {
                    if (context.mounted) await signOutAndSwitch(context);
                  }
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(tr('Switch store')),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Tw.slate400),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminHub())),
                icon: const Icon(Icons.admin_panel_settings, size: 18),
                label: Text(tr('Super admin')),
              ),
            ]),
            const VendorFooter(onDark: true),
          ]),
        ),
      ),
    );
  }
}
