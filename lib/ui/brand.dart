import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/license.dart';
import '../core/packages.dart';
import '../services/alert_service.dart';
import 'screens/plan_screen.dart';

/// Gradient backdrop used by the login, activation and super admin screens.
class BrandBackground extends StatelessWidget {
  const BrandBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!, cs.tertiary],
        ),
      ),
      child: Stack(children: [
        // Soft floating circles give the backdrop depth.
        Positioned(top: -80, right: -60, child: _Blob(size: 240, color: Colors.white.withOpacity(0.10))),
        Positioned(bottom: -100, left: -70, child: _Blob(size: 300, color: Colors.white.withOpacity(0.08))),
        Positioned(top: 160, left: -40, child: _Blob(size: 120, color: Colors.white.withOpacity(0.06))),
        child,
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
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

/// Returns true when [feature] is unlocked; otherwise shows the upgrade sheet.
bool requireFeature(BuildContext context, String feature) {
  if (LicenseService.instance.has(feature)) return true;
  showModalBottomSheet(
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
          const SizedBox(height: 4),
          Text('${tr('Included in')} ${Plans.pro.name}: ${Plans.pro.price}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.upgrade),
            label: Text(tr('See plans and upgrade')),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen()));
            },
          ),
        ]),
      ),
    ),
  );
  return false;
}
