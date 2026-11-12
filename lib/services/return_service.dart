import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import 'activity_log.dart';
import 'inventory_service.dart';
import 'ledger_service.dart';
import 'sales_service.dart';

class ReturnLineInput {
  ReturnLineInput({required this.saleItem, required this.qty, this.restock = true});
  final DbRow saleItem;
  double qty;
  bool restock;
}

/// type:
/// * refund   - money goes back to the customer from [refundAccountId]
/// * credit   - added to the customer's balance (needs a customer)
/// * exchange - value becomes credit for a new sale at the POS
class ReturnService {
  static Future<({String id, double total, String? customerId})> create({
    required String saleId,
    required List<ReturnLineInput> lines,
    required String type,
    String? refundAccountId,
    String? note,
  }) async {
    final sale = await SalesService.sale(saleId);
    if (sale == null) throw StateError('Sale not found.');
    if (sale['status'] == 'cancelled') throw StateError('This sale is cancelled.');
    final already = await SalesService.returnedQty(saleId);
    final customerId = sale['customer_id'] as String?;
    if (type == 'credit' && customerId == null) {
      throw StateError('Store credit needs a customer on the sale.');
    }

    var total = 0.0;
    var cost = 0.0;
    final valid = <ReturnLineInput>[];
    for (final l in lines) {
      if (l.qty <= 0) continue;
      final soldQty = asDouble(l.saleItem['qty']);
      final left = soldQty - (already[l.saleItem['id']] ?? 0);
      if (l.qty > left + 0.0001) {
        throw StateError('Only ${Fmt.qty(left)} of ${l.saleItem['name']} can still be returned.');
      }
      valid.add(l);
      total += asDouble(l.saleItem['total']) / soldQty * l.qty;
      if (l.restock) cost += asDouble(l.saleItem['cost_price']) * l.qty;
    }
    if (valid.isEmpty) throw StateError('Choose at least one item to return.');
    total = Fmt.round(total);

    final number = await SalesService.nextNumber('RET');
    final userId = AppState.instance.user?.id;

    final id = await Db.instance.tx((s) async {
      final id = await s.insert('returns', {
        'return_no': number,
        'sale_id': saleId,
        'customer_id': customerId,
        'type': type,
        'total': total,
        'refund': type == 'refund' ? total : 0,
        'cost_total': cost,
        'note': note,
        'employee_id': userId,
      });
      final touched = <String>[];
      for (final l in valid) {
        final it = l.saleItem;
        final soldQty = asDouble(it['qty']);
        await s.insert('return_items', {
          'return_id': id,
          'sale_item_id': it['id'],
          'product_id': it['product_id'],
          'name': it['name'],
          'qty': l.qty,
          'unit_price': asDouble(it['total']) / soldQty,
          'cost_price': asDouble(it['cost_price']),
          'total': asDouble(it['total']) / soldQty * l.qty,
          'restock': l.restock ? 1 : 0,
        });
        final pid = it['product_id'] as String?;
        if (l.restock && pid != null) {
          final tracked = await s.scalar('SELECT track_stock FROM products WHERE id = ?', [pid]);
          if (tracked == 1) {
            await InventoryService.addMovement(s,
                productId: pid, qty: l.qty, type: 'return', refId: id, employeeId: userId);
            touched.add(pid);
          }
        }
      }
      if (type == 'refund') {
        await LedgerService.addPayment(s,
            direction: 'out',
            accountId: refundAccountId,
            amount: total,
            partyType: customerId == null ? null : 'customer',
            partyId: customerId,
            refType: 'return',
            refId: id,
            employeeId: userId);
      }
      await InventoryService.refreshStock(s, touched);
      await ActivityLog.add('Return processed',
          entity: 'return', entityId: id, detail: '$number ($type) ${Fmt.money(total)}', s: s);
      return id;
    });
    return (id: id, total: total, customerId: customerId);
  }

  static Future<List<DbRow>> list({int limit = 200}) => Db.instance.s.q(
        'SELECT r.*, s.invoice_no, c.name AS customer_name FROM returns r '
        'LEFT JOIN sales s ON s.id = r.sale_id LEFT JOIN customers c ON c.id = r.customer_id '
        'WHERE r.deleted_at IS NULL ORDER BY r.created_at DESC LIMIT $limit',
      );

  static Future<List<DbRow>> forSale(String saleId) => Db.instance.s.q(
        'SELECT * FROM returns WHERE sale_id = ? AND deleted_at IS NULL ORDER BY created_at',
        [saleId],
      );

  static Future<List<DbRow>> items(String returnId) => Db.instance.s.q(
        'SELECT * FROM return_items WHERE return_id = ? AND deleted_at IS NULL',
        [returnId],
      );
}
