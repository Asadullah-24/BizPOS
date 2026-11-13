import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import '../core/license.dart';
import '../core/packages.dart';
import 'invoice_service.dart';

class PrinterDevice {
  PrinterDevice(this.name, this.address);
  final String name;
  final String address;
}

/// Thermal receipt printing over Bluetooth or the network (ESC/POS, port 9100).
/// Printer choice is stored on this phone only.
class PrinterService {
  /// bluetooth | network | system
  static String get type => Local.prefs.getString('printer_type') ?? 'system';
  static String? get btAddress => Local.prefs.getString('printer_bt_address');
  static String? get btName => Local.prefs.getString('printer_bt_name');
  static String? get ip => Local.prefs.getString('printer_ip');
  static int get port => Local.prefs.getInt('printer_port') ?? 9100;

  static Future<void> saveBluetooth(PrinterDevice d) async {
    await Local.prefs.setString('printer_type', 'bluetooth');
    await Local.prefs.setString('printer_bt_address', d.address);
    await Local.prefs.setString('printer_bt_name', d.name);
  }

  static Future<void> saveNetwork(String ip, int port) async {
    await Local.prefs.setString('printer_type', 'network');
    await Local.prefs.setString('printer_ip', ip.trim());
    await Local.prefs.setInt('printer_port', port);
  }

  static Future<void> useSystem() => Local.prefs.setString('printer_type', 'system');

  static Future<bool> _askBluetooth() async {
    if (!Platform.isAndroid) return true;
    final res = await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    final connect = res[Permission.bluetoothConnect];
    // Below Android 12 these permissions do not exist and report as granted/denied by plugin version.
    return connect == null || connect.isGranted || connect.isLimited || (res[Permission.location]?.isGranted ?? false);
  }

  static Future<List<PrinterDevice>> pairedPrinters() async {
    await _askBluetooth();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw StateError('Turn on Bluetooth and pair the printer in phone settings first.');
    }
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list.map((b) => PrinterDevice(b.name, b.macAdress)).toList();
  }

  static Future<List<int>> receiptBytes(InvoiceData d) async {
    final app = AppState.instance;
    final profile = await CapabilityProfile.load();
    final g = Generator(app.paperMm >= 80 ? PaperSize.mm80 : PaperSize.mm58, profile);
    final s = app.settings;
    var b = <int>[];
    b += g.text(_ascii(app.businessName),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size1));
    for (final line in [s['business_address'], s['business_phone'], s['tax_number']]) {
      if (line != null && line.isNotEmpty) b += g.text(_ascii(line), styles: const PosStyles(align: PosAlign.center));
    }
    b += g.hr();
    b += g.text(_ascii('${d.title}  ${d.number}'), styles: const PosStyles(bold: true));
    b += g.text(Fmt.dateTime(d.date));
    if (d.partyName != null) b += g.text(_ascii('${d.partyLabel}: ${d.partyName}'));
    if (d.servedBy != null) b += g.text(_ascii('Served by: ${d.servedBy}'));
    b += g.hr();
    for (final l in d.lines) {
      b += g.text(_ascii(l.name));
      b += g.row([
        PosColumn(text: '${Fmt.qty(l.qty)} x ${Fmt.amount(l.price)}', width: 7),
        PosColumn(text: Fmt.amount(l.total), width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    b += g.hr();
    List<int> kv(String k, double v, {bool bold = false}) => g.row([
          PosColumn(text: _ascii(k), width: 6, styles: PosStyles(bold: bold)),
          PosColumn(text: _ascii(Fmt.money(v)), width: 6, styles: PosStyles(align: PosAlign.right, bold: bold)),
        ]);
    b += kv('Subtotal', d.subtotal);
    if (d.discount > 0) b += kv('Discount', -d.discount);
    if (d.tax > 0) b += kv('Tax', d.tax);
    b += kv('TOTAL', d.total, bold: true);
    for (final p in d.payments) {
      b += kv(p.key, p.value);
    }
    if (d.due.abs() > 0.009) b += kv('Balance due', d.due, bold: true);
    b += g.hr();
    b += g.text(_ascii(app.invoiceFooter), styles: const PosStyles(align: PosAlign.center));
    final lic = LicenseService.instance;
    b += g.text(_ascii('${lic.footer} ${Vendor.pretty(lic.phone)}'), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    b += g.feed(3);
    b += g.cut();
    return b;
  }

  /// Prints with the chosen printer. Returns false when the system dialog should be used.
  static Future<bool> printReceipt(InvoiceData d) async {
    switch (type) {
      case 'bluetooth':
        final addr = btAddress;
        if (addr == null) throw StateError('Choose a Bluetooth printer in Settings > Printer.');
        await _askBluetooth();
        var connected = await PrintBluetoothThermal.connectionStatus;
        if (!connected) connected = await PrintBluetoothThermal.connect(macPrinterAddress: addr);
        if (!connected) throw StateError('Could not connect to ${btName ?? addr}. Is it on and paired?');
        final ok = await PrintBluetoothThermal.writeBytes(await receiptBytes(d));
        if (!ok) throw StateError('Printer did not accept the receipt.');
        return true;
      case 'network':
        final host = ip;
        if (host == null || host.isEmpty) throw StateError('Set the printer IP in Settings > Printer.');
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
        socket.add(await receiptBytes(d));
        await socket.flush();
        await socket.close();
        return true;
      default:
        await InvoicePdf.printSystem(d, roll: true);
        return true;
    }
  }

  /// Thermal printers only know ASCII in their default code page.
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
}
