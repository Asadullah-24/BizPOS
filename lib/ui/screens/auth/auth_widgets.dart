import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/i18n.dart';
import '../../brand.dart';
import '../../tokens.dart';

/// Dark theme used by every auth screen, independent of the app's theme mode.
ThemeData authTheme(BuildContext context) {
  final base = Theme.of(context);
  const radius = BorderRadius.all(Radius.circular(Tw.rXl));
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    brightness: Brightness.dark,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: Tw.indigo500,
      onPrimary: Colors.white,
      surface: Tw.slate950,
      onSurface: Tw.slate100,
      onSurfaceVariant: Tw.slate400,
      outline: Tw.slate600,
      outlineVariant: Tw.slate700,
      primaryContainer: const Color(0xFF2E2A6B),
      onPrimaryContainer: Tw.indigo100,
      surfaceContainerHighest: Tw.slate800,
      error: Tw.rose400,
    ),
    textTheme: base.textTheme.apply(bodyColor: Tw.slate100, displayColor: Colors.white, fontFamily: Tw.font),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tw.slate900.withOpacity(0.9),
      border: border(Tw.slate700),
      enabledBorder: border(Tw.slate700),
      focusedBorder: border(Tw.indigo400, 2),
      errorBorder: border(Tw.rose400),
      focusedErrorBorder: border(Tw.rose400, 2),
      labelStyle: const TextStyle(color: Tw.slate400),
      floatingLabelStyle: const TextStyle(color: Tw.indigo300),
      hintStyle: const TextStyle(color: Tw.slate500),
      prefixIconColor: Tw.slate400,
      suffixIconColor: Tw.slate400,
      errorStyle: const TextStyle(color: Tw.rose400),
      contentPadding: const EdgeInsets.symmetric(horizontal: Tw.s4, vertical: 16),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Tw.indigo400),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: Tw.slate100,
        side: const BorderSide(color: Tw.slate700),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: Tw.font, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Tw.indigo300,
        textStyle: const TextStyle(fontFamily: Tw.font, fontWeight: FontWeight.w600),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: Tw.slate500, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tw.indigo500 : Colors.transparent),
    ),
  );
}

/// Full-screen dark auth layout. Phones get a single column; tablets and
/// landscape get a brand panel on the left and the form on the right.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.showBack = false, this.trailing});
  final Widget child;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return Theme(
      data: authTheme(context),
      child: Scaffold(
        backgroundColor: Tw.slate950,
        resizeToAvoidBottomInset: true,
        body: AnimatedBackdrop(
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Tw.s2, Tw.s2, Tw.s4, 0),
                child: Row(children: [
                  if (showBack)
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Tw.slate300),
                      tooltip: tr('Back'),
                    )
                  else
                    const SizedBox(width: Tw.s2),
                  if (!wide) const BrandWordmark(size: 30),
                  const Spacer(),
                  if (trailing != null) trailing!,
                  const LanguageChip(),
                ]),
              ),
              Expanded(
                child: wide
                    ? Row(children: [
                        const Expanded(child: _BrandPanel()),
                        Expanded(child: Center(child: _scroll(child))),
                      ])
                    : Center(child: _scroll(child)),
              ),
              const VendorFooter(onDark: true),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Tw.s6, vertical: Tw.s4),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
      );
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Tw.s10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BrandWordmark(size: 44),
        const SizedBox(height: Tw.s8),
        Text(
          tr('Run your whole shop from one app.'),
          style: const TextStyle(fontFamily: Tw.font, fontSize: 40, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.2),
        ),
        const SizedBox(height: Tw.s4),
        Text(
          tr('Sales, stock, customers, expenses and reports. Works without internet and backs up when you are online.'),
          style: const TextStyle(fontFamily: Tw.font, fontSize: 17, height: 1.5, color: Tw.slate400),
        ),
        const SizedBox(height: Tw.s8),
        const FeatureList(),
      ]),
    );
  }
}

/// Gradient app mark + "BizPOS" wordmark.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 36, this.showName = true});
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BrandMark(size: size),
      if (showName) ...[
        SizedBox(width: size * 0.3),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Biz', style: TextStyle(color: Colors.white)),
            TextSpan(
              text: 'POS',
              style: TextStyle(foreground: Paint()..shader = const LinearGradient(colors: [Tw.indigo300, Tw.violet500]).createShader(Rect.fromLTWH(0, 0, size * 2, size))),
            ),
          ]),
          style: TextStyle(fontFamily: Tw.font, fontSize: size * 0.62, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
      ],
    ]);
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36, this.glow = false});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Tw.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow ? Tw.glow(Tw.indigo500, opacity: 0.55) : null,
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Icon(Icons.point_of_sale_rounded, color: Colors.white, size: size * 0.56),
    );
  }
}

