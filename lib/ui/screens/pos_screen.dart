import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/cart.dart';
import '../../services/product_service.dart';
import '../common.dart';
import 'checkout_screen.dart';
import 'parties_screen.dart';
import 'scanner_screen.dart';

/// The cart lives outside the screen so it survives tab switches.
class PosController extends ChangeNotifier {
  PosController._();
  static final PosController instance = PosController._();

  final Cart cart = Cart();

  CartTotals get totals {
    final app = AppState.instance;
    return cart.compute(taxEnabled: app.taxEnabled, taxInclusive: app.taxInclusive);
  }

  double _taxFor(Product p) {
    final app = AppState.instance;
    if (!app.taxEnabled) return 0;
    return p.taxRate ?? app.defaultTaxRate;
  }

  double qtyInCart(String productId) =>
      cart.lines.where((l) => l.productId == productId).fold<double>(0, (a, l) => a + l.qty);

  /// Adds a product. Returns a warning when stock is short (or null).
  String? addProduct(Product p, {double qty = 1}) {
    final app = AppState.instance;
    String? warning;
    if (p.trackStock && app.hasModule(Mod.inventory)) {
      final want = qtyInCart(p.id) + qty;
      if (want > p.stock) {
        if (app.settings['block_out_of_stock'] == '1') return '${tr('Out of stock')}: ${p.displayName}';
        warning = '${tr('Only')} ${Fmt.qty(p.stock)} ${tr('in stock')}: ${p.displayName}';
      }
    }
    cart.add(CartLine(
      productId: p.id,
      name: p.displayName,
      unitPrice: p.salePrice,
      costPrice: p.costPrice,
      qty: qty,
      taxRate: _taxFor(p),
      unit: p.unit,
      trackStock: p.trackStock,
      stock: p.stock,
    ));
    notifyListeners();
    return warning;
  }

  void addCustom(String name, double price, double qty) {
    final app = AppState.instance;
    cart.add(CartLine(
      productId: null,
      name: name,
      unitPrice: price,
      qty: qty,
      taxRate: app.taxEnabled ? app.defaultTaxRate : 0,
      trackStock: false,
    ));
    notifyListeners();
  }

  void changeQty(CartLine l, double delta) {
    l.qty += delta;
    if (l.qty <= 0) cart.lines.remove(l);
    notifyListeners();
  }

  void remove(CartLine l) {
    cart.lines.remove(l);
    notifyListeners();
  }

  void setCustomer(Party? p) {
    cart.customerId = p?.id;
    cart.customerName = p?.name;
    notifyListeners();
  }

  void startExchange({required String returnId, required double credit, String? customerId, String? customerName}) {
    cart.clear();
    cart.exchangeReturnId = returnId;
    cart.exchangeCredit = credit;
    cart.customerId = customerId;
    cart.customerName = customerName;
    notifyListeners();
  }

  void clear() {
    cart.clear();
    notifyListeners();
  }

  void changed() => notifyListeners();
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  String _q = '';
  String? _categoryId;
  final pos = PosController.instance;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(Product p) {
    final w = pos.addProduct(p);
    if (w != null) showSnack(context, w, error: true);
  }

