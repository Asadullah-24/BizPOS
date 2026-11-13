import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/db.dart';
import '../../../core/i18n.dart';
import '../../../services/cloud_service.dart';
import '../../brand.dart';
import '../../tokens.dart';
import 'auth_widgets.dart';

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

const _rememberKey = 'auth_last_email';

/// Email sign-in and sign-up, switchable with the tabs at the top.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.signUp = false, this.initialEmail});
  final bool signUp;

  /// Prefilled email (choosing a store on this phone).
  final String? initialEmail;

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
  bool _googleBusy = false;
  bool _remember = true;
  String? _error;
  AutovalidateMode _validate = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    final last = widget.initialEmail ?? Local.prefs.getString(_rememberKey);
    if (last != null && !widget.signUp) _email.text = last;
    _password.addListener(() {
      if (_signUp) setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switch(bool signUp) {
    if (signUp == _signUp) return;
    setState(() {
      _signUp = signUp;
      _error = null;
      _validate = AutovalidateMode.disabled;
    });
    _form.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      setState(() => _validate = AutovalidateMode.onUserInteraction);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cloud = CloudService.instance;
      final email = _email.text.trim();
      if (_signUp) {
        await cloud.signUp(name: _name.text.trim(), email: email, password: _password.text);
      } else {
        await cloud.signIn(email, _password.text);
      }
      if (_remember) {
        await Local.prefs.setString(_rememberKey, email);
      } else {
        await Local.prefs.remove(_rememberKey);
      }
      TextInput.finishAutofillContext();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = tr(authError(e)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _google() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      await CloudService.instance.signInWithGoogle();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = tr(authError(e)));
    }
    if (mounted) setState(() => _googleBusy = false);
  }

  Future<void> _forgot() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tw.slate900,
      builder: (ctx) => Theme(data: authTheme(ctx), child: _ForgotSheet(initialEmail: _email.text.trim())),
    );
    if (sent == true && mounted) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final busy = _busy || _googleBusy;
    return AuthScaffold(
      showBack: true,
      child: FadeSlideIn(
        child: GlassCard(
          padding: const EdgeInsets.all(Tw.s6),
          child: AutofillGroup(
            child: Form(
              key: _form,
              autovalidateMode: _validate,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Tabs(signUp: _signUp, onChanged: busy ? null : _switch),
                const SizedBox(height: Tw.s6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    key: ValueKey(_signUp),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(_signUp ? 'Create your account' : 'Welcome back'),
                        style: const TextStyle(fontFamily: Tw.font, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: Tw.s1),
                      Text(
                        tr(_signUp ? 'Free forever. Upgrade any time.' : 'Sign in to your BizPOS account'),
                        style: const TextStyle(color: Tw.slate400, fontSize: 14.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Tw.s5),
                if (_error != null) ...[
                  AuthBanner(text: _error!),
                  const SizedBox(height: Tw.s4),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _signUp
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: Tw.s3),
                          child: TextFormField(
                            controller: _name,
                            enabled: !busy,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: InputDecoration(labelText: tr('Your name'), prefixIcon: const Icon(Icons.person_outline_rounded)),
                            validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter your name.') : null,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                TextFormField(
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: tr('Email'), hintText: 'name@example.com', prefixIcon: const Icon(Icons.mail_outline_rounded)),
                  validator: validateEmail,
                ),
                const SizedBox(height: Tw.s3),
                TextFormField(
                  controller: _password,
                  enabled: !busy,
                  obscureText: !_show,
                  textInputAction: _signUp ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: (_) => _signUp ? null : _submit(),
                  autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: tr('Password'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: tr(_show ? 'Hide password' : 'Show password'),
                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                  validator: _signUp ? validatePassword : (v) => (v ?? '').isEmpty ? tr('Enter your password.') : null,
                ),
                if (_signUp) ...[
                  PasswordStrength(password: _password.text),
                  Padding(
                    padding: const EdgeInsets.only(top: Tw.s1),
                    child: Text(tr('At least 8 characters with letters and numbers.'),
                        style: const TextStyle(color: Tw.slate500, fontSize: 12)),
                  ),
                  const SizedBox(height: Tw.s3),
                  TextFormField(
                    controller: _confirm,
                    enabled: !busy,
                    obscureText: !_show,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: tr('Confirm password'), prefixIcon: const Icon(Icons.lock_reset_rounded)),
                    validator: (v) => v != _password.text ? tr('Passwords do not match.') : null,
                  ),
                ],
                const SizedBox(height: Tw.s2),
                Row(children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(value: _remember, onChanged: busy ? null : (v) => setState(() => _remember = v ?? true)),
                  ),
                  const SizedBox(width: Tw.s2),
                  GestureDetector(
                    onTap: () => setState(() => _remember = !_remember),
                    child: Text(tr('Remember my email'), style: const TextStyle(color: Tw.slate300, fontSize: 13.5)),
                  ),
                  const Spacer(),
                  if (!_signUp) TextButton(onPressed: busy ? null : _forgot, child: Text(tr('Forgot password?'))),
                ]),
                const SizedBox(height: Tw.s4),
                GradientButton(
                  label: tr(_signUp ? 'Create account' : 'Sign in'),
                  busy: _busy,
                  onPressed: _googleBusy ? null : _submit,
                ),
                const OrDivider(),
                GoogleButton(onPressed: _busy ? null : _google, busy: _googleBusy),
                const SizedBox(height: Tw.s4),
                Center(
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tr(_signUp ? 'Already have an account?' : 'New to BizPOS?'), style: const TextStyle(color: Tw.slate400, fontSize: 14)),
                    TextButton(
                      onPressed: busy ? null : () => _switch(!_signUp),
                      child: Text(tr(_signUp ? 'Sign in' : 'Create a free account')),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented "Sign in | Create account" switch.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.signUp, required this.onChanged});
  final bool signUp;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) {
      final selected = signUp == value;
      return Expanded(
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Tw.slate700 : Colors.transparent,
              borderRadius: BorderRadius.circular(Tw.rLg + 2),
              boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))] : null,
            ),
            child: Text(
              tr(label),
              style: TextStyle(fontFamily: Tw.font, fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : Tw.slate400),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(Tw.s1),
      decoration: BoxDecoration(
        color: Tw.slate950.withOpacity(0.7),
        borderRadius: BorderRadius.circular(Tw.rXl),
        border: Border.all(color: Tw.slate800),
      ),
      child: Row(children: [tab('Sign in', false), tab('Create account', true)]),
    );
  }
}

