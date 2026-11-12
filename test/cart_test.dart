import 'package:bizpos/services/cart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CartLine line(double price, {double qty = 1, double discount = 0, double tax = 0}) =>
      CartLine(productId: null, name: 'Item', unitPrice: price, qty: qty, discount: discount, taxRate: tax);

  test('subtotal and total without tax or discount', () {
    final c = Cart()..lines.addAll([line(100, qty: 2), line(50)]);
    final t = c.compute(taxEnabled: false, taxInclusive: false);
    expect(t.subtotal, 250);
    expect(t.total, 250);
    expect(t.tax, 0);
    expect(t.itemsCount, 3);
  });

  test('line discount and percent cart discount', () {
    final c = Cart()
      ..lines.addAll([line(100, qty: 2, discount: 20), line(20)])
      ..cartDiscount = 10
      ..cartDiscountPercent = true;
    final t = c.compute(taxEnabled: false, taxInclusive: false);
    // (200 - 20) + 20 = 200, minus 10% = 180
    expect(t.total, closeTo(180, 1e-9));
    expect(t.discount, closeTo(40, 1e-9));
  });

  test('exclusive tax is added on top', () {
    final c = Cart()..lines.add(line(100, tax: 17));
    final t = c.compute(taxEnabled: true, taxInclusive: false);
    expect(t.tax, closeTo(17, 1e-9));
    expect(t.total, closeTo(117, 1e-9));
  });

  test('inclusive tax is extracted from the price', () {
    final c = Cart()..lines.add(line(117, tax: 17));
    final t = c.compute(taxEnabled: true, taxInclusive: true);
    expect(t.total, closeTo(117, 1e-9));
    expect(t.tax, closeTo(17, 1e-9));
  });

  test('fixed cart discount never exceeds the cart value', () {
    final c = Cart()
      ..lines.add(line(50))
      ..cartDiscount = 80;
    final t = c.compute(taxEnabled: false, taxInclusive: false);
    expect(t.total, 0);
  });

  test('adding the same product merges quantities', () {
    final c = Cart();
    c.add(CartLine(productId: 'p1', name: 'A', unitPrice: 10));
    c.add(CartLine(productId: 'p1', name: 'A', unitPrice: 10, qty: 2));
    expect(c.lines.length, 1);
    expect(c.lines.first.qty, 3);
  });
}
