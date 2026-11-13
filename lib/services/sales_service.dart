import '../core/app_state.dart';
import '../core/db.dart';
import '../core/format.dart';
import 'activity_log.dart';
import 'cart.dart';
import 'inventory_service.dart';
import 'ledger_service.dart';

class SaleResult {
  SaleResult(this.saleId, this.change);
  final String saleId;

  /// Money to hand back when the customer paid more than the total.
  final double change;
}

class SalesService {
  /// Document numbers are unique per phone (prefix-DEVICE-00001), so two phones
  /// selling offline can never create the same invoice number.
  static Future<String> nextNumber(String prefix) async {
    final key = 'seq_$prefix';
    final next = (Local.prefs.getInt(key) ?? 0) + 1;
    await Local.prefs.setInt(key, next);
    final code = Db.instance.deviceId.replaceAll('-', '').substring(0, 4).toUpperCase();
    return '$prefix-$code-${next.toString().padLeft(5, '0')}';
  }

  static Future<SaleResult> completeSale(Cart cart, List<PaymentLine> payments) async {
    final app = AppState.instance;
    final totals = cart.compute(taxEnabled: app.taxEnabled, taxInclusive: app.taxInclusive);
    final total = Fmt.round(totals.total);
    final credit = cart.exchangeCredit > total ? total : cart.exchangeCredit;
    final extraCredit = cart.exchangeCredit - credit;

    var remaining = total - credit;
    final recorded = <PaymentLine>[];
    var tendered = 0.0;
    for (final p in payments) {
      if (p.amount <= 0) continue;
      tendered += p.amount;
      final use = p.amount > remaining ? remaining : p.amount;
      if (use > 0) {
        recorded.add(PaymentLine(accountId: p.accountId, accountName: p.accountName, amount: use));
        remaining -= use;
      }
    }
    final paid = recorded.fold<double>(0, (a, b) => a + b.amount);
    if (remaining > 0.0001 && cart.customerId == null) {
      throw StateError('Select a customer to sell on credit.');
    }

    final invoiceNo = await nextNumber(app.invoicePrefix.isEmpty ? 'INV' : app.invoicePrefix);
    final userId = app.user?.id;
    final refundAccount = extraCredit > 0.0001 ? await LedgerService.defaultAccount() : null;

    final saleId = await Db.instance.tx((s) async {
      final saleId = await s.insert('sales', {
        'invoice_no': invoiceNo,
        'customer_id': cart.customerId,
        'subtotal': Fmt.round(totals.subtotal),
        'discount': Fmt.round(totals.discount),
        'tax': totals.tax,
        'total': total,
        'paid': paid + credit,
        'credit_applied': credit,
        'cost_total': totals.cost,
        'items_count': totals.itemsCount,
        'status': 'completed',
        'note': cart.note.isEmpty ? null : cart.note,
        'source': cart.source,
        'ref': cart.ref,
        'employee_id': userId,
      });
      final touched = <String>[];
      for (final c in totals.lines) {
        final l = c.line;
        await s.insert('sale_items', {
          'sale_id': saleId,
          'product_id': l.productId,
          'name': l.name,
          'qty': l.qty,
          'unit_price': l.unitPrice,
          'cost_price': l.costPrice,
          'discount': c.discount,
          'tax_rate': l.taxRate,
          'tax': c.tax,
          'total': c.total,
        });
        if (l.productId != null && l.trackStock) {
          await InventoryService.addMovement(s,
              productId: l.productId!, qty: -l.qty, type: 'sale', refId: saleId, employeeId: userId);
          touched.add(l.productId!);
        }
      }
      for (final p in recorded) {
        await LedgerService.addPayment(s,
            direction: 'in',
            accountId: p.accountId,
            amount: p.amount,
            partyType: cart.customerId == null ? null : 'customer',
            partyId: cart.customerId,
            refType: 'sale',
            refId: saleId,
            employeeId: userId);
      }
      if (extraCredit > 0.0001 && cart.exchangeReturnId != null) {
        // Exchange worth more than the new items: refund the difference.
        await LedgerService.addPayment(s,
            direction: 'out',
            accountId: refundAccount?.id,
            amount: extraCredit,
            partyType: cart.customerId == null ? null : 'customer',
            partyId: cart.customerId,
            refType: 'return',
            refId: cart.exchangeReturnId,
            note: 'Exchange difference refunded',
            employeeId: userId);
      }
      await InventoryService.refreshStock(s, touched);
      await ActivityLog.add('Sale completed',
          entity: 'sale', entityId: saleId, detail: '$invoiceNo  ${Fmt.money(total)}', s: s);
      return saleId;
    });
    return SaleResult(saleId, tendered - paid > 0 ? tendered - paid : 0);
  }

