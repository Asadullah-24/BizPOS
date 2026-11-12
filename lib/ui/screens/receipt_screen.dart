import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/invoice_service.dart';
import '../../services/printer_service.dart';
import '../common.dart';

/// Shown after a sale: change due, print and share options.
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.saleId, this.change = 0});
  final String saleId;
  final double change;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  InvoiceData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await InvoiceData.forSale(widget.saleId);
    if (!mounted) return;
    setState(() => _data = d);
    if (AppState.instance.settings['auto_print'] == '1') _print();
  }

  Future<void> _print() async {
    final d = _data;
    if (d == null) return;
    await guard(context, () => PrinterService.printReceipt(d));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sale completed')), automaticallyImplyLeading: false),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Icon(Icons.check_circle, size: 72, color: Colors.green.shade600),
                  const SizedBox(height: 8),
                  Text(d.number, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  Text(Fmt.money(d.total),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (widget.change > 0.009)
                    Card(
                      color: cs.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('${tr('Give change')}: ${Fmt.money(widget.change)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onTertiaryContainer)),
                      ),
                    ),
                  if (d.due > 0.009)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${tr('On credit')}: ${Fmt.money(d.due)}',
                          textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontSize: 16)),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: _print, icon: const Icon(Icons.print), label: Text(tr('Print receipt'))),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => guard(context, () => InvoicePdf.share(d)),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(tr('Share invoice PDF')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => guard(context, () => InvoicePdf.share(d, roll: true)),
                    icon: const Icon(Icons.receipt),
                    label: Text(tr('Share receipt')),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(tr('New sale')),
                  ),
                ]),
              ),
            ),
    );
  }
}
