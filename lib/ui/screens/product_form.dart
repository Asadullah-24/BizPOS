import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/ids.dart';
import '../../models/models.dart';
import '../../services/product_service.dart';
import '../../services/store_service.dart';
import '../brand.dart';
import '../common.dart';
import 'inventory_screen.dart';
import 'scanner_screen.dart';

class _VariantRow {
  _VariantRow({this.id, String name = '', String sku = '', String barcode = '', double price = 0, double cost = 0, this.stock = 0})
      : name = TextEditingController(text: name),
        sku = TextEditingController(text: sku),
        barcode = TextEditingController(text: barcode),
        price = TextEditingController(text: numText(price)),
        cost = TextEditingController(text: numText(cost)),
        opening = TextEditingController();
  final String? id;
  final double stock;
  final TextEditingController name, sku, barcode, price, cost, opening;
}

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, this.productId, this.initialBarcode});
  final String? productId;

  /// Prefills the barcode when a product is created from an unknown scan.
  final String? initialBarcode;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  bool _loading = true;
  Product? _existing;
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _tax = TextEditingController();
  final _opening = TextEditingController();
  final _low = TextEditingController();
  final _unit = TextEditingController();
  final Map<String, TextEditingController> _attrs = {};
  String? _categoryId;
  String? _image;
  List<String> _more = [];
  final Map<String, String> _hidden = {};
  bool _track = true;
  bool _active = true;
  bool _hasVariants = false;
  final List<_VariantRow> _variants = [];
  final List<String> _removed = [];
  List<Category> _cats = [];
  bool _saving = false;

  bool get _isNew => _existing == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppState.instance;
    _cats = await ProductService.categories('product');
    final fields = app.businessType?.fields ?? [];
    if (widget.productId != null) {
      final p = await ProductService.byId(widget.productId!);
      _existing = p;
      if (p != null) {
        _name.text = p.name;
        _sku.text = p.sku ?? '';
        _barcode.text = p.barcode ?? '';
        _cost.text = numText(p.costPrice);
        _price.text = numText(p.salePrice);
        _tax.text = p.taxRate == null ? '' : Fmt.qty(p.taxRate!);
        _low.text = numText(p.lowStock);
        _unit.text = p.unit ?? '';
        _categoryId = p.categoryId;
        _image = p.image;
        _more = p.moreImages;
        _track = p.trackStock;
        _active = p.active;
        _hasVariants = p.hasVariants;
        for (final e in p.attrs.entries) {
          if (e.key.startsWith('_')) _hidden[e.key] = e.value;
        }
        for (final f in {...fields, ...p.attrs.keys.where((k) => !k.startsWith('_'))}) {
          _attrs[f] = TextEditingController(text: p.attrs[f] ?? '');
        }
        if (p.hasVariants) {
          for (final v in await ProductService.variants(p.id)) {
            _variants.add(_VariantRow(
              id: v.id,
              name: v.variantName ?? '',
              sku: v.sku ?? '',
              barcode: v.barcode ?? '',
              price: v.salePrice,
              cost: v.costPrice,
              stock: v.stock,
            ));
          }
        }
      }
    } else {
      _sku.text = await ProductService.nextSku();
      _barcode.text = widget.initialBarcode ?? '';
      _unit.text = app.businessType?.units.firstOrNull ?? 'pcs';
      _track = app.hasModule(Mod.inventory);
      for (final f in fields) {
        _attrs[f] = TextEditingController();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _maxPhotos = 4;
  List<String> get _photos => [if (_image != null) _image!, ..._more];

  void _setPhotos(List<String> l) {
    _image = l.isEmpty ? null : l.first;
    _more = l.length > 1 ? l.sublist(1) : [];
  }

  /// Adds photos from the camera or gallery (several at once from the gallery).
  Future<void> _addPhotos() async {
    final left = _maxPhotos - _photos.length;
    if (left <= 0) return showSnack(context, tr('Up to 4 photos per product.'));
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: Text(tr('Camera')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(tr('Gallery')),
            subtitle: Text('${tr('Pick up to')} $left'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return;
    final picker = ImagePicker();
    // High resolution and quality: the app makes its own smaller copies for the website.
    final files = src == ImageSource.camera
        ? [if (await picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 90) case final x?) x]
        : left == 1
            ? [if (await picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 90) case final x?) x]
            : await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 90, limit: left);
    if (files.isEmpty) return;
    final names = <String>[for (final x in files.take(left)) await ImageStore.save(File(x.path))];
    if (mounted) setState(() => _setPhotos([..._photos, ...names]));
  }

  Future<void> _photoMenu(int i) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          if (i > 0)
            ListTile(leading: const Icon(Icons.star_rounded), title: Text(tr('Make main photo')), onTap: () => Navigator.pop(ctx, 'main')),
          ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('Remove photo')), onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (action == null) return;
    final l = [..._photos];
    final name = l.removeAt(i);
    if (action == 'main') l.insert(0, name);
    setState(() => _setPhotos(l));
  }

  Widget _photoStrip() {
    final photos = _photos;
    Widget tile(int i) => InkWell(
          onTap: () => _photoMenu(i),
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: [
            ProductThumb(image: photos[i], name: _name.text, size: i == 0 ? 110 : 72),
            if (i == 0 && photos.length > 1)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Text(tr('Main'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: [
        if (photos.isEmpty)
          InkWell(
            onTap: _addPhotos,
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              ProductThumb(image: null, name: _name.text, size: 110),
              const Positioned(right: 4, bottom: 4, child: CircleAvatar(radius: 16, child: Icon(Icons.photo_camera, size: 18))),
            ]),
          ),
        for (var i = 0; i < photos.length; i++) tile(i),
        if (photos.isNotEmpty && photos.length < _maxPhotos)
          SizedBox(
            width: 72,
            height: 72,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: _addPhotos,
              child: const Icon(Icons.add_photo_alternate_rounded),
            ),
          ),
      ],
    );
  }

  Future<void> _scanInto(TextEditingController c) async {
    final code = await ScannerScreen.scan(context);
    if (code != null) setState(() => c.text = code);
  }

  Future<void> _addCategory() async {
    final name = await promptText(context, 'New category', label: 'Name');
    if (name == null || name.trim().isEmpty) return;
    final id = await ProductService.addCategory(name, 'product');
    _cats = await ProductService.categories('product');
    setState(() => _categoryId = id);
  }

  Future<void> _addField() async {
    final name = await promptText(context, 'New field', label: 'Field name (e.g. Color)');
    if (name == null || name.trim().isEmpty) return;
    setState(() => _attrs[name.trim()] = TextEditingController());
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, tr('Enter the product name.'), error: true);
    final ids = <String>{if (_existing != null) _existing!.id, for (final v in _variants) if (v.id != null) v.id!};
    for (final pair in [('sku', _sku.text), ('barcode', _barcode.text)]) {
      if (await ProductService.codeInUse(pair.$1, pair.$2, exceptIds: ids)) {
        if (mounted) showSnack(context, '${tr(pair.$1 == 'sku' ? 'SKU' : 'Barcode')} ${pair.$2} ${tr('is already used by another product.')}', error: true);
        return;
      }
    }
    if (_hasVariants && _variants.where((v) => v.name.text.trim().isNotEmpty).isEmpty) {
      if (mounted) showSnack(context, tr('Add at least one variant, or turn variants off.'), error: true);
      return;
    }
    setState(() => _saving = true);
    final p = Product(
      id: _existing?.id ?? newId(),
      name: _name.text.trim(),
      sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      categoryId: _categoryId,
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      costPrice: Fmt.parse(_cost.text),
      salePrice: Fmt.parse(_price.text),
      taxRate: _tax.text.trim().isEmpty ? null : Fmt.parse(_tax.text),
      trackStock: _track,
      lowStock: Fmt.parse(_low.text),
      image: _image,
      attrs: {
        ..._hidden..remove('_more_images'),
        for (final e in _attrs.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        if (_more.isNotEmpty) '_more_images': _more.join('|'),
      },
      hasVariants: _hasVariants,
      active: _active,
    );
    if (_isNew) {
      try {
        await ProductService.checkLimit();
      } on ProductLimitError catch (e) {
        if (mounted) await showProductLimit(context, e.limit);
        return;
      }
    }
    if (!mounted) return;
    final ok = await guard(context, () async {
      await ProductService.save(
        p,
        isNew: _isNew,
        openingStock: Fmt.parse(_opening.text),
        variants: _hasVariants
            ? [
                for (final v in _variants)
                  if (v.name.text.trim().isNotEmpty)
                    VariantInput(
                      id: v.id,
                      name: v.name.text.trim(),
                      sku: v.sku.text.trim().isEmpty ? null : v.sku.text.trim(),
                      barcode: v.barcode.text.trim().isEmpty ? null : v.barcode.text.trim(),
                      price: v.price.text.trim().isEmpty ? p.salePrice : Fmt.parse(v.price.text),
                      cost: v.cost.text.trim().isEmpty ? p.costPrice : Fmt.parse(v.cost.text),
                      openingStock: Fmt.parse(v.opening.text),
                    ),
              ]
            : null,
        removedVariantIds: _removed,
      );
    }, success: 'Saved');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      StoreService.instance.productChanged(p.id);
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete product', 'Delete ${_existing!.name}? Past sales keep their records.', danger: true)) return;
    await ProductService.delete(_existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final units = {...?app.businessType?.units, if (_unit.text.isNotEmpty) _unit.text}.toList();
    final inv = app.hasModule(Mod.inventory);
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(_isNew ? 'Add product' : 'Edit product')),
        actions: [if (!_isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: _photoStrip()),
              if (_photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_photos.length}/$_maxPhotos ${tr('photos')} · ${tr('tap a photo to make it main or remove it')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              gap,
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('Product name')), onChanged: (_) => setState(() {})),
              gap,
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Category')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(tr('None'))),
                      for (final c in _cats) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                IconButton(tooltip: tr('New category'), icon: const Icon(Icons.add), onPressed: _addCategory),
              ]),
              gap,
              TextField(
                controller: _unit,
                decoration: InputDecoration(
                  labelText: tr('Unit (pcs, kg, ltr...)'),
                  suffixIcon: units.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (v) => setState(() => _unit.text = v),
                          itemBuilder: (_) => [for (final u in units) PopupMenuItem(value: u, child: Text(u))],
                        ),
                ),
              ),
              gap,
              Row(children: [
                Expanded(child: TextField(controller: _sku, decoration: InputDecoration(labelText: tr('SKU')))),
                if (app.hasModule(Mod.barcode)) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _barcode,
                      decoration: InputDecoration(
                        labelText: tr('Barcode'),
                        suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scanInto(_barcode)),
                      ),
                    ),
                  ),
                ],
              ]),
              gap,
              Row(children: [
                Expanded(child: NumField(controller: _cost, label: 'Cost price')),
                const SizedBox(width: 12),
                Expanded(child: NumField(controller: _price, label: 'Sale price')),
              ]),
              if (app.taxEnabled) ...[
                gap,
                NumField(controller: _tax, label: 'Tax % (empty = default ${Fmt.qty(app.defaultTaxRate)}%)'),
              ],
              if (inv) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Track stock')),
                  value: _track,
                  onChanged: (v) => setState(() => _track = v),
                ),
                if (_track) ...[
                  Row(children: [
                    if (_isNew && !_hasVariants) ...[
                      Expanded(child: NumField(controller: _opening, label: 'Opening stock')),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: NumField(controller: _low, label: 'Low stock alert at')),
                  ]),
                  if (!_isNew && !_hasVariants) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.tune),
                      label: Text('${tr('Adjust stock')} (${Fmt.qty(_existing!.stock)})'),
                      onPressed: () async {
                        await showAdjustStock(context, _existing!);
                        final fresh = await ProductService.byId(_existing!.id);
                        if (fresh != null && mounted) setState(() => _existing!.stock = fresh.stock);
                      },
                    ),
                  ],
                ],
              ],
              ...[
                SectionTitle('Details', trailing: TextButton.icon(onPressed: _addField, icon: const Icon(Icons.add), label: Text(tr('Field')))),
                for (final e in _attrs.entries) ...[
                  TextField(controller: e.value, decoration: InputDecoration(labelText: e.key)),
                  gap,
                ],
              ],
              if (app.hasModule(Mod.variants))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('This product has variants')),
                  subtitle: Text(tr('Sizes, colors, flavours... each with its own price and stock')),
                  value: _hasVariants,
                  onChanged: !_isNew && _existing!.hasVariants ? null : (v) => setState(() => _hasVariants = v),
                ),
              if (_hasVariants) ...[
                for (var i = 0; i < _variants.length; i++) _variantCard(i),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _variants.add(_VariantRow())),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add variant')),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Active (show at POS)')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Save'))),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _variantCard(int i) {
    final v = _variants[i];
    final app = AppState.instance;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(controller: v.name, decoration: InputDecoration(labelText: tr('Variant (e.g. Red / L)'))),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                if (v.id != null) _removed.add(v.id!);
                _variants.removeAt(i);
              }),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: NumField(controller: v.price, label: 'Price')),
            const SizedBox(width: 8),
            Expanded(child: NumField(controller: v.cost, label: 'Cost')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: v.sku, decoration: InputDecoration(labelText: tr('SKU')))),
            if (app.hasModule(Mod.barcode)) ...[
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: v.barcode,
                  decoration: InputDecoration(
                    labelText: tr('Barcode'),
                    suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => _scanInto(v.barcode)),
                  ),
                ),
              ),
            ],
          ]),
          if (_track && app.hasModule(Mod.inventory)) ...[
            const SizedBox(height: 8),
            if (v.id == null)
              NumField(controller: v.opening, label: 'Opening stock')
            else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('${tr('Stock')}: ${Fmt.qty(v.stock)}  ·  ${tr('Adjust from Inventory')}'),
              ),
          ],
        ]),
      ),
    );
  }
}
