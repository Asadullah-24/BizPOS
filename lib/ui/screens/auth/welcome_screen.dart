import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_state.dart';
import '../../../core/db.dart';
import '../../../core/i18n.dart';
import '../../../services/cloud_service.dart';
import '../../brand.dart';
import '../../tokens.dart';
import 'auth_widgets.dart';
import '../../../services/profile_service.dart';
import 'sign_in_screen.dart';

/// First screen for a new install: create an account, sign in, or use offline.
/// With [linkOnly] it is opened from inside the app to connect an account.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.linkOnly = false});
  final bool linkOnly;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  void _done() {
    if (widget.linkOnly) {
      CloudService.instance.ensureShopLinked();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudService.instance.signInWithGoogle();
      if (mounted) _done();
    } catch (e) {
      if (mounted) setState(() => _error = tr(authError(e)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(bool signUp) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SignInScreen(signUp: signUp)));
    if (ok == true && mounted) _done();
  }

  /// Stores kept on this phone (shown after signing out).
  List<StoreProfile> get _stores {
    final p = ProfileService.instance;
    return [
      if (p.signedOut && (p.active.uid != null || p.active.name.isNotEmpty)) p.active,
      ...p.others,
    ];
  }

  Future<void> _openStore(StoreProfile st) async {
    final profiles = ProfileService.instance;
    if (st.uid == null) {
      // Offline store: open it; its PIN protects it.
      await profiles.switchTo(st.id);
      await profiles.setSignedOut(false);
      CloudService.instance.refresh();
      return;
    }
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => SignInScreen(initialEmail: st.email)));
    if (ok == true && mounted) _done();
  }

  Future<void> _offline() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: authTheme(ctx),
        child: AlertDialog(
          backgroundColor: Tw.slate900,
          icon: const Icon(Icons.wifi_off_rounded, color: Tw.amber400),
          title: Text(tr('Use without an account?')),
          content: Text(
            tr('Everything works on this phone, but there is no cloud backup and no way to recover your data if the phone is lost. You can create an account later.'),
            style: const TextStyle(color: Tw.slate300, height: 1.45),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Continue offline'))),
          ],
        ),
      ),
    );
    if (go != true) return;
    final profiles = ProfileService.instance;
    if (profiles.signedOut || profiles.active.uid != null) {
      // The open store belongs to an account: start a separate offline store.
      await profiles.switchTo(await profiles.create());
    }
    await Local.prefs.setBool(Local.k('offline_mode'), true);
    await profiles.setSignedOut(false);
    CloudService.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return AuthScaffold(
      showBack: widget.linkOnly,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!wide) ...[
          const SizedBox(height: Tw.s4),
          FadeSlideIn(
            child: Text(
              tr('Run your whole shop from one app.'),
              style: const TextStyle(fontFamily: Tw.font, fontSize: 32, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1),
            ),
          ),
          const SizedBox(height: Tw.s3),
          FadeSlideIn(
            delay: 80,
            child: Text(
              tr('Sales, stock, customers, expenses and reports. Works without internet and backs up when you are online.'),
              style: const TextStyle(fontFamily: Tw.font, fontSize: 15.5, height: 1.5, color: Tw.slate400),
            ),
          ),
          const SizedBox(height: Tw.s6),
          const FadeSlideIn(delay: 160, child: FeatureList()),
          const SizedBox(height: Tw.s2),
        ] else ...[
          Text(tr('Get started'),
              style: const TextStyle(fontFamily: Tw.font, fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.6)),
          const SizedBox(height: Tw.s2),
          Text(tr('Create a free account or sign in to continue.'), style: const TextStyle(color: Tw.slate400, fontSize: 15)),
          const SizedBox(height: Tw.s6),
        ],
        if (CloudService.instance.revokedNotice) ...[
          AuthBanner(text: tr('This phone was removed from your account, so its BizPOS data was erased. Sign in to start again.')),
          const SizedBox(height: Tw.s4),
        ],
        if (_error != null) ...[
          AuthBanner(text: _error!),
          const SizedBox(height: Tw.s4),
        ],
        FadeSlideIn(
          delay: 240,
          child: GradientButton(
            label: tr('Create free account'),
            icon: Icons.arrow_forward_rounded,
            onPressed: _busy ? null : () => _open(true),
          ),
        ),
        const SizedBox(height: Tw.s3),
        FadeSlideIn(
          delay: 300,
          child: OutlinedButton(
            onPressed: _busy ? null : () => _open(false),
            child: Text(tr('I already have an account')),
          ),
        ),
        const FadeSlideIn(delay: 340, child: OrDivider()),
        FadeSlideIn(delay: 380, child: GoogleButton(onPressed: _google, busy: _busy)),
        if (!widget.linkOnly) ...[
          const SizedBox(height: Tw.s4),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Tw.slate400),
              onPressed: _busy ? null : _offline,
              icon: const Icon(Icons.wifi_off_rounded, size: 18),
              label: Text(tr('Use without an account (offline)')),
            ),
          ),
        ],
        if (_stores.isNotEmpty) ...[
          const SizedBox(height: Tw.s4),
          Text(tr('Stores on this phone'),
              style: const TextStyle(color: Tw.slate300, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: Tw.s2),
          for (final st in _stores)
            Padding(
              padding: const EdgeInsets.only(bottom: Tw.s2),
              child: Material(
                color: Tw.slate900.withOpacity(0.85),
                borderRadius: BorderRadius.circular(Tw.rXl),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Tw.rXl),
                  onTap: _busy ? null : () => _openStore(st),
                  child: Container(
                    padding: const EdgeInsets.all(Tw.s3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Tw.rXl),
                      border: Border.all(color: Tw.slate700),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(Tw.rXl)),
                        child: Text((st.name.isEmpty ? '?' : st.name.characters.first).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: Tw.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(st.name.isEmpty ? tr('Store') : st.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          Text(st.email ?? tr('Offline store'), style: const TextStyle(color: Tw.slate400, fontSize: 12.5), overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Tw.slate400),
                    ]),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: Tw.s2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_rounded, size: 13, color: Tw.slate500),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tr('Only you and your staff can see your shop data.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tw.slate500, fontSize: 12),
            ),
          ),
        ]),
      ]),
    );
  }
}
