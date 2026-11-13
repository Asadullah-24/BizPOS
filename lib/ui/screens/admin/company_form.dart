import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/business_templates.dart';
import '../../../core/i18n.dart';
import '../../../core/packages.dart';
import '../../../services/cloud_service.dart';
import '../../common.dart';
import '../../tokens.dart';
import '../auth/sign_in_screen.dart';

/// Super admin: create a new company (shop) for a customer, optionally with a
/// paid package, and share the company code with the owner.
class CompanyForm extends StatefulWidget {
  const CompanyForm({super.key});

  @override
  State<CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<CompanyForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _amount = TextEditingController();
  final _password = TextEditingController(text: _newPassword());
  String _type = businessTemplates.first.key;
  String _packageId = '';
  bool _busy = false;
  bool _login = true;
  bool _show = true;

  static String _newPassword() {
    const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
    const digits = '23456789';
    final r = Random.secure();
    final chars = [
      for (var i = 0; i < 6; i++) letters[r.nextInt(letters.length)],
      for (var i = 0; i < 4; i++) digits[r.nextInt(digits.length)],
    ]..shuffle(r);
    return chars.join();
  }

  Future<void> _save(List<Package> packages) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final pkg = _find(packages, _packageId);
      final tpl = businessTemplates.firstWhere((t) => t.key == _type);
      final cloud = CloudService.instance;
      final amount = double.tryParse(_amount.text.trim());
      if (_login) {
        try {
          final id = await cloud.createCompanyWithLogin(
            name: _name.text,
            ownerEmail: _email.text,
            password: _password.text,
            ownerName: _owner.text,
            phone: _phone.text,
            city: _city.text,
            category: tpl.name,
            package: pkg,
            amount: amount,
          );
          if (!mounted) return;
          await showOwnerLogin(context,
              id: id, name: _name.text.trim(), email: _email.text.trim().toLowerCase(), password: _password.text, phone: _phone.text.trim());
        } on FirebaseAuthException catch (e) {
          if (e.code != 'email-already-in-use') rethrow;
          if (!mounted) return;
          final useCode = await confirm(context, 'Email already has an account',
              'This email already has a BizPOS account. Create the company with a code instead? The owner joins it from More > Account > Join a company.');
          if (!useCode) {
            setState(() => _busy = false);
            return;
          }
          final id = await cloud.createCompany(
              name: _name.text, ownerEmail: _email.text, ownerName: _owner.text, phone: _phone.text, city: _city.text,
              category: tpl.name, package: pkg, amount: amount);
          if (!mounted) return;
          await showCompanyCode(context, id: id, name: _name.text.trim(), phone: _phone.text.trim());
        }
      } else {
        final id = await cloud.createCompany(
          name: _name.text,
          ownerEmail: _email.text,
          ownerName: _owner.text,
          phone: _phone.text,
          city: _city.text,
          category: tpl.name,
          package: pkg,
          amount: amount,
        );
        if (!mounted) return;
        await showCompanyCode(context, id: id, name: _name.text.trim(), phone: _phone.text.trim());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, tr(authError(e)), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('New company'))),
      body: StreamBuilder<List<Package>>(
        stream: CloudService.instance.packages(),
        builder: (context, snap) {
          final packages = snap.data ?? const <Package>[];
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(Tw.s4), children: [
              _section(context, 'Company'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Company / shop name'), prefixIcon: const Icon(Icons.storefront_rounded)),
                validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the company name.') : null,
              ),
              const SizedBox(height: Tw.s3),
              DropdownButtonFormField<String>(
                value: _type,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Business type'), prefixIcon: const Icon(Icons.category_rounded)),
                items: [for (final t in businessTemplates) DropdownMenuItem(value: t.key, child: Text(tr(t.name)))],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: Tw.s3),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('City'), prefixIcon: const Icon(Icons.location_city_rounded)),
              ),
              _section(context, 'Owner'),
              TextFormField(
                controller: _owner,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Owner name'), prefixIcon: const Icon(Icons.person_rounded)),
              ),
              const SizedBox(height: Tw.s3),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('Owner email'),
                  helperText: tr('Signing in with Google on this email joins the company automatically.'),
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.mail_rounded),
                ),
                validator: validateEmail,
              ),
              const SizedBox(height: Tw.s3),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Create login for the owner')),
                subtitle: Text(tr(_login
                    ? 'The owner signs in with this email and password. No code needed.'
                    : 'The owner joins with a company code.')),
                value: _login,
                onChanged: (v) => setState(() => _login = v),
              ),
              if (_login) ...[
                TextFormField(
                  controller: _password,
                  obscureText: !_show,
                  decoration: InputDecoration(
                    labelText: tr('Owner password'),
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tr(_show ? 'Hide password' : 'Show password'),
                        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                      IconButton(
                        tooltip: tr('New password'),
                        icon: const Icon(Icons.casino_outlined),
                        onPressed: () => setState(() => _password.text = _newPassword()),
                      ),
                    ]),
                  ),
                  validator: (v) => _login ? validatePassword(v) : null,
                ),
                const SizedBox(height: Tw.s3),
              ],
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: tr('Owner phone / WhatsApp'), prefixIcon: const Icon(Icons.phone_rounded)),
              ),
              _section(context, 'Package'),
              DropdownButtonFormField<String>(
                value: _packageId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Package'), prefixIcon: const Icon(Icons.workspace_premium_rounded)),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('Free (no package)'))),
                  for (final p in packages.where((p) => p.active))
                    DropdownMenuItem(value: p.id, child: Text('${tr(p.name)}${p.price.isEmpty ? '' : ' · ${p.price}'}')),
                ],
                onChanged: (v) => setState(() {
                  _packageId = v ?? '';
                  final p = _find(packages, _packageId);
                  _amount.text = p == null ? '' : p.amount.toStringAsFixed(0);
                }),
              ),
              if (_packageId.isNotEmpty) ...[
                const SizedBox(height: Tw.s3),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Amount received'), prefixIcon: const Icon(Icons.payments_rounded)),
                ),
              ],
              if (packages.isEmpty && snap.connectionState != ConnectionState.waiting)
                Padding(
                  padding: const EdgeInsets.only(top: Tw.s2),
                  child: Text(tr('No packages yet. Create them in the Packages tab.'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              const SizedBox(height: Tw.s6),
              FilledButton.icon(
                onPressed: _busy ? null : () => _save(packages),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_business_rounded),
                label: Text(tr('Create company')),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, Tw.s5, 4, Tw.s3),
        child: Text(tr(text).toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      );
}

Package? _find(List<Package> list, String id) {
  for (final p in list) {
    if (p.id == id) return p;
  }
  return null;
}

/// Shows the company code with copy and share buttons.
Future<void> showCompanyCode(BuildContext context, {required String id, required String name, String phone = ''}) {
  final message = 'Assalam o Alaikum! Your BizPOS company "$name" is ready.\n'
      '1. Install BizPOS and create your account (or continue with Google).\n'
      '2. Open More > Account > Join a company.\n'
      '3. Enter this company code: $id';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.verified_rounded, color: Tw.emerald500, size: 40),
      title: Text(tr('Company code')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Give this code to the owner. They enter it in More > Account > Join a company.'), textAlign: TextAlign.center),
        const SizedBox(height: Tw.s4),
        Container(
          padding: const EdgeInsets.all(Tw.s3),
          decoration: BoxDecoration(
            color: Tw.indigo500.withOpacity(0.12),
            borderRadius: BorderRadius.circular(Tw.rXl),
            border: Border.all(color: Tw.indigo500.withOpacity(0.35)),
          ),
          child: SelectableText(id,
              textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(tr('Copy')),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: id));
            showSnack(ctx, tr('Copied'));
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.share_rounded, size: 18),
          label: Text(tr('Share')),
          onPressed: () => Share.share(message),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
      ],
    ),
  );
}

