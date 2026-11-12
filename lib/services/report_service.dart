import 'package:intl/intl.dart';

import '../core/db.dart';

enum PeriodKind { day, week, month, year, custom }

class Period {
  Period(this.kind, this.from, this.to);

  final PeriodKind kind;

  /// Inclusive start.
  final DateTime from;

  /// Exclusive end.
  final DateTime to;

  int get fromMs => from.millisecondsSinceEpoch;
  int get toMs => to.millisecondsSinceEpoch;

  static Period of(PeriodKind kind, [DateTime? anchor]) {
    final a = anchor ?? DateTime.now();
    switch (kind) {
      case PeriodKind.day:
        final f = DateTime(a.year, a.month, a.day);
        return Period(kind, f, DateTime(f.year, f.month, f.day + 1));
      case PeriodKind.week:
        final d = DateTime(a.year, a.month, a.day);
        final f = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        return Period(kind, f, DateTime(f.year, f.month, f.day + 7));
      case PeriodKind.month:
        return Period(kind, DateTime(a.year, a.month), DateTime(a.year, a.month + 1));
      case PeriodKind.year:
        return Period(kind, DateTime(a.year), DateTime(a.year + 1));
      case PeriodKind.custom:
        final f = DateTime(a.year, a.month, a.day);
        return Period(kind, f, DateTime(f.year, f.month, f.day + 1));
    }
  }

  static Period custom(DateTime from, DateTime toInclusive) => Period(
        PeriodKind.custom,
        DateTime(from.year, from.month, from.day),
        DateTime(toInclusive.year, toInclusive.month, toInclusive.day + 1),
      );

  Period shift(int n) {
    switch (kind) {
      case PeriodKind.day:
        return Period.of(kind, DateTime(from.year, from.month, from.day + n));
      case PeriodKind.week:
        return Period.of(kind, DateTime(from.year, from.month, from.day + 7 * n));
      case PeriodKind.month:
        return Period.of(kind, DateTime(from.year, from.month + n));
      case PeriodKind.year:
        return Period.of(kind, DateTime(from.year + n));
      case PeriodKind.custom:
        final days = (to.difference(from).inHours / 24).round();
        return Period(kind, DateTime(from.year, from.month, from.day + days * n),
            DateTime(to.year, to.month, to.day + days * n));
    }
  }

  String get label {
    switch (kind) {
      case PeriodKind.day:
        return DateFormat('EEE, dd MMM yyyy').format(from);
      case PeriodKind.week:
        final last = to.subtract(const Duration(days: 1));
        return '${DateFormat('dd MMM').format(from)} - ${DateFormat('dd MMM yyyy').format(last)}';
      case PeriodKind.month:
        return DateFormat('MMMM yyyy').format(from);
      case PeriodKind.year:
        return DateFormat('yyyy').format(from);
      case PeriodKind.custom:
        final last = to.subtract(const Duration(days: 1));
        return '${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(last)}';
    }
  }
}

class SeriesPoint {
  SeriesPoint(this.label, this.sales, this.profit);
  final String label;
  double sales;
  double profit;
}

class ReportData {
  int salesCount = 0;
  int cancelledCount = 0;
  double sales = 0;
  double tax = 0;
  double discount = 0;
  double cost = 0;
  double returns = 0;
  double returnsCost = 0;
  double expenses = 0;
  double purchases = 0;
  double moneyIn = 0;
  double moneyOut = 0;
  List<SeriesPoint> series = [];
  List<DbRow> topProducts = [];
  List<DbRow> byCategory = [];
  List<DbRow> byAccount = [];
  List<DbRow> expensesByCategory = [];

  double get netSales => sales - returns;
  double get cogs => cost - returnsCost;

  /// Revenue without tax, minus cost of goods sold.
  double get grossProfit => netSales - tax - cogs;
  double get netProfit => grossProfit - expenses;
  double get avgSale => salesCount == 0 ? 0 : sales / salesCount;
}

