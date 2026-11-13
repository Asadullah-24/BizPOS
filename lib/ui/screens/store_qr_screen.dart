import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../common.dart';

/// Contact card QR for the shop (customers scan it to save the shop number).
/// In the marketplace phase this becomes the shop's online page link.
String storeQrData() {
  final app = AppState.instance;
  final s = app.settings;
  String clean(String? v) => (v ?? '').replaceAll(RegExp(r'[;:,]'), ' ');
  return 'MECARD:N:${clean(app.businessName)};TEL:${clean(s['business_phone'])};'
      'ADR:${clean(s['business_address'])};NOTE:BizPOS shop ${LicenseService.instance.storeId ?? ''};;';
}

class StoreQrScreen extends StatelessWidget {
  const StoreQrScreen({super.key});

  Future<void> _shareImage() async {
    final painter = QrPainter(data: storeQrData(), version: QrVersions.auto, gapless: true, emptyColor: Colors.white);
    final data = await painter.toImageData(900, format: ui.ImageByteFormat.png);
    if (data == null) return;
    await Share.shareXFiles([XFile.fromData(data.buffer.asUint8List(), name: 'shop-qr.png', mimeType: 'image/png')],
        text: AppState.instance.businessName);
  }

  Future<void> _print() async {
    final app = AppState.instance;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (_) => pw.Center(
        child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text(app.businessName, style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(app.settings['business_phone'] ?? ''),
          pw.SizedBox(height: 20),
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: storeQrData(), width: 260, height: 260),
          pw.SizedBox(height: 16),
          pw.Text('Scan to save our contact'),
          pw.SizedBox(height: 30),
          pw.Text(LicenseService.instance.footer, style: const pw.TextStyle(fontSize: 9)),
        ]),
      ),
    ));
    await Printing.layoutPdf(name: 'shop-qr', onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Shop QR code'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(app.businessName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: storeQrData(), size: 260, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('Customers scan this to save your shop name, phone and address. Print it for your counter.'),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () => guard(context, _print), icon: const Icon(Icons.print), label: Text(tr('Print'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => guard(context, _shareImage), icon: const Icon(Icons.share), label: Text(tr('Share'))),
      ]),
    );
  }
}
