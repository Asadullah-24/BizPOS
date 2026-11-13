import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/inventory_service.dart';
import '../../services/product_service.dart';
import '../common.dart';
import 'product_form.dart';
import 'scanner_screen.dart';

/// Scan barcodes one after another to add or remove stock.
class StockScanScreen extends StatefulWidget {
  const StockScanScreen({super.key});

  @override
  State<StockScanScreen> createState() => _StockScanScreenState();
}

class _StockScanScreenState extends State<StockScanScreen> {
  String _mode = 'add';
  final _qty = TextEditingController(text: '1');
  final List<String> _log = [];
  final Set<String> _unknown = {};

  Future<String?> _onCode(String code) async {
    final p = await ProductService.findByCode(code);
    if (p == null) {
      setState(() => _unknown.add(code));
      return '${tr('Unknown barcode')} $code. ${tr('You can add it after scanning.')}';
    }
    final q = Fmt.parse(_qty.text);
    if (q <= 0) return tr('Enter a quantity above zero.');
    try {
      await InventoryService.adjust(
        productId: p.id,
        mode: _mode,
        qty: q,
        note: 'Barcode scan',
        employeeId: AppState.instance.user?.id,
      );
    } catch (e) {
      return errorText(e);
    }
    final fresh = await ProductService.byId(p.id);
    final line = '${_mode == 'add' ? '+' : '-'}${Fmt.qty(q)} ${p.displayName} → ${Fmt.qty(fresh?.stock ?? 0)}';
    if (mounted) setState(() => _log.insert(0, line));
    return line;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Scan to add or remove stock'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'add', label: Text(tr('Add stock')), icon: const Icon(Icons.add)),
            ButtonSegment(value: 'remove', label: Text(tr('Remove stock')), icon: const Icon(Icons.remove)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        NumField(controller: _qty, label: 'Quantity per scan'),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(tr('Start scanning')),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(onCode: _onCode))),
        ),
        if (_unknown.isNotEmpty) ...[
          const SectionTitle('Unknown barcodes'),
          for (final code in _unknown.toList())
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(code),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(initialBarcode: code)));
                  if (await ProductService.findByCode(code) != null) setState(() => _unknown.remove(code));
                },
                child: Text(tr('Add product')),
              ),
            ),
        ],
        if (_log.isNotEmpty) ...[
          const SectionTitle('Scanned'),
          for (final l in _log) ListTile(dense: true, leading: const Icon(Icons.check, color: Colors.green), title: Text(l)),
        ],
      ]),
    );
  }
}
