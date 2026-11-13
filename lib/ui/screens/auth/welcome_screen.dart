import 'package:flutter/material.dart';

import '../../../core/db.dart';
import '../../../core/i18n.dart';
import '../../../services/cloud_service.dart';
import '../../brand.dart';
import '../../common.dart';
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

  void _done() {
    if (widget.linkOnly) {
      CloudService.instance.ensureShopLinked();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await CloudService.instance.signInWithGoogle();
      if (mounted) _done();
    } catch (e) {
      if (mounted) showSnack(context, tr(authError(e)), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(bool signUp) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => SignInScreen(signUp: signUp)));
    if (ok == true && mounted) _done();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final white = Colors.white.withOpacity(0.92);
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: widget.linkOnly ? AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white) : null,
        body: AnimatedBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FadeSlideIn(
                      child: Center(
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                            boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 12))],
                          ),
                          child: const Icon(Icons.point_of_sale_rounded, size: 50, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeSlideIn(
                      delay: 120,
                      child: Text('BizPOS',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      delay: 220,
                      child: Text(
                        tr('Sell, track stock and grow your shop. Works with or without internet.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: white, fontSize: 16, height: 1.4),
                      ),
                    ),
                    if (CloudService.instance.revokedNotice)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          tr('This phone was removed from your account, so its BizPOS data was erased. Sign in to start again.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF8A80)),
                        ),
                      ),
                    const SizedBox(height: 36),
                    FadeSlideIn(
                      delay: 320,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _open(true),
                        child: Text(tr('Create free account')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: 400,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(0.4))),
                        onPressed: _busy ? null : () => _open(false),
                        child: Text(tr('Sign in')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeSlideIn(
                      delay: 480,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(0.4))),
                        onPressed: _busy ? null : _google,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.g_mobiledata, size: 30),
                        label: Text(tr('Continue with Google')),
                      ),
                    ),
                    if (!widget.linkOnly) ...[
                      const SizedBox(height: 20),
                      FadeSlideIn(
                        delay: 560,
                        child: TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.white70),
                          onPressed: () async {
                            await Local.prefs.setBool('offline_mode', true);
                            CloudService.instance.refresh();
                          },
                          child: Text(tr('Use without an account (offline)')),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const VendorFooter(onDark: true),
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
