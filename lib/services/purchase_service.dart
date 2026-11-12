import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import 'activity_log.dart';
import 'inventory_service.dart';
import 'ledger_service.dart';
import 'sales_service.dart';

class PurchaseLine {
  PurchaseLine({required this.productId, required this.name, required this.qty, required this.unitCost, this.trackStock = true});
  final String productId;
  final String name;
  double qty;
  double unitCost;
  bool trackStock;
  double get total => qty * unitCost;
}

class PurchaseService {
  /// Receives stock from a supplier. Product cost becomes the weighted average
  /// of the old stock and the new stock.
  static Future<String> create({
    String? supplierId,
    String? refNo,
    required List<PurchaseLine> lines,
    double discount = 0,
    double tax = 0,
    double paid = 0,
    String? accountId,
    String? note,
    int? date,
  }) async {
    if (lines.isEmpty) throw StateError('Add at least one item.');
    final subtotal = lines.fold<double>(0, (a, l) => a + l.total);
    final total = Fmt.round(subtotal - discount + tax);
    if (paid > total + 0.0001) throw StateError('Paid amount is more than the purchase total.');
    if (paid < total - 0.0001 && supplierId == null) {
      throw StateError('Select a supplier to buy on credit.');
    }
    if (paid > 0 && accountId == null) throw StateError('Choose the account you paid from.');
    final number = await SalesService.nextNumber('PUR');
    final userId = AppState.instance.user?.id;

    return Db.instance.tx((s) async {
      final id = await s.insert('purchases', {
        'purchase_no': number,
        'supplier_id': supplierId,
        'ref_no': refNo,
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paid': paid,
        'note': note,
        'employee_id': userId,
        if (date != null) 'created_at': date,
      });
      // Spread discount and tax over items so landed cost is accurate.
      final factor = subtotal > 0 ? total / subtotal : 1.0;
      final touched = <String>[];
      for (final l in lines) {
        await s.insert('purchase_items', {
          'purchase_id': id,
          'product_id': l.productId,
          'name': l.name,
          'qty': l.qty,
          'unit_cost': l.unitCost,
          'total': l.total,
        });
        final landed = l.unitCost * factor;
        if (l.trackStock) {
          final stock = await s.scalar(
              'SELECT COALESCE(SUM(qty), 0) FROM stock_movements WHERE product_id = ? AND deleted_at IS NULL',
              [l.productId]);
          final old = await s.scalar('SELECT cost_price FROM products WHERE id = ?', [l.productId]);
          final newCost = (stock > 0 && stock + l.qty > 0)
              ? (stock * old + l.qty * landed) / (stock + l.qty)
              : landed;
          await s.update('products', l.productId, {'cost_price': newCost});
          await InventoryService.addMovement(s,
              productId: l.productId, qty: l.qty, type: 'purchase', refId: id, unitCost: landed, employeeId: userId);
          touched.add(l.productId);
        } else {
          await s.update('products', l.productId, {'cost_price': landed});
        }
      }
      if (paid > 0) {
        await LedgerService.addPayment(s,
            direction: 'out',
            accountId: accountId,
            amount: paid,
            partyType: supplierId == null ? null : 'supplier',
            partyId: supplierId,
            refType: 'purchase',
            refId: id,
            employeeId: userId);
      }
      await InventoryService.refreshStock(s, touched);
      await ActivityLog.add('Purchase received',
          entity: 'purchase', entityId: id, detail: '$number ${Fmt.money(total)}', s: s);
      return id;
    });
  }

  /// Voids a purchase: removes its stock and payments.
  static Future<void> voidPurchase(String id) async {
    await Db.instance.tx((s) async {
      final pur = await s.byId('purchases', id);
      if (pur == null || pur['deleted_at'] != null) return;
      await s.softDelete('purchases', id);
      final items = await s.q('SELECT id FROM purchase_items WHERE purchase_id = ?', [id]);
      for (final i in items) {
        await s.softDelete('purchase_items', i['id'] as String);
      }
      final moves = await s.q(
          "SELECT id, product_id FROM stock_movements WHERE ref_id = ? AND type = 'purchase' AND deleted_at IS NULL", [id]);
      for (final m in moves) {
        await s.softDelete('stock_movements', m['id'] as String);
      }
      final pays = await s.q("SELECT id FROM payments WHERE ref_id = ? AND ref_type = 'purchase' AND deleted_at IS NULL", [id]);
      for (final p in pays) {
        await s.softDelete('payments', p['id'] as String);
      }
      await InventoryService.refreshStock(s, moves.map((m) => m['product_id'] as String));
      await ActivityLog.add('Purchase voided', entity: 'purchase', entityId: id, detail: '${pur['purchase_no']}', s: s);
    });
  }

  static Future<List<DbRow>> list({String? supplierId, int limit = 200}) => Db.instance.s.q(
        'SELECT p.*, s.name AS supplier_name FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id '
        'WHERE p.deleted_at IS NULL ${supplierId == null ? '' : 'AND p.supplier_id = ?'} '
        'ORDER BY p.created_at DESC LIMIT $limit',
        supplierId == null ? null : [supplierId],
      );

  static Future<DbRow?> purchase(String id) => Db.instance.s.one(
        'SELECT p.*, s.name AS supplier_name, s.phone AS supplier_phone FROM purchases p '
        'LEFT JOIN suppliers s ON s.id = p.supplier_id WHERE p.id = ?',
        [id],
      );

  static Future<List<DbRow>> items(String id) => Db.instance.s.q(
        'SELECT * FROM purchase_items WHERE purchase_id = ? AND deleted_at IS NULL',
        [id],
      );
}

class ExpenseService {
  static Future<void> add({
    required String? categoryId,
    required double amount,
    required String accountId,
    String? note,
    required int date,
  }) async {
    final userId = AppState.instance.user?.id;
    await Db.instance.tx((s) async {
      final id = await s.insert('expenses', {
        'category_id': categoryId,
        'amount': amount,
        'account_id': accountId,
        'note': note,
        'date': date,
        'employee_id': userId,
      });
      await LedgerService.addPayment(s,
          direction: 'out', accountId: accountId, amount: amount, refType: 'expense', refId: id, note: note, employeeId: userId);
      final cat = categoryId == null ? null : await s.byId('categories', categoryId);
      await ActivityLog.add('Expense added',
          entity: 'expense', entityId: id, detail: '${cat?['name'] ?? ''} ${Fmt.money(amount)}', s: s);
    });
  }

  static Future<void> delete(String id) async {
    await Db.instance.tx((s) async {
      await s.softDelete('expenses', id);
      final pays = await s.q("SELECT id FROM payments WHERE ref_id = ? AND ref_type = 'expense'", [id]);
      for (final p in pays) {
        await s.softDelete('payments', p['id'] as String);
      }
      await ActivityLog.add('Expense deleted', entity: 'expense', entityId: id, s: s);
    });
  }

  static Future<List<DbRow>> list({int? from, int? to, String? categoryId}) {
    final where = ['e.deleted_at IS NULL'];
    final args = <Object?>[];
    if (from != null) {
      where.add('e.date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('e.date < ?');
      args.add(to);
    }
    if (categoryId != null) {
      where.add('e.category_id = ?');
      args.add(categoryId);
    }
    return Db.instance.s.q(
      'SELECT e.*, c.name AS category_name, a.name AS account_name FROM expenses e '
      'LEFT JOIN categories c ON c.id = e.category_id LEFT JOIN accounts a ON a.id = e.account_id '
      'WHERE ${where.join(' AND ')} ORDER BY e.date DESC LIMIT 500',
      args,
    );
  }
}