  /// Hardware barcode scanners type the code and press Enter.
  Future<void> _submitSearch(String v) async {
    final p = await ProductService.findByCode(v);
    if (!mounted) return;
    if (p != null) {
      _add(p);
      _search.clear();
      setState(() => _q = '');
    }
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(onCode: (code) async {
          final p = await ProductService.findByCode(code);
          if (p == null) return '${tr('No product with code')} $code';
          final w = pos.addProduct(p);
          return w ?? '${tr('Added')}: ${p.displayName}';
        }),
      ),
    );
  }

  Future<void> _customItem() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Quick item')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('Name'))),
          const SizedBox(height: 12),
          NumField(controller: price, label: 'Price'),
          const SizedBox(height: 12),
          NumField(controller: qty, label: 'Quantity'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add'))),
        ],
      ),
    );
    if (ok != true) return;
    final p = Fmt.parse(price.text);
    final q = Fmt.parse(qty.text);
    if (name.text.trim().isEmpty || p <= 0 || q <= 0) return;
    pos.addCustom(name.text.trim(), p, q);
  }

  Future<void> _pickVariant(Product parent) async {
    final vs = (await ProductService.variants(parent.id)).where((v) => v.active).toList();
    if (!mounted) return;
    if (vs.isEmpty) return showSnack(context, tr('This product has no variants yet.'), error: true);
    final v = await showModalBottomSheet<Product>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(parent.name, style: Theme.of(ctx).textTheme.titleLarge)),
          for (final v in vs)
            ListTile(
              title: Text(v.variantName ?? ''),
              subtitle: Text('${tr('Stock')}: ${Fmt.qty(v.stock)}'),
              trailing: Text(Fmt.money(v.salePrice), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    );
    if (v != null) _add(v);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = isWide(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Sell')),
        actions: [
          IconButton(tooltip: tr('Quick item'), icon: const Icon(Icons.add_box_outlined), onPressed: _customItem),
          if (app.hasModule(Mod.barcode))
            IconButton(tooltip: tr('Scan'), icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
        ],
      ),
      body: wide
          ? Row(children: [
              Expanded(child: _catalogue(app)),
              const VerticalDivider(width: 1),
              SizedBox(width: 400, child: CartPanel(embedded: true, onCheckout: () => _checkout(context))),
            ])
          : _catalogue(app),
      bottomNavigationBar: wide
          ? null
          : ListenableBuilder(
              listenable: pos,
              builder: (ctx, _) {
                final t = pos.totals;
                final count = t.itemsCount;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: FilledButton(
                      onPressed: pos.cart.isEmpty ? null : () => _openCart(context),
                      child: Row(children: [
                        Badge(label: Text(Fmt.qty(count)), child: const Icon(Icons.shopping_cart)),
                        const SizedBox(width: 16),
                        Expanded(child: Text(tr(pos.cart.isEmpty ? 'Cart is empty' : 'View cart'))),
                        Text(Fmt.money(t.total)),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openCart(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('Cart'))),
          body: CartPanel(onCheckout: () => _checkout(context)),
        ),
      ),
    );
  }

  Future<void> _checkout(BuildContext context) async {
    if (pos.cart.isEmpty) return;
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  Widget _catalogue(AppState app) {
    final cols = (MediaQuery.sizeOf(context).width / (isWide(context) ? 190 : 150)).floor().clamp(2, 6).toInt();
    return Column(children: [
      SearchField(
        controller: _search,
        hint: app.hasModule(Mod.barcode) ? 'Search name, SKU or barcode' : 'Search products',
        onChanged: (v) => setState(() => _q = v),
        // Hardware barcode scanners type the code and press Enter.
        onSubmitted: _submitSearch,
        trailing: _q.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  setState(() => _q = '');
                },
              ),
      ),
      SizedBox(
        height: 48,
        child: LiveData<List<Category>>(
          load: () => ProductService.categories('product'),
          builder: (ctx, cats) => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(tr('All')),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
                ),
            ],
          ),
        ),
      ),
      Expanded(
        child: LiveData<List<Product>>(
          deps: [_q, _categoryId],
          load: () => ProductService.catalogue(search: _q, categoryId: _categoryId).then(
                (list) => list.where((p) => p.active).toList(),
              ),
          builder: (ctx, list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.inventory_2_outlined,
                text: _q.isEmpty ? 'Add products to start selling, or use a quick item.' : 'No products found',
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _ProductCard(
                product: list[i],
                showStock: app.hasModule(Mod.inventory),
                onTap: () => list[i].hasVariants ? _pickVariant(list[i]) : _add(list[i]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap, required this.showStock});
  final Product product;
  final VoidCallback onTap;
  final bool showStock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = product;
    final out = p.trackStock && showStock && p.stock <= 0;
    return Card(
      color: cs.surfaceContainerHighest.withOpacity(0.45),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, c) => Center(
                  child: ProductThumb(image: p.image, name: p.name, size: c.maxHeight < c.maxWidth ? c.maxHeight : c.maxWidth),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              Expanded(
                child: Text(
                  p.hasVariants ? tr('Options') : Fmt.money(p.salePrice),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showStock && p.trackStock)
                Text(
                  Fmt.qty(p.stock),
                  style: TextStyle(fontSize: 12, color: out ? cs.error : (p.isLow ? Colors.orange.shade800 : cs.onSurfaceVariant)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Cart list with totals and checkout button. Used beside the catalogue on
/// tablets and as its own page on phones.
class CartPanel extends StatelessWidget {
  const CartPanel({super.key, required this.onCheckout, this.embedded = false});
  final VoidCallback onCheckout;
  final bool embedded;

  Future<void> _editLine(BuildContext context, CartLine l) async {
    final app = AppState.instance;
    final pos = PosController.instance;
    final qty = TextEditingController(text: Fmt.qty(l.qty));
    final price = TextEditingController(text: Fmt.qty(l.unitPrice));
    final disc = TextEditingController(text: numText(l.discount));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            NumField(controller: qty, label: 'Quantity', autofocus: true),
            const SizedBox(height: 12),
            NumField(controller: price, label: 'Price', enabled: app.can(Perm.editPrice)),
            const SizedBox(height: 12),
            NumField(controller: disc, label: 'Discount (amount)', enabled: app.can(Perm.discount)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: Text(tr('Remove'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Save'))),
        ],
      ),
    );
    if (res == 'remove') {
      pos.remove(l);
    } else if (res == 'save') {
      final q = Fmt.parse(qty.text);
      if (q <= 0) {
        pos.remove(l);
        return;
      }
      l.qty = q;
      if (app.can(Perm.editPrice)) l.unitPrice = Fmt.parse(price.text);
      if (app.can(Perm.discount)) l.discount = Fmt.parse(disc.text);
      pos.changed();
    }
  }

  Future<void> _cartDiscount(BuildContext context) async {
    final pos = PosController.instance;
    final c = TextEditingController(text: numText(pos.cart.cartDiscount));
    var percent = pos.cart.cartDiscountPercent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('Cart discount')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('Amount'))),
                const ButtonSegment(value: true, label: Text('%')),
              ],
              selected: {percent},
              onSelectionChanged: (s) => setS(() => percent = s.first),
            ),
            const SizedBox(height: 12),
            NumField(controller: c, label: percent ? 'Percent' : 'Amount', autofocus: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Apply'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    pos.cart.cartDiscount = Fmt.parse(c.text);
    pos.cart.cartDiscountPercent = percent;
    pos.changed();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pos = PosController.instance;
    return ListenableBuilder(
      listenable: pos,
      builder: (context, _) {
        final t = pos.totals;
        final cart = pos.cart;
        return Column(children: [
          if (app.hasModule(Mod.customers))
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(cart.customerName ?? tr('Walk-in customer')),
              subtitle: cart.exchangeCredit > 0 ? Text('${tr('Exchange credit')}: ${Fmt.money(cart.exchangeCredit)}') : null,
              trailing: cart.customerId == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => pos.setCustomer(null)),
              onTap: () async {
                final p = await pickParty(context, 'customer');
                if (p != null) pos.setCustomer(p);
              },
            ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? const EmptyState(icon: Icons.shopping_cart_outlined, text: 'Cart is empty')
                : ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = t.lines[i];
                      final l = c.line;
                      return ListTile(
                        onTap: () => _editLine(context, l),
                        title: Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          '${Fmt.money(l.unitPrice)}${l.unit == null ? '' : ' / ${l.unit}'}',
                          if (c.discount > 0.0001) '-${Fmt.money(c.discount)}',
                          if (c.tax > 0.0001) '${tr('Tax')} ${Fmt.percent(l.taxRate)}',
                        ].join('  ·  ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => pos.changeQty(l, -1),
                          ),
                          Text(Fmt.qty(l.qty), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => pos.changeQty(l, 1),
                          ),
                          SizedBox(
                            width: 84,
                            child: Text(Fmt.money(c.total),
                                textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
          Material(
            elevation: 6,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  KeyValue('Subtotal', Fmt.money(t.subtotal)),
                  InkWell(
                    onTap: app.can(Perm.discount) && !cart.isEmpty ? () => _cartDiscount(context) : null,
                    child: KeyValue(
                      app.can(Perm.discount) ? 'Discount (tap to change)' : 'Discount',
                      t.discount > 0 ? '-${Fmt.money(t.discount)}' : Fmt.money(0),
                    ),
                  ),
                  if (app.taxEnabled) KeyValue(app.taxInclusive ? 'Tax (included)' : 'Tax', Fmt.money(t.tax)),
                  const Divider(),
                  KeyValue('Total', Fmt.money(t.total), bold: true),
                  const SizedBox(height: 10),
                  Row(children: [
                    OutlinedButton(
                      onPressed: cart.isEmpty && cart.customerId == null
                          ? null
                          : () async {
                              if (await confirm(context, 'Clear cart', 'Remove all items from the cart?')) pos.clear();
                            },
                      child: const Icon(Icons.delete_sweep_outlined),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: cart.isEmpty ? null : onCheckout,
                        child: Text('${tr('Charge')}  ${Fmt.money(t.total)}'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
