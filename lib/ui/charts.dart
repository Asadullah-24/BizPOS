import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../services/report_service.dart';

/// Sales (and optionally profit) per bucket as grouped bars.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.points, this.showProfit = false, this.height = 200});
  final List<SeriesPoint> points;
  final bool showProfit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxY = points.fold<double>(0, (m, p) => p.sales > m ? p.sales : m);
    final every = points.length > 16 ? (points.length / 8).ceil() : 1;
    final barWidth = points.length > 20 ? 6.0 : (points.length > 10 ? 9.0 : 14.0);
    return SizedBox(
      height: height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: BarChart(
          BarChartData(
            maxY: maxY <= 0 ? 1 : maxY * 1.15,
            minY: 0,
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(x: i, barsSpace: 2, barRods: [
                  BarChartRodData(
                    toY: points[i].sales,
                    color: cs.primary,
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  if (showProfit)
                    BarChartRodData(
                      toY: points[i].profit < 0 ? 0 : points[i].profit,
                      color: cs.tertiary,
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                ]),
            ],
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withOpacity(0.4), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= points.length || i % every != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(points[i].label, style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${points[group.x].label}\n${tr(rodIndex == 0 ? 'Sales' : 'Profit')}: ${Fmt.money(rod.toY)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.showProfit});
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(tr(t), style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Wrap(spacing: 16, children: [
      dot(cs.primary, 'Sales'),
      if (showProfit) dot(cs.tertiary, 'Profit'),
    ]);
  }
}
