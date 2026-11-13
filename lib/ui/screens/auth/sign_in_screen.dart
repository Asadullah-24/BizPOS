import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../services/cloud_service.dart';
import '../../brand.dart';
import '../../common.dart';

String? validateEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return tr('Enter your email.');
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return tr('That email address is not valid.');
  return null;
}

String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return tr('At least 8 characters.');
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) return tr('Use letters and numbers.');
  return null;
}

/// Email sign-in and sign-up on the animated dark backdrop.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.signUp = false});
  final bool signUp;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _signUp = widget.signUp;
  bool _show = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cloud = CloudService.instance;
      if (_signUp) {
        await cloud.signUp(name: _name.text, email: _email.text, password: _password.text);
      } else {
        await cloud.signIn(_email.text, _password.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = tr(authError(e)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgot() async {
    final err = validateEmail(_email.text);
    if (err != null) {
      setState(() => _error = tr('Enter your email above, then tap "Forgot password".'));
      return;
    }
    await guard(context, () => CloudService.instance.resetPassword(_email.text),
        success: 'Password reset link sent. Check your email (and spam folder).');
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: tr(label),
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Theme.of(context).colorScheme.primary, brightness: Brightness.dark),
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(fillColor: Colors.white.withOpacity(0.06)),
      filledButtonTheme: Theme.of(context).filledButtonTheme,
    );
    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
        body: AnimatedBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: FadeSlideIn(
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111A2E).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 40, offset: const Offset(0, 20))],
                      ),
                      child: Form(
                        key: _form,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              tr(_signUp ? 'Create your account' : 'Welcome back'),
                              key: ValueKey(_signUp),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(_signUp ? 'Free forever. Upgrade any time.' : 'Sign in to your BizPOS account'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 20),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            child: _signUp
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextFormField(
                                      controller: _name,
                                      textCapitalization: TextCapitalization.words,
                                      decoration: _dec('Your name', Icons.person_outline),
                                      validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter your name.') : null,
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: _dec('Email', Icons.alternate_email),
                            validator: validateEmail,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: !_show,
                            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                            decoration: _dec('Password', Icons.lock_outline,
                                suffix: IconButton(
                                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _show = !_show),
                                )),
                            validator: _signUp ? validatePassword : (v) => (v ?? '').isEmpty ? tr('Enter your password.') : null,
                          ),
                          if (_signUp) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirm,
                              obscureText: !_show,
                              decoration: _dec('Confirm password', Icons.lock_outline),
                              validator: (v) => v != _password.text ? tr('Passwords do not match.') : null,
                            ),
                          ],
                          if (!_signUp)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(onPressed: _busy ? null : _forgot, child: Text(tr('Forgot password?'))),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(tr(_signUp ? 'Create account' : 'Sign in')),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() {
                              _signUp = !_signUp;
                              _error = null;
                            }),
                            child: Text(tr(_signUp ? 'Have an account? Sign in' : 'New here? Create a free account')),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
