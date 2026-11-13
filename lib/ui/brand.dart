import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/access.dart';
import '../core/i18n.dart';
import '../core/license.dart';
import '../core/packages.dart';
import '../services/alert_service.dart';
import 'screens/plan_screen.dart';

/// Dark animated backdrop with slowly drifting glow orbs (welcome / sign-in).
class AnimatedBackdrop extends StatefulWidget {
  const AnimatedBackdrop({super.key, required this.child});
  final Widget child;

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B14), Color(0xFF0B1324), Color(0xFF0A1A22)],
        ),
      ),
      child: Stack(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            final size = MediaQuery.sizeOf(context);
            Widget orb(double x, double y, double r, Color c) => Positioned(
                  left: x - r,
                  top: y - r,
                  child: Container(
                    width: r * 2,
                    height: r * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [c.withOpacity(0.55), c.withOpacity(0)]),
                    ),
                  ),
                );
            return Stack(children: [
              orb(size.width * (0.2 + 0.1 * math.sin(t)), size.height * (0.18 + 0.05 * math.cos(t)), 180, cs.primary),
              orb(size.width * (0.85 + 0.08 * math.cos(t * 1.3)), size.height * (0.45 + 0.06 * math.sin(t)), 200, cs.tertiary),
              orb(size.width * (0.35 + 0.12 * math.cos(t * 0.7)), size.height * (0.88 + 0.04 * math.sin(t * 1.1)), 220, const Color(0xFF6366F1)),
            ]);
          },
        ),
        widget.child,
      ]),
    );
  }
}

/// Fades and slides its child in after [delay] (staggered entrances).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 500 + delay),
        curve: Interval(delay / (500 + delay), 1, curve: Curves.easeOutCubic),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
        ),
        child: child,
      );
}

/// Gradient backdrop used by the login, activation and super admin screens.
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBackdrop(child: child);
}

/// Raised card with a deep shadow (the "3D" panel on the login screen).
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 18)),
          BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

/// Keypad key with a bevel and drop shadow that "presses" when tapped.
class Key3D extends StatefulWidget {
  const Key3D({super.key, required this.onTap, this.label, this.icon, this.accent = false});
  final VoidCallback? onTap;
  final String? label;
  final IconData? icon;
  final bool accent;

  @override
  State<Key3D> createState() => _Key3DState();
}

class _Key3DState extends State<Key3D> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = widget.accent ? cs.primary : cs.surfaceContainerHighest;
    final fg = widget.accent ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        margin: EdgeInsets.only(top: _down ? 4 : 0, bottom: _down ? 0 : 4),
        width: 74,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(base, Colors.white, 0.25)!, base],
          ),
          boxShadow: _down
              ? [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 2, offset: const Offset(0, 1))]
              : [
                  BoxShadow(color: Color.lerp(base, Colors.black, 0.35)!, offset: const Offset(0, 4)),
                  BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 10, offset: const Offset(0, 8)),
                ],
        ),
        child: widget.icon != null
            ? Icon(widget.icon, color: fg, size: 26)
            : Text(widget.label ?? '', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

/// "Powered by BizPOS · 0322-4699887" line shown at the bottom of the app.
class VendorFooter extends StatelessWidget {
  const VendorFooter({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final color = onDark ? Colors.white.withOpacity(0.85) : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => showVendorContact(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.support_agent, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${lic.footer} · ${tr('Support')} ${Vendor.pretty(lic.phone)}',
              style: TextStyle(fontSize: 11.5, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> showVendorContact(BuildContext context, {String? message}) async {
  final lic = LicenseService.instance;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: Text(lic.footer),
          subtitle: Text('${tr('Device')} ${lic.deviceCodePretty}'),
        ),
        ListTile(
          leading: const Icon(Icons.chat, color: Colors.green),
          title: Text('${tr('WhatsApp')} ${Vendor.pretty(lic.phone)}'),
          onTap: () {
            Navigator.pop(ctx);
            VendorContact.whatsapp(message ?? 'Assalam o Alaikum, I need help with BizPOS. Device code: ${lic.deviceCodePretty}');
          },
        ),
        ListTile(
          leading: const Icon(Icons.call),
          title: Text('${tr('Call')} ${Vendor.pretty(lic.phone)}'),
          onTap: () {
            Navigator.pop(ctx);
            VendorContact.call();
          },
        ),
      ]),
    ),
  );
}

/// Runs [open] when [feature] is available; otherwise shows what it needs and
/// links to the plans screen.
Future<void> openFeature(BuildContext context, String feature, VoidCallback open) async {
  if (Access.instance.has(feature)) {
    open();
    return;
  }
  final go = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.workspace_premium, size: 48, color: Colors.amber),
          const SizedBox(height: 8),
          Text(tr('Paid feature'), textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(tr(Feature.labels[feature] ?? feature), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.upgrade),
            label: Text(tr('See plans')),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    ),
  );
  if (go == true && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen()));
  }
}

/// Synchronous check for places that only need yes/no; shows the unlock sheet when locked.
bool requireFeature(BuildContext context, String feature) {
  if (Access.instance.has(feature)) return true;
  openFeature(context, feature, () {});
  return false;
}
