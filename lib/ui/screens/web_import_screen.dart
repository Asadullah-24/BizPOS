import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/cloud_service.dart';
import '../../services/store_service.dart';
import '../../services/web_import_service.dart';
import '../tokens.dart';

/// Brings products, prices, photos and descriptions from the shop's own
/// WooCommerce or Shopify website into BizPOS.
class WebImportScreen extends StatefulWidget {
  const WebImportScreen({super.key});

  @override
  State<WebImportScreen> createState() => _WebImportScreenState();
}

class _WebImportScreenState extends State<WebImportScreen> {
  final _site = TextEditingController(text: Local.prefs.getString(Local.k('import_site')) ?? '');
  List<WebProduct>? _items;
  final _picked = <String>{};
  bool _loading = false;
  bool _importing = false;
  int _found = 0;
  int _done = 0;
  String _current = '';
  bool _publish = true;
  bool _updatePrices = true;
  String? _error;

  @override
  void dispose() {
    _site.dispose();
    super.dispose();
  }

  bool get _canPublish => CloudService.instance.signedIn && StoreService.instance.myAllowance != null;

  Future<void> _load() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _items = null;
      _found = 0;
    });
    try {
      final list = await WebImportService.fetch(_site.text, onProgress: (n) {
        if (mounted) setState(() => _found = n);
      });
      await Local.prefs.setString(Local.k('import_site'), _site.text.trim());
      setState(() {
        _items = list;
        _picked
          ..clear()
          ..addAll(list.map((e) => e.sourceId));
      });
    } catch (e) {
      setState(() => _error = e is StateError ? e.message : '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _import() async {
    final list = _items!.where((e) => _picked.contains(e.sourceId)).toList();
    if (list.isEmpty) return;
    setState(() {
      _importing = true;
      _done = 0;
    });
    final res = await WebImportService.run(
      list,
      updatePrices: _updatePrices,
      publish: _publish && _canPublish,
      onProgress: (d, n) {
        if (mounted) setState(() {
          _done = d;
          _current = n;
        });
      },
    );
    if (!mounted) return;
    setState(() => _importing = false);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: Tw.emerald500, size: 40),
        title: Text(tr('Import finished')),
        content: Text([
          '${res.added} ${tr('products added')}',
          '${res.updated} ${tr('products updated')}',
          if (_publish && _canPublish) '${res.online} ${tr('shown on your online store')}',
          if (res.failed > 0) '${res.failed} ${tr('could not be imported')}',
          if (res.limitReached) tr('Your plan product limit was reached. Upgrade to add the rest.'),
          if (res.onlineLimitReached) tr('Your online product limit was reached. Ask BizPOS support for more.'),
          tr('Add stock and cost prices in Products when you are ready.'),
        ].join('\n')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done')))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return PopScope(
      canPop: !_importing,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Import from my website'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
          Text(tr('Bring products, prices, photos and descriptions from your own WooCommerce (WordPress) or Shopify website.'),
              style: muted),
          const SizedBox(height: 12),
          TextField(
            controller: _site,
            enabled: !_loading && !_importing,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: tr('Website address'),
              hintText: 'yourshop.com',
              prefixIcon: const Icon(Icons.language_rounded),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading || _importing ? null : _load,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded),
            label: Text(_loading ? '${tr('Reading products')}… $_found' : tr('Load products')),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Tw.rose500)),
            ),
          if (items != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                SwitchListTile(
                  title: Text(tr('Show on my online store with photos')),
                  subtitle: Text(_canPublish
                      ? tr('Up to 4 photos and the description for each product.')
                      : tr('Needs a BizPOS account with the online store.')),
                  value: _publish && _canPublish,
                  onChanged: _canPublish && !_importing ? (v) => setState(() => _publish = v) : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(tr('Update prices of products already in BizPOS')),
                  value: _updatePrices,
                  onChanged: _importing ? null : (v) => setState(() => _updatePrices = v),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('${items.length} ${tr('products found')} · ${_picked.length} ${tr('selected')}', style: theme.textTheme.titleSmall)),
              TextButton(
                onPressed: _importing
                    ? null
                    : () => setState(() => _picked.length == items.length
                        ? _picked.clear()
                        : _picked.addAll(items.map((e) => e.sourceId))),
                child: Text(tr(_picked.length == items.length ? 'Select none' : 'Select all')),
              ),
            ]),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  CheckboxListTile(
                    value: _picked.contains(items[i].sourceId),
                    onChanged: _importing
                        ? null
                        : (v) => setState(() => v == true ? _picked.add(items[i].sourceId) : _picked.remove(items[i].sourceId)),
                    secondary: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: items[i].images.isEmpty
                            ? Container(color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.image_outlined))
                            : Image.network(items[i].images.first, fit: BoxFit.cover, cacheWidth: 120,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    title: Text(items[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      Fmt.money(items[i].price),
                      if (items[i].category != null) items[i].category!,
                      if (!items[i].inStock) tr('Out of stock'),
                      '${items[i].images.length} ${tr('photos')}',
                    ].join(' · ')),
                  ),
                ],
              ]),
            ),
          ],
        ]),
        bottomNavigationBar: items == null || items.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_importing) ...[
                      LinearProgressIndicator(value: _picked.isEmpty ? null : _done / _picked.length),
                      const SizedBox(height: 6),
                      Text('$_done / ${_picked.length}  $_current', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                      const SizedBox(height: 6),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _importing || _picked.isEmpty ? null : _import,
                        child: Text(_importing ? tr('Importing… keep the app open') : '${tr('Import')} ${_picked.length} ${tr('products')}'),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}
