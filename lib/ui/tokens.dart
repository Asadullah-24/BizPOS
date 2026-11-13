import 'package:flutter/material.dart';

/// Design tokens for BizPOS, taken from the Tailwind CSS palette and scales
/// so colours, spacing and radii stay consistent across every screen.
class Tw {
  Tw._();

  // Slate (neutrals)
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate850 = Color(0xFF172033);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // Brand: indigo -> violet
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo900 = Color(0xFF312E81);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const fuchsia500 = Color(0xFFD946EF);
  static const sky400 = Color(0xFF38BDF8);
  static const cyan400 = Color(0xFF22D3EE);

  // Status
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);

  // Spacing (Tailwind 4px scale)
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;

  // Radius
  static const rLg = 8.0;
  static const rXl = 12.0;
  static const r2xl = 16.0;
  static const r3xl = 24.0;

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo500, violet600],
  );

  static List<BoxShadow> glow(Color c, {double opacity = 0.45}) => [
        BoxShadow(color: c.withOpacity(opacity), blurRadius: 24, offset: const Offset(0, 10)),
      ];

  static const font = 'Inter';
}
