import 'package:intl/intl.dart';

/// Formatting helpers driven by business settings (currency, decimals).
class Fmt {
  static String symbol = 'Rs';
  static int decimals = 0;
  static bool symbolAfter = false;

  static NumberFormat _num() => NumberFormat.decimalPatternDigits(decimalDigits: decimals);

  static String money(double v) {
    final s = _num().format(v.abs());
    final sign = v < 0 ? '-' : '';
    return symbolAfter ? '$sign$s $symbol' : '$sign$symbol $s';
  }

  /// Plain number with business decimals, no currency symbol.
  static String amount(double v) => _num().format(v);

  static String qty(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static String date(int ms) => DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(ms));

  static String dateTime(int ms) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

  static String time(int ms) => DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));

  static String percent(double v) => '${qty(v)}%';

  static double round(double v) {
    final f = _pow10(decimals);
    return (v * f).roundToDouble() / f;
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  /// Parses user input like "1,250.50"; returns 0 on bad input.
  static double parse(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0;
}
