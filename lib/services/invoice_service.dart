import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/access.dart';
import '../core/format.dart';
import '../core/license.dart';
import '../core/packages.dart';
import 'product_service.dart';
import 'purchase_service.dart';
import 'sales_service.dart';

class DocLine {
  DocLine(this.name, this.qty, this.price, this.total);
  final String name;
  final double qty;
  final double price;
  final double total;
}

/// Everything a receipt or invoice needs, independent of output (PDF or thermal).
class InvoiceData {
  InvoiceData({
    required this.title,
    required this.number,
    required this.date,
    required this.partyLabel,
    this.partyName,
    this.partyPhone,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    this.payments = const [],
    this.status,
    this.note,
    this.servedBy,
  });

  final String title;
  final String number;
  final int date;
  final String partyLabel;
  final String? partyName;
  final String? partyPhone;
  final List<DocLine> lines;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final List<MapEntry<String, double>> payments;
  final String? status;
  final String? note;
  final String? servedBy;

  double get due => total - paid;

  static Future<InvoiceData> forSale(String saleId) async {
    final s = await SalesService.sale(saleId);
    if (s == null) throw StateError('Sale not found.');
    final items = await SalesService.items(saleId);
    final pays = await SalesService.payments(saleId);
    final credit = asDouble(s['credit_applied']);
    return InvoiceData(
      title: s['status'] == 'cancelled' ? 'CANCELLED INVOICE' : 'INVOICE',
      number: s['invoice_no'] as String,
      date: asInt(s['created_at']),
      partyLabel: 'Customer',
      partyName: s['customer_name'] as String?,
      partyPhone: s['customer_phone'] as String?,
      lines: [
        for (final i in items)
          DocLine(i['name'] as String, asDouble(i['qty']), asDouble(i['unit_price']), asDouble(i['total'])),
      ],
      subtotal: asDouble(s['subtotal']),
      discount: asDouble(s['discount']),
      tax: asDouble(s['tax']),
      total: asDouble(s['total']),
      paid: asDouble(s['paid']),
      payments: [
        for (final p in pays)
          if (p['direction'] == 'in') MapEntry((p['account_name'] ?? 'Payment') as String, asDouble(p['amount'])),
        if (credit > 0) MapEntry('Exchange credit', credit),
      ],
      status: s['status'] as String?,
      note: s['note'] as String?,
      servedBy: s['employee_name'] as String?,
    );
  }

  static Future<InvoiceData> forPurchase(String id) async {
    final p = await PurchaseService.purchase(id);
    if (p == null) throw StateError('Purchase not found.');
    final items = await PurchaseService.items(id);
    return InvoiceData(
      title: 'PURCHASE INVOICE',
      number: p['purchase_no'] as String,
      date: asInt(p['created_at']),
      partyLabel: 'Supplier',
      partyName: p['supplier_name'] as String?,
      partyPhone: p['supplier_phone'] as String?,
      lines: [
        for (final i in items)
          DocLine(i['name'] as String, asDouble(i['qty']), asDouble(i['unit_cost']), asDouble(i['total'])),
      ],
      subtotal: asDouble(p['subtotal']),
      discount: asDouble(p['discount']),
      tax: asDouble(p['tax']),
      total: asDouble(p['total']),
      paid: asDouble(p['paid']),
      note: [p['ref_no'] == null ? null : 'Supplier ref: ${p['ref_no']}', p['note']]
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .join('\n'),
    );
  }
}