/// Bottom sheet that sends a password reset link.
class _ForgotSheet extends StatefulWidget {
  const _ForgotSheet({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ForgotSheet> createState() => _ForgotSheetState();
}

class _ForgotSheetState extends State<_ForgotSheet> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudService.instance.resetPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = tr(authError(e)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Tw.s6, Tw.s2, Tw.s6, MediaQuery.viewInsetsOf(context).bottom + Tw.s6),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Tw.indigo500.withOpacity(0.15), borderRadius: BorderRadius.circular(Tw.rXl)),
            child: const Icon(Icons.key_rounded, color: Tw.indigo300),
          ),
          const SizedBox(height: Tw.s4),
          Text(tr('Reset your password'),
              style: const TextStyle(fontFamily: Tw.font, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: Tw.s1),
          Text(tr('We will email you a link to choose a new password.'), style: const TextStyle(color: Tw.slate400, fontSize: 14)),
          const SizedBox(height: Tw.s5),
          if (_sent)
            AuthBanner(success: true, text: '${tr('Password reset link sent. Check your email (and spam folder).')}\n${tr('It comes from noreply@bizpos-7e092.firebaseapp.com. No email? Make sure this is the email you signed up with.')}')
          else ...[
            if (_error != null) ...[AuthBanner(text: _error!), const SizedBox(height: Tw.s3)],
            TextFormField(
              controller: _email,
              autofocus: widget.initialEmail.isEmpty,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Email'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
              validator: validateEmail,
              onFieldSubmitted: (_) => _send(),
            ),
          ],
          const SizedBox(height: Tw.s5),
          if (_sent)
            OutlinedButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Back to sign in')))
          else
            GradientButton(label: tr('Send reset link'), busy: _busy, onPressed: _send),
        ]),
      ),
    );
  }
}
