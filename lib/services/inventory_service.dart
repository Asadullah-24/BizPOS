import '../core/db.dart';
import 'activity_log.dart';

/// Stock is never stored as an editable number. Every change is a row in
/// stock_movements, and products.stock is a cache of their sum. Two phones that
/// sell the same product offline both keep their movements after a merge, so
/// stock stays correct.
class InventoryService {
  static Future<void> addMovement(
    Store s, {
    required String productId,
    required double qty,
    required String type,
    String? refId,
    double? unitCost,
    String? note,
    String? employeeId,
  }) async {
    if (qty == 0) return;
    await s.insert('stock_movements', {
      'product_id': productId,
      'qty': qty,
      'type': type,
      'ref_id': refId,
      'unit_cost': unitCost,
      'note': note,
      'employee_id': employeeId,
    });
  }

  static Future<void> refreshStock(Store s, Iterable<String> productIds) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    await s.ex.rawUpdate(
      'UPDATE products SET stock = (SELECT COALESCE(SUM(m.qty), 0) FROM stock_movements m '
      'WHERE m.product_id = products.id AND m.deleted_at IS NULL) WHERE id IN ($marks)',
      ids,
    );
  }

  static Future<void> refreshAllStock(Store s) async {
    await s.ex.rawUpdate(
      'UPDATE products SET stock = (SELECT COALESCE(SUM(m.qty), 0) FROM stock_movements m '
      'WHERE m.product_id = products.id AND m.deleted_at IS NULL)',
    );
  }

  /// mode: add | remove | set
  static Future<void> adjust({
    required String productId,
    required String mode,
    required double qty,
    String? note,
    String? employeeId,
  }) async {
    await Db.instance.tx((s) async {
      final current = await s.scalar(
        'SELECT COALESCE(SUM(qty), 0) FROM stock_movements WHERE product_id = ? AND deleted_at IS NULL',
        [productId],
      );
      double delta;
      switch (mode) {
        case 'add':
          delta = qty;
          break;
        case 'remove':
          delta = -qty;
          break;
        default:
          delta = qty - current;
      }
      await addMovement(s,
          productId: productId, qty: delta, type: 'adjustment', note: note, employeeId: employeeId);
      await refreshStock(s, [productId]);
      final p = await s.byId('products', productId);
      await ActivityLog.add('Stock adjusted',
          entity: 'product',
          entityId: productId,
          detail: '${p?['name']}: ${delta > 0 ? '+' : ''}$delta${note == null || note.isEmpty ? '' : ' ($note)'}',
          s: s);
    });
  }

  static Future<List<DbRow>> movements(String productId) => Db.instance.s.q(
        'SELECT * FROM stock_movements WHERE product_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 300',
        [productId],
      );
}