/// EN / اردو toggle shown on the auth screens.
class LanguageChip extends StatelessWidget {
  const LanguageChip({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final urdu = app.language == 'ur';
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        final next = urdu ? 'en' : 'ur';
        app.previewLanguage(next);
        if (app.onboarded) app.setSetting('language', next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Tw.s3, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Tw.slate900.withOpacity(0.8),
          border: Border.all(color: Tw.slate700),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.translate_rounded, size: 15, color: Tw.slate300),
          const SizedBox(width: 6),
          Text(urdu ? 'English' : 'اردو', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tw.slate200)),
        ]),
      ),
    );
  }
}

/// Three selling points with tinted icons.
class FeatureList extends StatelessWidget {
  const FeatureList({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color c, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: Tw.s4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withOpacity(0.14),
                borderRadius: BorderRadius.circular(Tw.rXl),
                border: Border.all(color: c.withOpacity(0.25)),
              ),
              child: Icon(icon, color: c, size: 21),
            ),
            const SizedBox(width: Tw.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: const TextStyle(fontFamily: Tw.font, fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 2),
                Text(tr(sub), style: const TextStyle(fontFamily: Tw.font, fontSize: 13, height: 1.4, color: Tw.slate400)),
              ]),
            ),
          ]),
        );
    return Column(children: [
      row(Icons.wifi_off_rounded, Tw.emerald400, 'Works offline', 'Sell and print bills without internet.'),
      row(Icons.cloud_done_rounded, Tw.sky400, 'Safe backup', 'Your data follows you to a new phone.'),
      row(Icons.bolt_rounded, Tw.amber400, 'Free to start', 'Upgrade only when you need more.'),
    ]);
  }
}

/// Indigo -> violet gradient primary button with a loading state.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled || busy ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Tw.brandGradient,
          borderRadius: BorderRadius.circular(Tw.rXl),
          boxShadow: enabled ? Tw.glow(Tw.indigo500, opacity: 0.35) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tw.rXl),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(label, style: const TextStyle(fontFamily: Tw.font, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        if (icon != null) ...[const SizedBox(width: Tw.s2), Icon(icon, color: Colors.white, size: 20)],
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White "Continue with Google" button following Google's sign-in button style.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed, this.busy = false});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Tw.rXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tw.rXl),
        onTap: busy ? null : onPressed,
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Tw.slate700))
            else
              const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GoogleG())),
            const SizedBox(width: Tw.s3),
            Text(tr('Continue with Google'),
                style: const TextStyle(fontFamily: Tw.font, fontSize: 15, fontWeight: FontWeight.w600, color: Tw.slate800)),
          ]),
        ),
      ),
    );
  }
}

class _GoogleG extends CustomPainter {
  const _GoogleG();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.2;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    const deg = math.pi / 180;
    canvas.drawArc(rect, -40 * deg, -100 * deg, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -140 * deg, -90 * deg, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 130 * deg, -100 * deg, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 30 * deg, -70 * deg, false, p(const Color(0xFF4285F4)));
    final c = size.center(Offset.zero);
    canvas.drawRect(Rect.fromLTWH(c.dx, c.dy - w / 2, size.width / 2 - w / 4, w), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "──── or ────" divider.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: Tw.slate800));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tw.s5),
      child: Row(children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tw.s3),
          child: Text(tr('or'), style: const TextStyle(color: Tw.slate500, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        line,
      ]),
    );
  }
}

/// Rose-tinted error box (or emerald for success).
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, required this.text, this.success = false});
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final c = success ? Tw.emerald400 : Tw.rose400;
    return Container(
      padding: const EdgeInsets.all(Tw.s3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(Tw.rXl),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: c, size: 20),
        const SizedBox(width: Tw.s2),
        Expanded(child: Text(text, style: TextStyle(color: c, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w500))),
      ]),
    );
  }
}

/// 0 = empty, 1 weak, 2 fair, 3 good, 4 strong.
int passwordScore(String s) {
  if (s.isEmpty) return 0;
  var score = 0;
  if (s.length >= 8) score++;
  if (s.length >= 12) score++;
  if (RegExp(r'[a-z]').hasMatch(s) && RegExp(r'[A-Z]').hasMatch(s)) score++;
  if (RegExp(r'[0-9]').hasMatch(s)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(s)) score++;
  return score.clamp(1, 4);
}

/// Four-segment strength meter under the new password field.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final score = passwordScore(password);
    const colors = [Tw.slate700, Tw.rose500, Tw.amber500, Tw.sky400, Tw.emerald400];
    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    return Padding(
      padding: const EdgeInsets.only(top: Tw.s2),
      child: Row(children: [
        for (var i = 1; i <= 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i <= score ? colors[score] : Tw.slate800,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: 6),
        ],
        const SizedBox(width: Tw.s3),
        SizedBox(
          width: 52,
          child: Text(
            score == 0 ? '' : tr(labels[score]),
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors[score]),
          ),
        ),
      ]),
    );
  }
}