class ReportService {
  static Future<ReportData> build(Period p, {bool details = true}) async {
    final s = Db.instance.s;
    final a = [p.fromMs, p.toMs];
    final d = ReportData();

    final sale = await s.one(
      "SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(tax),0) AS tax, "
      "COALESCE(SUM(discount),0) AS disc, COALESCE(SUM(cost_total),0) AS cost FROM sales "
      "WHERE status = 'completed' AND deleted_at IS NULL AND created_at >= ? AND created_at < ?",
      a,
    );
    d.salesCount = asInt(sale?['n']);
    d.sales = asDouble(sale?['total']);
    d.tax = asDouble(sale?['tax']);
    d.discount = asDouble(sale?['disc']);
    d.cost = asDouble(sale?['cost']);
    d.cancelledCount = (await s.scalar(
            "SELECT COUNT(*) FROM sales WHERE status = 'cancelled' AND deleted_at IS NULL AND created_at >= ? AND created_at < ?",
            a))
        .toInt();

    final ret = await s.one(
      'SELECT COALESCE(SUM(total),0) AS total, COALESCE(SUM(cost_total),0) AS cost FROM returns '
      'WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?',
      a,
    );
    d.returns = asDouble(ret?['total']);
    d.returnsCost = asDouble(ret?['cost']);
    d.expenses = await s.scalar(
        'SELECT COALESCE(SUM(amount),0) FROM expenses WHERE deleted_at IS NULL AND date >= ? AND date < ?', a);
    d.purchases = await s.scalar(
        'SELECT COALESCE(SUM(total),0) FROM purchases WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?', a);
    d.moneyIn = await s.scalar(
        "SELECT COALESCE(SUM(amount),0) FROM payments WHERE direction = 'in' AND ref_type IS NOT 'transfer' "
        'AND deleted_at IS NULL AND created_at >= ? AND created_at < ?',
        a);
    d.moneyOut = await s.scalar(
        "SELECT COALESCE(SUM(amount),0) FROM payments WHERE direction = 'out' AND ref_type IS NOT 'transfer' "
        'AND deleted_at IS NULL AND created_at >= ? AND created_at < ?',
        a);

    d.series = await _series(p);
    if (!details) return d;

    d.topProducts = await s.q(
      'SELECT i.name, SUM(i.qty) AS qty, SUM(i.total) AS total, SUM(i.total - i.tax - i.cost_price * i.qty) AS profit '
      'FROM sale_items i JOIN sales s ON s.id = i.sale_id '
      "WHERE s.status = 'completed' AND s.deleted_at IS NULL AND i.deleted_at IS NULL AND s.created_at >= ? AND s.created_at < ? "
      'GROUP BY IFNULL(i.product_id, i.name) ORDER BY total DESC LIMIT 15',
      a,
    );
    d.byCategory = await s.q(
      "SELECT IFNULL(c.name, 'Uncategorized') AS name, SUM(i.qty) AS qty, SUM(i.total) AS total "
      'FROM sale_items i JOIN sales s ON s.id = i.sale_id LEFT JOIN products p ON p.id = i.product_id '
      'LEFT JOIN categories c ON c.id = p.category_id '
      "WHERE s.status = 'completed' AND s.deleted_at IS NULL AND i.deleted_at IS NULL AND s.created_at >= ? AND s.created_at < ? "
      'GROUP BY c.id ORDER BY total DESC',
      a,
    );
    d.byAccount = await s.q(
      "SELECT IFNULL(ac.name, 'Other') AS name, "
      "SUM(CASE WHEN p.direction = 'in' THEN p.amount ELSE 0 END) AS money_in, "
      "SUM(CASE WHEN p.direction = 'out' THEN p.amount ELSE 0 END) AS money_out "
      'FROM payments p LEFT JOIN accounts ac ON ac.id = p.account_id '
      'WHERE p.deleted_at IS NULL AND p.created_at >= ? AND p.created_at < ? GROUP BY p.account_id ORDER BY money_in DESC',
      a,
    );
    d.expensesByCategory = await s.q(
      "SELECT IFNULL(c.name, 'Other') AS name, SUM(e.amount) AS total FROM expenses e "
      'LEFT JOIN categories c ON c.id = e.category_id '
      'WHERE e.deleted_at IS NULL AND e.date >= ? AND e.date < ? GROUP BY e.category_id ORDER BY total DESC',
      a,
    );
    return d;
  }

  static Future<List<SeriesPoint>> _series(Period p) async {
    final rows = await Db.instance.s.q(
      "SELECT created_at, total, tax, cost_total FROM sales WHERE status = 'completed' AND deleted_at IS NULL "
      'AND created_at >= ? AND created_at < ?',
      [p.fromMs, p.toMs],
    );
    final days = (p.to.difference(p.from).inHours / 24).round();
    final byHour = p.kind == PeriodKind.day || days <= 1;
    final byMonth = p.kind == PeriodKind.year || days > 62;
    final points = <SeriesPoint>[];
    if (byHour) {
      for (var h = 0; h < 24; h++) {
        points.add(SeriesPoint('$h', 0, 0));
      }
    } else if (byMonth) {
      var m = DateTime(p.from.year, p.from.month);
      while (m.isBefore(p.to)) {
        points.add(SeriesPoint(DateFormat('MMM').format(m), 0, 0));
        m = DateTime(m.year, m.month + 1);
      }
    } else {
      for (var i = 0; i < days; i++) {
        final day = DateTime(p.from.year, p.from.month, p.from.day + i);
        points.add(SeriesPoint(
            p.kind == PeriodKind.week ? DateFormat('EEE').format(day) : DateFormat('d').format(day), 0, 0));
      }
    }
    for (final r in rows) {
      final t = DateTime.fromMillisecondsSinceEpoch(asInt(r['created_at']));
      int idx;
      if (byHour) {
        idx = t.hour;
      } else if (byMonth) {
        idx = (t.year - p.from.year) * 12 + t.month - p.from.month;
      } else {
        idx = (DateTime(t.year, t.month, t.day).difference(p.from).inHours / 24).round();
      }
      if (idx < 0 || idx >= points.length) continue;
      final total = asDouble(r['total']);
      points[idx].sales += total;
      points[idx].profit += total - asDouble(r['tax']) - asDouble(r['cost_total']);
    }
    return points;
  }
}
