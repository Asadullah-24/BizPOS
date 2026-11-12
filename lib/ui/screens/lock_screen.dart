import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../services/auth_service.dart';
import '../../services/drive_service.dart';

/// PIN keypad shown above the whole app while nobody is signed in.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => FocusManager.instance.primaryFocus?.unfocus());
  }

  void _press(String d) {
    if (_busy || _pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
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
    await AppState.instance.login(e);
    DriveService.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = AppState.instance;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 76,
            height: 64,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: onTap ?? () => _press(label),
              child: icon != null ? Icon(icon, size: 26) : Text(label, style: const TextStyle(fontSize: 26)),
            ),
          ),
        );

    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.storefront, size: 36, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              Text(app.businessName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(tr('Enter PIN'), style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  _pin.length < 4 ? 4 : _pin.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 32,
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
                    Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    key('', icon: Icons.backspace_outlined, onTap: _back),
                    key('0'),
                    key('', icon: _busy ? Icons.hourglass_top : Icons.arrow_forward, onTap: _submit),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Text(
                tr('Forgot your PIN? The owner can reset it in Employees.'),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
