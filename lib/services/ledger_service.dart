import '../core/db.dart';
import '../models/models.dart';
import 'activity_log.dart';

/// Money movement: account balances, customer/supplier balances, payments.
///
/// Balances are always calculated from transactions, never stored, so merged
/// data from two phones adds up correctly.
class LedgerService {
  static const _customerBalance = '''
    (c.opening_balance
      + COALESCE((SELECT SUM(total) FROM sales WHERE customer_id = c.id AND status = 'completed' AND deleted_at IS NULL), 0)
      - COALESCE((SELECT SUM(total) FROM returns WHERE customer_id = c.id AND deleted_at IS NULL), 0)
      - COALESCE((SELECT SUM(amount) FROM payments WHERE party_type = 'customer' AND party_id = c.id AND direction = 'in' AND deleted_at IS NULL), 0)
      + COALESCE((SELECT SUM(amount) FROM payments WHERE party_type = 'customer' AND party_id = c.id AND direction = 'out' AND deleted_at IS NULL), 0)
    )''';

  static const _supplierBalance = '''
    (c.opening_balance
      + COALESCE((SELECT SUM(total) FROM purchases WHERE supplier_id = c.id AND deleted_at IS NULL), 0)
      - COALESCE((SELECT SUM(amount) FROM payments WHERE party_type = 'supplier' AND party_id = c.id AND direction = 'out' AND deleted_at IS NULL), 0)
      + COALESCE((SELECT SUM(amount) FROM payments WHERE party_type = 'supplier' AND party_id = c.id AND direction = 'in' AND deleted_at IS NULL), 0)
    )''';

  static String _table(String kind) => kind == 'supplier' ? 'suppliers' : 'customers';
  static String _balance(String kind) => kind == 'supplier' ? _supplierBalance : _customerBalance;

  static Future<List<Party>> parties(String kind, {String search = ''}) async {
    final like = '%${search.trim()}%';
    final rows = await Db.instance.s.q(
      'SELECT c.*, ${_balance(kind)} AS balance FROM ${_table(kind)} c '
      'WHERE c.deleted_at IS NULL AND (c.name LIKE ? OR IFNULL(c.phone, \'\') LIKE ?) '
      'ORDER BY c.name COLLATE NOCASE',
      [like, like],
    );
    return rows.map(Party.fromRow).toList();
  }

  static Future<Party?> party(String kind, String id) async {
    final r = await Db.instance.s.one(
      'SELECT c.*, ${_balance(kind)} AS balance FROM ${_table(kind)} c WHERE c.id = ?',
      [id],
    );
    return r == null ? null : Party.fromRow(r);
  }

  static Future<double> totalBalance(String kind) => Db.instance.s.scalar(
        'SELECT COALESCE(SUM(${_balance(kind)}), 0) FROM ${_table(kind)} c WHERE c.deleted_at IS NULL',
      );

  static Future<List<Account>> accounts() async {
    final rows = await Db.instance.s.q('''
      SELECT a.*, a.opening_balance + COALESCE((
        SELECT SUM(CASE WHEN p.direction = 'in' THEN p.amount ELSE -p.amount END)
        FROM payments p WHERE p.account_id = a.id AND p.deleted_at IS NULL), 0) AS balance
      FROM accounts a WHERE a.deleted_at IS NULL
      ORDER BY a.is_default DESC, a.name COLLATE NOCASE
    ''');
    return rows.map(Account.fromRow).toList();
  }

  static Future<Account?> defaultAccount() async {
    final list = await accounts();
    if (list.isEmpty) return null;
    return list.firstWhere((a) => a.isDefault, orElse: () => list.first);
  }

  static Future<String> addPayment(
    Store s, {
    required String direction,
    required String? accountId,
    required double amount,
    String? partyType,
    String? partyId,
    String? refType,
    String? refId,
    String? note,
    String? employeeId,
  }) {
    return s.insert('payments', {
      'direction': direction,
      'account_id': accountId,
      'amount': amount,
      'party_type': partyType,
      'party_id': partyId,
      'ref_type': refType,
      'ref_id': refId,
      'note': note,
      'employee_id': employeeId,
    });
  }

  /// Customer pays off their balance, or supplier is paid.
  static Future<void> settle({
    required String kind,
    required String partyId,
    required String accountId,
    required double amount,
    String? note,
    String? employeeId,
  }) async {
    await Db.instance.tx((s) async {
      final isCustomer = kind == 'customer';
      await addPayment(
        s,
        direction: isCustomer ? 'in' : 'out',
        accountId: accountId,
        amount: amount,
        partyType: kind,
        partyId: partyId,
        refType: isCustomer ? 'receivable' : 'payable',
        note: note,
        employeeId: employeeId,
      );
      final p = await s.byId(_table(kind), partyId);
      await ActivityLog.add(isCustomer ? 'Payment received' : 'Supplier paid',
          entity: kind, entityId: partyId, detail: '${p?['name']}: $amount', s: s);
    });
  }

  static Future<void> transfer({
    required String fromId,
    required String toId,
    required double amount,
    String? note,
    String? employeeId,
  }) async {
    await Db.instance.tx((s) async {
      final ref = await addPayment(s,
          direction: 'out', accountId: fromId, amount: amount, refType: 'transfer', note: note, employeeId: employeeId);
      await addPayment(s,
          direction: 'in', accountId: toId, amount: amount, refType: 'transfer', refId: ref, note: note, employeeId: employeeId);
      await ActivityLog.add('Transfer between accounts', entity: 'account', entityId: fromId, detail: '$amount', s: s);
    });
  }

  /// Account statement, newest first.
  static Future<List<DbRow>> accountTransactions(String accountId) => Db.instance.s.q(
        'SELECT * FROM payments WHERE account_id = ? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 500',
        [accountId],
      );

  /// Customer or supplier statement: invoices, returns and payments, newest first.
  static Future<List<DbRow>> statement(String kind, String partyId) async {
    final s = Db.instance.s;
    final rows = <DbRow>[];
    if (kind == 'customer') {
      rows.addAll(await s.q(
        "SELECT id, created_at, 'sale' AS kind, invoice_no AS ref, total AS amount, status FROM sales "
        'WHERE customer_id = ? AND deleted_at IS NULL',
        [partyId],
      ));
      rows.addAll(await s.q(
        "SELECT id, created_at, 'return' AS kind, return_no AS ref, total AS amount, type AS status FROM returns "
        'WHERE customer_id = ? AND deleted_at IS NULL',
        [partyId],
      ));
    } else {
      rows.addAll(await s.q(
        "SELECT id, created_at, 'purchase' AS kind, purchase_no AS ref, total AS amount, '' AS status FROM purchases "
        'WHERE supplier_id = ? AND deleted_at IS NULL',
        [partyId],
      ));
    }
    rows.addAll(await s.q(
      "SELECT id, created_at, 'payment_' || direction AS kind, IFNULL(note, '') AS ref, amount, ref_type AS status "
      'FROM payments WHERE party_type = ? AND party_id = ? AND deleted_at IS NULL',
      [kind, partyId],
    ));
    rows.sort((a, b) => asInt(b['created_at']).compareTo(asInt(a['created_at'])));
    return rows;
  }
}
