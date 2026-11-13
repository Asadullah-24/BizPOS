import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n.dart';
import '../../../services/cloud_service.dart';
import '../../brand.dart';
import '../../tokens.dart';
import '../auth/auth_widgets.dart';
import '../auth/sign_in_screen.dart';
import '../super_admin/super_admin_login.dart';
import 'admin_panel.dart';

/// Single entrance for the super admin, from the lock screen, Settings and More.
/// A signed-in super admin goes straight to the online panel; anyone else sees
/// what is needed, their user ID, and the offline codes console.
class SuperAdminHub extends StatefulWidget {
  const SuperAdminHub({super.key});

  @override
  State<SuperAdminHub> createState() => _SuperAdminHubState();
}

class _SuperAdminHubState extends State<SuperAdminHub> {
  bool _checking = false;
  String? _note;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _note = null;
    });
    final ok = await CloudService.instance.reloadAdmin();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _note = ok ? null : tr('Still not a super admin. Check the document in Firebase and try again.');
    });
  }

  Future<void> _signIn() async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
    if (mounted) await _check();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    if (cloud.isAdmin) return const AdminGate();
    final uid = cloud.user?.uid;
    return AuthScaffold(
      showBack: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(Tw.r2xl)),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: Tw.s4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Super admin'),
                  style: const TextStyle(fontFamily: Tw.font, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(tr('Control every shop from any phone.'), style: const TextStyle(color: Tw.slate400)),
            ]),
          ),
        ]),
        const SizedBox(height: Tw.s6),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Header(icon: Icons.cloud_rounded, color: Tw.sky400, title: tr('Online control panel')),
            const SizedBox(height: Tw.s3),
            Wrap(spacing: Tw.s2, runSpacing: Tw.s2, children: [
              for (final f in ['Dashboard', 'Shops', 'Packages', 'Subscriptions', 'Requests', 'Branding', 'Password', '2FA'])
                _Chip(tr(f)),
            ]),
            const SizedBox(height: Tw.s4),
            if (!cloud.signedIn) ...[
              Text(tr('Sign in with the account you made super admin.'), style: const TextStyle(color: Tw.slate300)),
              const SizedBox(height: Tw.s4),
              GradientButton(label: tr('Sign in'), onPressed: _signIn),
            ] else ...[
              AuthBanner(text: '${cloud.user?.email ?? ''}: ${tr('this account is not a super admin yet.')}'),
              const SizedBox(height: Tw.s4),
              Text(tr('One-time setup in Firebase console → Firestore → collection "admins" → document ID = your user ID → field role = super.'),
                  style: const TextStyle(color: Tw.slate300, height: 1.45)),
              const SizedBox(height: Tw.s3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Tw.s3, vertical: Tw.s2),
                decoration: BoxDecoration(
                  color: Tw.slate950,
                  borderRadius: BorderRadius.circular(Tw.rXl),
                  border: Border.all(color: Tw.slate700),
                ),
                child: Row(children: [
                  Expanded(
                    child: SelectableText(uid ?? '',
                        style: const TextStyle(fontFamily: 'monospace', color: Tw.indigo300, fontSize: 13)),
                  ),
                  IconButton(
                    tooltip: tr('Copy'),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uid ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('User ID copied'))));
                    },
                  ),
                ]),
              ),
              if (_note != null) ...[const SizedBox(height: Tw.s3), AuthBanner(text: _note!)],
              const SizedBox(height: Tw.s4),
              GradientButton(label: tr('I have done it, check again'), busy: _checking, onPressed: _check),
            ],
          ]),
        ),
        const SizedBox(height: Tw.s4),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Header(icon: Icons.qr_code_2_rounded, color: Tw.amber400, title: tr('Offline unlock codes')),
            const SizedBox(height: Tw.s2),
            Text(tr('For shops without internet. Uses the master password and the authenticator code.'),
                style: const TextStyle(color: Tw.slate400, height: 1.45)),
            const SizedBox(height: Tw.s4),
            OutlinedButton.icon(
              icon: const Icon(Icons.key_rounded),
              label: Text(tr('Open offline codes')),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperAdminLogin())),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.color, required this.title});
  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(Tw.rXl)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: Tw.s3),
        Text(title, style: const TextStyle(fontFamily: Tw.font, fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
      ]);
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Tw.indigo500.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Tw.indigo500.withOpacity(0.3)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tw.indigo300)),
      );
}
