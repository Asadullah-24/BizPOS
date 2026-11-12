import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/product_service.dart';
import '../common.dart';
import 'categories_screen.dart';
import 'product_form.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Products')), actions: [
        IconButton(
          tooltip: tr('Categories'),
          icon: const Icon(Icons.category_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen(kind: 'product'))),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr('Add product')),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm())),
      ),
      body: Column(children: [
        SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Search name, SKU or barcode'),
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
                  child: ChoiceChip(label: Text(tr('All')), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                ),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(c.name), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LiveData<List<Product>>(
            deps: [_q, _cat],
            load: () => ProductService.catalogue(search: _q, categoryId: _cat),
            builder: (ctx, list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  text: 'No products yet',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm())),
                    icon: const Icon(Icons.add),
                    label: Text(tr('Add product')),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final showStock = app.hasModule(Mod.inventory) && p.trackStock;
                  return ListTile(
                    leading: ProductThumb(image: p.image, name: p.name),
                    title: Text(p.name, style: TextStyle(color: p.active ? null : Theme.of(context).disabledColor)),
                    subtitle: Text([
                      if (p.hasVariants) tr('Has variants'),
                      if (p.sku != null && p.sku!.isNotEmpty) p.sku!,
                      if (!p.active) tr('Inactive'),
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(p.hasVariants ? '' : Fmt.money(p.salePrice), style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (showStock)
                          Text(
                            '${Fmt.qty(p.stock)} ${p.unit ?? ''}',
                            style: TextStyle(fontSize: 12, color: p.stock <= p.lowStock ? Colors.red : null),
                          ),
                      ],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(productId: p.id))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