/// Shows the owner's new login with copy and share buttons.
Future<void> showOwnerLogin(BuildContext context,
    {required String id, required String name, required String email, required String password, String phone = ''}) {
  final message = 'Assalam o Alaikum! Your BizPOS company "$name" is ready.\n'
      '1. Install BizPOS.\n'
      '2. Tap "I already have an account" and sign in:\n'
      'Email: $email\n'
      'Password: $password\n'
      '3. Change your password in More > Account.';
  Widget row(BuildContext ctx, String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: Tw.s2),
        padding: const EdgeInsets.fromLTRB(Tw.s3, Tw.s2, Tw.s1, Tw.s2),
        decoration: BoxDecoration(
          color: Tw.indigo500.withOpacity(0.12),
          borderRadius: BorderRadius.circular(Tw.rXl),
          border: Border.all(color: Tw.indigo500.withOpacity(0.35)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(label), style: Theme.of(ctx).textTheme.labelSmall),
              SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showSnack(ctx, tr('Copied'));
            },
          ),
        ]),
      );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.verified_rounded, color: Tw.emerald500, size: 40),
      title: Text(tr('Company and login ready')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Send these to the owner. They sign in with them on their phone.'), textAlign: TextAlign.center),
        const SizedBox(height: Tw.s4),
        row(ctx, 'Email', email),
        row(ctx, 'Password', password),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.share_rounded, size: 18),
          label: Text(tr('Share')),
          onPressed: () => Share.share(message),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
      ],
    ),
  );
}
