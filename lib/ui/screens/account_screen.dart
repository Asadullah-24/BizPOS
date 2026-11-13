import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/access.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../services/cloud_service.dart';
import '../common.dart';
import 'auth/sign_in_screen.dart';
import 'auth/welcome_screen.dart';
import 'plan_screen.dart';

/// Account, plan, devices (remove a lost phone) and password.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Change password')),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: current, obscureText: true, decoration: InputDecoration(labelText: tr('Current password'))),
            const SizedBox(height: 12),
            TextFormField(controller: next, obscureText: true, decoration: InputDecoration(labelText: tr('New password')), validator: validatePassword),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await CloudService.instance.changePassword(current.text, next.text);
      if (context.mounted) showSnack(context, tr('Password changed'));
    } catch (e) {
      if (context.mounted) showSnack(context, tr(authError(e)), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    final access = context.watch<Access>();
    final u = cloud.user;
    if (u == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Account'))),
        body: EmptyState(
          icon: Icons.account_circle_outlined,
          text: 'Sign in so your plan and shop stay safe if you lose this phone.',
          action: FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelcomeScreen(linkOnly: true))),
            child: Text(tr('Sign in or create account')),
          ),
        ),
      );
    }
    final me = LicenseService.instance.deviceCode;
    final devices = cloud.devices.entries.toList()..sort((a, b) => a.key == me ? -1 : (b.key == me ? 1 : a.key.compareTo(b.key)));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Account'))),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(child: Text((u.displayName ?? u.email ?? '?').characters.first.toUpperCase())),
          title: Text(u.displayName ?? ''),
          subtitle: Text(u.email ?? ''),
        ),
        if (cloud.usesPassword && !u.emailVerified)
          ListTile(
            leading: const Icon(Icons.mark_email_unread_outlined, color: Colors.orange),
            title: Text(tr('Email not verified')),
            trailing: TextButton(
              onPressed: () => guard(context, () => cloud.sendVerification(), success: 'Verification email sent'),
              child: Text(tr('Resend')),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr(access.planName)),
          subtitle: Text(access.isPaid
              ? (access.expiresAt == 0 ? tr('Lifetime') : '${tr('Valid until')} ${Fmt.date(access.expiresAt)}')
              : tr('Free')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: Text(tr('User ID')),
          subtitle: Text(u.uid, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: u.uid));
              if (context.mounted) showSnack(context, tr('Copied'));
            },
          ),
        ),
        const SectionTitle('My devices'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(tr('Lost or stolen phone? Remove it here. When it next goes online, BizPOS erases its data and signs it out.'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
        if (devices.isEmpty) const ListTile(title: Text('—')),
        for (final d in devices)
          ListTile(
            leading: Icon(d.value['revoked'] == true ? Icons.phonelink_erase : Icons.phone_android,
                color: d.value['revoked'] == true ? Colors.red : null),
            title: Text('${d.key.substring(0, 4)}-${d.key.substring(4)}${d.key == me ? '  (${tr('this phone')})' : ''}'),
            subtitle: Text([
              '${d.value['name'] ?? ''}',
              if (d.value['lastSeen'] is Timestamp) '${tr('Last seen')} ${Fmt.dateTime((d.value['lastSeen'] as Timestamp).millisecondsSinceEpoch)}',
              if (d.value['revoked'] == true) tr('Removed'),
            ].join(' · ')),
            trailing: d.key == me
                ? null
                : TextButton(
                    onPressed: () async {
                      final revoke = d.value['revoked'] != true;
                      if (revoke &&
                          !await confirm(context, 'Remove this phone',
                              'Its BizPOS data will be erased and it will be signed out the next time it connects.', danger: true)) {
                        return;
                      }
                      if (context.mounted) await guard(context, () => cloud.setDeviceRevoked(d.key, revoke));
                    },
                    child: Text(tr(d.value['revoked'] == true ? 'Restore' : 'Remove')),
                  ),
          ),
        const SectionTitle('Security'),
        if (cloud.usesPassword)
          ListTile(leading: const Icon(Icons.password), title: Text(tr('Change password')), onTap: () => _changePassword(context)),
        if (cloud.usesPassword)
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: Text(tr('Send password reset email')),
            onTap: () => guard(context, () => cloud.resetPassword(u.email ?? ''), success: 'Password reset link sent'),
          ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(tr('Sign out')),
          subtitle: Text(tr('Your shop data stays on this phone.')),
          onTap: () async {
            if (await confirm(context, 'Sign out', 'Sign out of your BizPOS account on this phone?')) await cloud.signOut();
          },
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
