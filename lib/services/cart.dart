/// Pure cart maths (no Flutter, no database) so it can be unit tested.
library;

class CartLine {
  CartLine({
    required this.productId,
    required this.name,
    required this.unitPrice,
    this.qty = 1,
    this.costPrice = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.unit,
    this.trackStock = true,
    this.stock = 0,
  });

  final String? productId;
  String name;
  double qty;
  double unitPrice;
  double costPrice;

  /// Discount amount for the whole line (not per unit).
  double discount;

  /// Tax percent, e.g. 17 for 17%.
  double taxRate;
  String? unit;
  bool trackStock;
  double stock;

  double get gross => qty * unitPrice;
}

class LineCalc {
  LineCalc(this.line, this.gross, this.discount, this.net, this.tax, this.total);
  final CartLine line;
  final double gross;

  /// Line discount plus its share of the cart discount.
  final double discount;

  /// Amount after discounts, before exclusive tax.
  final double net;
  final double tax;
  final double total;
}

class CartTotals {
  CartTotals({
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.cartDiscount,
    required this.tax,
    required this.total,
    required this.cost,
    required this.itemsCount,
  });

  final List<LineCalc> lines;
  final double subtotal;
  final double discount;
  final double cartDiscount;
  final double tax;
  final double total;
  final double cost;
  final double itemsCount;
}

class Cart {
  final List<CartLine> lines = [];
  double cartDiscount = 0;
  bool cartDiscountPercent = false;
  String? customerId;
  String? customerName;
  String note = '';

  /// pos | online, and the online order id for online sales.
  String source = 'pos';
  String? ref;

  /// Store credit from an exchange, applied as a payment at checkout.
  double exchangeCredit = 0;
  String? exchangeReturnId;

  bool get isEmpty => lines.isEmpty;

  void add(CartLine line) {
    if (line.productId != null) {
      for (final l in lines) {
        if (l.productId == line.productId && l.unitPrice == line.unitPrice) {
          l.qty += line.qty;
          return;
        }
      }
    }
    lines.add(line);
  }

  void clear() {
    lines.clear();
    cartDiscount = 0;
    cartDiscountPercent = false;
    customerId = null;
    customerName = null;
    note = '';
    source = 'pos';
    ref = null;
    exchangeCredit = 0;
    exchangeReturnId = null;
  }

  CartTotals compute({required bool taxEnabled, required bool taxInclusive}) {
    final afterLine = <double>[];
    var subtotal = 0.0;
    var lineDiscounts = 0.0;
    for (final l in lines) {
      final g = l.gross;
      final d = l.discount.clamp(0, g < 0 ? 0 : g).toDouble();
      subtotal += g;
      lineDiscounts += d;
      afterLine.add(g - d);
    }
    final base = afterLine.fold<double>(0, (a, b) => a + b);
    var cartDisc = cartDiscountPercent ? base * cartDiscount / 100 : cartDiscount;
    if (cartDisc > base) cartDisc = base;
    if (cartDisc < 0) cartDisc = 0;

    final calcs = <LineCalc>[];
    var tax = 0.0;
    var total = 0.0;
    var cost = 0.0;
    var count = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final alloc = base > 0 ? cartDisc * afterLine[i] / base : 0.0;
      final net = afterLine[i] - alloc;
      double t;
      double lineTotal;
      if (!taxEnabled || l.taxRate <= 0) {
        t = 0;
        lineTotal = net;
      } else if (taxInclusive) {
        lineTotal = net;
        t = net - net / (1 + l.taxRate / 100);
      } else {
        t = net * l.taxRate / 100;
        lineTotal = net + t;
      }
      tax += t;
      total += lineTotal;
      cost += l.costPrice * l.qty;
      count += l.qty;
      calcs.add(LineCalc(l, l.gross, (l.gross - afterLine[i]) + alloc, net, t, lineTotal));
    }

    return CartTotals(
      lines: calcs,
      subtotal: subtotal,
      discount: lineDiscounts + cartDisc,
      cartDiscount: cartDisc,
      tax: tax,
      total: total,
      cost: cost,
      itemsCount: count,
    );
  }
}

/// One payment line at checkout (cash, card, wallet...).
class PaymentLine {
  PaymentLine({required this.accountId, required this.accountName, required this.amount});
  String accountId;
  String accountName;
  double amount;
}
