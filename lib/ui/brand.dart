import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/access.dart';
import '../core/i18n.dart';
import '../core/license.dart';
import '../core/packages.dart';
import '../services/alert_service.dart';
import 'screens/plan_screen.dart';
import 'screens/auth/auth_widgets.dart';
import 'tokens.dart';

/// Dark animated backdrop: slate-950 base, a faint dot grid and slowly
/// drifting indigo / violet / sky glows (welcome, sign-in, lock screens).
class AnimatedBackdrop extends StatefulWidget {
  const AnimatedBackdrop({super.key, required this.child});
  final Widget child;

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Tw.slate950,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value * 2 * math.pi;
                final size = MediaQuery.sizeOf(context);
                Widget orb(double x, double y, double r, Color c, double o) => Positioned(
                      left: x - r,
                      top: y - r,
                      child: Container(
                        width: r * 2,
                        height: r * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [c.withOpacity(o), c.withOpacity(0)]),
                        ),
                      ),
                    );
                return Stack(children: [
                  orb(size.width * (0.15 + 0.08 * math.sin(t)), size.height * (0.10 + 0.04 * math.cos(t)), 260, Tw.indigo500, 0.38),
                  orb(size.width * (0.95 + 0.06 * math.cos(t * 1.3)), size.height * (0.38 + 0.05 * math.sin(t)), 240, Tw.violet600, 0.30),
                  orb(size.width * (0.30 + 0.10 * math.cos(t * 0.7)), size.height * (0.98 + 0.03 * math.sin(t * 1.1)), 280, Tw.sky400, 0.14),
                ]);
              },
            ),
          ),
        ),
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DotGrid()))),
        widget.child,
      ]),
    );
  }
}

class _DotGrid extends CustomPainter {
  const _DotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.045);
    const gap = 22.0;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

/// Frosted slate card used on the dark auth and lock screens.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(Tw.s6)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Tw.slate900.withOpacity(0.82),
        borderRadius: BorderRadius.circular(Tw.r3xl),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 40, offset: const Offset(0, 20)),
        ],
      ),
      child: Theme(data: authTheme(context), child: child),
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
    final accent = widget.accent;
    final fg = accent ? Colors.white : Tw.slate100;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 76,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tw.r2xl),
            gradient: accent ? Tw.brandGradient : null,
            color: accent ? null : (_down ? Tw.slate700 : Tw.slate800.withOpacity(0.9)),
            border: accent ? null : Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: accent && !_down ? Tw.glow(Tw.indigo500, opacity: 0.4) : null,
          ),
          child: widget.icon != null
              ? Icon(widget.icon, color: fg, size: 24)
              : Text(widget.label ?? '', style: TextStyle(fontFamily: Tw.font, fontSize: 24, fontWeight: FontWeight.w600, color: fg)),
        ),
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
    final color = onDark ? Tw.slate400 : Theme.of(context).colorScheme.onSurfaceVariant;
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


/// Shown when the shop reaches its plan's product limit.
Future<void> showProductLimit(BuildContext context, int limit) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Tw.amber500.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.inventory_2_rounded, color: Tw.amber500, size: 30),
          ),
          Text('${tr('Product limit reached')}: $limit', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(tr('Upgrade your plan to add more products. Your existing products keep working.'), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.workspace_premium_rounded),
            label: Text(tr('See plans')),
            onPressed: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_rounded, color: Tw.emerald500),
            label: Text(tr('Ask support on WhatsApp')),
            onPressed: () {
              Navigator.pop(ctx);
              VendorContact.whatsapp('Assalam o Alaikum, I need more than $limit products in BizPOS. Device code: ${LicenseService.instance.deviceCodePretty}');
            },
          ),
        ]),
      ),
    ),
  );
  if (go == true && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen()));
  }
}

/// "37 / 100 products" bar shown on the Products screen when there is a limit.
class ProductUsageBar extends StatelessWidget {
  const ProductUsageBar({super.key, required this.count, required this.limit});
  final int count;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (limit <= 0) return const SizedBox.shrink();
    final ratio = (count / limit).clamp(0.0, 1.0);
    final color = ratio >= 1 ? Tw.rose500 : (ratio >= 0.8 ? Tw.amber500 : Tw.indigo500);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: ratio, minHeight: 6, color: color, backgroundColor: cs.surfaceContainerHighest),
            ),
          ),
          const SizedBox(width: 10),
          Text('$count / $limit ${tr('products')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          if (ratio >= 0.8) ...[
            const SizedBox(width: 6),
            Text(tr('Upgrade'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tw.indigo400)),
          ],
        ]),
      ),
    );
  }
}
