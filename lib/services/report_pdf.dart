import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import 'report_service.dart';

class ReportPdf {
  static Future<void> share(Period p, ReportData d) async {
    final app = AppState.instance;
    final doc = pw.Document(title: 'Report ${p.label}');
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

    pw.Widget kv(String k, double v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(k, style: strong ? bold : null)),
            pw.Text(Fmt.money(v), style: strong ? bold : null),
          ]),
        );

    pw.Widget table(String title, List<String> headers, List<List<String>> rows) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 14),
            pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            if (rows.isEmpty)
              pw.Text('No data')
            else
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: rows,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
          ],
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        pw.Text(app.businessName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Business report: ${p.label}'),
        pw.Text('Generated ${Fmt.dateTime(DateTime.now().millisecondsSinceEpoch)}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 16),
        pw.Text('Profit and loss', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        kv('Sales (${d.salesCount})', d.sales),
        kv('Returns', -d.returns),
        kv('Net sales', d.netSales, strong: true),
        kv('Tax collected', -d.tax),
        kv('Cost of goods sold', -d.cogs),
        kv('Gross profit', d.grossProfit, strong: true),
        kv('Expenses', -d.expenses),
        kv('Net profit', d.netProfit, strong: true),
        pw.SizedBox(height: 8),
        kv('Discounts given', d.discount),
        kv('Purchases', d.purchases),
        kv('Money in', d.moneyIn),
        kv('Money out', d.moneyOut),
        table('Top products', ['Product', 'Qty', 'Sales', 'Profit'], [
          for (final r in d.topProducts)
            [
              '${r['name']}',
              Fmt.qty(asDouble(r['qty'])),
              Fmt.amount(asDouble(r['total'])),
              Fmt.amount(asDouble(r['profit'])),
            ],
        ]),
        table('Sales by category', ['Category', 'Qty', 'Sales'], [
          for (final r in d.byCategory) ['${r['name']}', Fmt.qty(asDouble(r['qty'])), Fmt.amount(asDouble(r['total']))],
        ]),
        table('Accounts', ['Account', 'In', 'Out'], [
          for (final r in d.byAccount)
            ['${r['name']}', Fmt.amount(asDouble(r['money_in'])), Fmt.amount(asDouble(r['money_out']))],
        ]),
        table('Expenses by category', ['Category', 'Amount'], [
          for (final r in d.expensesByCategory) ['${r['name']}', Fmt.amount(asDouble(r['total']))],
        ]),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'report-${p.fromMs}.pdf');
  }
}