class InvoicePdf {
  static Future<Uint8List> build(InvoiceData d, {bool roll = false}) async {
    final app = AppState.instance;
    final doc = pw.Document(title: '${d.title} ${d.number}');
    final mm = app.paperMm.toDouble();
    final format = roll
        ? PdfPageFormat(mm * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm)
        : PdfPageFormat.a4.copyWith(
            marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36);
    final small = pw.TextStyle(fontSize: roll ? 7 : 9);
    final normal = pw.TextStyle(fontSize: roll ? 8 : 10);
    final bold = pw.TextStyle(fontSize: roll ? 9 : 11, fontWeight: pw.FontWeight.bold);
    final big = pw.TextStyle(fontSize: roll ? 12 : 20, fontWeight: pw.FontWeight.bold);

    pw.Widget kv(String k, String v, {pw.TextStyle? style}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(k, style: style ?? normal)),
            pw.Text(v, style: style ?? normal),
          ]),
        );

    final s = app.settings;
    final logoFile = Access.instance.has(Feature.branding) ? await ImageStore.file(s['logo']) : null;
    final logo = logoFile == null ? null : pw.MemoryImage(await logoFile.readAsBytes());
    final lic = LicenseService.instance;
    final header = pw.Column(
      crossAxisAlignment: roll ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) pw.Image(logo, height: roll ? 40 : 56),
        pw.Text(app.businessName, style: big),
        if ((s['business_address'] ?? '').isNotEmpty) pw.Text(s['business_address']!, style: small),
        if ((s['business_phone'] ?? '').isNotEmpty) pw.Text('Phone: ${s['business_phone']}', style: small),
        if ((s['business_email'] ?? '').isNotEmpty) pw.Text(s['business_email']!, style: small),
        if ((s['tax_number'] ?? '').isNotEmpty) pw.Text('Tax no: ${s['tax_number']}', style: small),
      ],
    );

    final meta = pw.Column(
      crossAxisAlignment: roll ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.end,
      children: [
        pw.Text(d.title, style: bold),
        pw.Text(d.number, style: normal),
        pw.Text(Fmt.dateTime(d.date), style: small),
        if (d.partyName != null) pw.Text('${d.partyLabel}: ${d.partyName}', style: small),
        if (d.partyPhone != null && d.partyPhone!.isNotEmpty) pw.Text(d.partyPhone!, style: small),
        if (d.servedBy != null) pw.Text('Served by: ${d.servedBy}', style: small),
      ],
    );

    final table = pw.TableHelper.fromTextArray(
      headers: roll ? ['Item', 'Qty', 'Total'] : ['#', 'Item', 'Qty', 'Price', 'Total'],
      data: [
        for (var i = 0; i < d.lines.length; i++)
          roll
              ? [d.lines[i].name, Fmt.qty(d.lines[i].qty), Fmt.amount(d.lines[i].total)]
              : [
                  '${i + 1}',
                  d.lines[i].name,
                  Fmt.qty(d.lines[i].qty),
                  Fmt.amount(d.lines[i].price),
                  Fmt.amount(d.lines[i].total),
                ],
      ],
      headerStyle: bold,
      cellStyle: normal,
      border: roll ? null : pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerDecoration: roll ? null : const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: roll
          ? {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight}
          : {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
      cellPadding: pw.EdgeInsets.all(roll ? 1 : 4),
    );

    final totals = pw.Container(
      width: roll ? null : 220,
      child: pw.Column(children: [
        kv('Subtotal', Fmt.money(d.subtotal)),
        if (d.discount > 0) kv('Discount', '-${Fmt.money(d.discount)}'),
        if (d.tax > 0) kv('Tax', Fmt.money(d.tax)),
        pw.Divider(height: 4, thickness: 0.5),
        kv('Total', Fmt.money(d.total), style: bold),
        for (final p in d.payments) kv(p.key, Fmt.money(p.value), style: small),
        kv('Paid', Fmt.money(d.paid)),
        if (d.due.abs() > 0.009) kv('Balance due', Fmt.money(d.due), style: bold),
      ]),
    );

    doc.addPage(pw.Page(
      pageFormat: format,
      build: (ctx) => pw.Column(
        crossAxisAlignment: roll ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
        children: [
          if (roll) ...[header, pw.SizedBox(height: 4), meta] else
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: header),
              meta,
            ]),
          pw.SizedBox(height: roll ? 6 : 16),
          table,
          pw.SizedBox(height: 8),
          pw.Align(alignment: pw.Alignment.centerRight, child: totals),
          if (d.note != null && d.note!.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(d.note!, style: small),
          ],
          pw.SizedBox(height: roll ? 8 : 24),
          pw.Center(child: pw.Text(app.invoiceFooter, style: small, textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('${lic.footer} - ${Vendor.pretty(lic.phone)}',
                style: pw.TextStyle(fontSize: roll ? 6 : 8, color: PdfColors.grey600)),
          ),
        ],
      ),
    ));
    return doc.save();
  }

  static Future<void> share(InvoiceData d, {bool roll = false}) async {
    final bytes = await build(d, roll: roll);
    await Printing.sharePdf(bytes: bytes, filename: '${d.number}.pdf');
  }

  /// System print dialog: Wi-Fi/network printers and PDF save.
  static Future<void> printSystem(InvoiceData d, {bool roll = false}) async {
    await Printing.layoutPdf(name: d.number, onLayout: (_) => build(d, roll: roll));
  }
}
