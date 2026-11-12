import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/i18n.dart';

/// Camera barcode scanner.
/// * Single mode: pops with the first code.
/// * Continuous mode: calls [onCode] for each new code and stays open (POS).
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.onCode});
  final Future<String?> Function(String code)? onCode;

  static Future<String?> scan(BuildContext context) =>
      Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  String? _last;
  DateTime _lastAt = DateTime(2000);
  String? _message;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    final now = DateTime.now();
    if (code == _last && now.difference(_lastAt).inMilliseconds < 2000) return;
    _last = code;
    _lastAt = now;
    if (widget.onCode == null) {
      _done = true;
      Navigator.pop(context, code);
      return;
    }
    final msg = await widget.onCode!(code);
    if (mounted) setState(() => _message = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(tr('Scan barcode')),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_message != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
      ]),
      bottomNavigationBar: widget.onCode == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
              ),
            ),
    );
  }
}