  /// Cancels a sale: puts stock back and refunds every payment to its account.
  static Future<void> cancelSale(String saleId, {String? reason}) async {
    await Db.instance.tx((s) async {
      final sale = await s.byId('sales', saleId);
      if (sale == null) throw StateError('Sale not found.');
      if (sale['status'] == 'cancelled') return;
      final hasReturns = await s.scalar(
          'SELECT COUNT(*) FROM returns WHERE sale_id = ? AND deleted_at IS NULL', [saleId]);
      if (hasReturns > 0) {
        throw StateError('This sale has returns. Process the remaining items as a return instead.');
      }
      final userId = AppState.instance.user?.id;
      await s.update('sales', saleId, {
        'status': 'cancelled',
        'note': [sale['note'], if (reason != null && reason.isNotEmpty) 'Cancelled: $reason']
            .whereType<String>()
            .join('\n'),
      });
      final items = await s.q('SELECT * FROM sale_items WHERE sale_id = ? AND deleted_at IS NULL', [saleId]);
      final touched = <String>[];
      for (final i in items) {
        final pid = i['product_id'] as String?;
        if (pid == null) continue;
        final moved = await s.scalar(
            "SELECT COUNT(*) FROM stock_movements WHERE ref_id = ? AND product_id = ? AND type = 'sale' AND deleted_at IS NULL",
            [saleId, pid]);
        if (moved > 0) {
          await InventoryService.addMovement(s,
              productId: pid, qty: asDouble(i['qty']), type: 'cancel', refId: saleId, employeeId: userId);
          touched.add(pid);
        }
      }
      final pays = await s.q(
          "SELECT * FROM payments WHERE ref_type = 'sale' AND ref_id = ? AND direction = 'in' AND deleted_at IS NULL",
          [saleId]);
      for (final p in pays) {
        await LedgerService.addPayment(s,
            direction: 'out',
            accountId: p['account_id'] as String?,
            amount: asDouble(p['amount']),
            partyType: p['party_type'] as String?,
            partyId: p['party_id'] as String?,
            refType: 'sale_cancel',
            refId: saleId,
            note: 'Refund for cancelled sale',
            employeeId: userId);
      }
      await InventoryService.refreshStock(s, touched);
      await ActivityLog.add('Sale cancelled',
          entity: 'sale', entityId: saleId, detail: '${sale['invoice_no']} ${reason ?? ''}', s: s);
    });
  }

  static Future<DbRow?> sale(String id) => Db.instance.s.one(
        'SELECT s.*, c.name AS customer_name, c.phone AS customer_phone, e.name AS employee_name '
        'FROM sales s LEFT JOIN customers c ON c.id = s.customer_id '
        'LEFT JOIN employees e ON e.id = s.employee_id WHERE s.id = ?',
        [id],
      );

  static Future<List<DbRow>> items(String saleId) => Db.instance.s.q(
        'SELECT * FROM sale_items WHERE sale_id = ? AND deleted_at IS NULL ORDER BY created_at',
        [saleId],
      );

  static Future<List<DbRow>> payments(String saleId) => Db.instance.s.q(
        'SELECT p.*, a.name AS account_name FROM payments p LEFT JOIN accounts a ON a.id = p.account_id '
        "WHERE p.ref_id = ? AND p.ref_type IN ('sale', 'sale_cancel') AND p.deleted_at IS NULL ORDER BY p.created_at",
        [saleId],
      );

  /// Quantity already returned for each sale item.
  static Future<Map<String, double>> returnedQty(String saleId) async {
    final rows = await Db.instance.s.q(
      'SELECT ri.sale_item_id, SUM(ri.qty) AS q FROM return_items ri JOIN returns r ON r.id = ri.return_id '
      'WHERE r.sale_id = ? AND r.deleted_at IS NULL AND ri.deleted_at IS NULL GROUP BY ri.sale_item_id',
      [saleId],
    );
    return {for (final r in rows) (r['sale_item_id'] ?? '') as String: asDouble(r['q'])};
  }

  static Future<List<DbRow>> list({int? from, int? to, String search = '', String? status, int limit = 200}) {
    final where = <String>['s.deleted_at IS NULL'];
    final args = <Object?>[];
    if (from != null) {
      where.add('s.created_at >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('s.created_at < ?');
      args.add(to);
    }
    if (status != null) {
      where.add('s.status = ?');
      args.add(status);
    }
    if (search.trim().isNotEmpty) {
      where.add("(s.invoice_no LIKE ? OR IFNULL(c.name, '') LIKE ? OR IFNULL(c.phone, '') LIKE ?)");
      final like = '%${search.trim()}%';
      args.addAll([like, like, like]);
    }
    return Db.instance.s.q(
      'SELECT s.*, c.name AS customer_name FROM sales s LEFT JOIN customers c ON c.id = s.customer_id '
      'WHERE ${where.join(' AND ')} ORDER BY s.created_at DESC LIMIT $limit',
      args,
    );
  }
}
