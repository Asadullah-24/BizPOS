import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/db.dart';
import '../core/ids.dart';
import '../models/models.dart';
import 'cloud_service.dart';
import 'product_service.dart';
import 'store_service.dart';

/// A product read from the shop's own website.
class WebProduct {
  WebProduct({
    required this.sourceId,
    required this.name,
    required this.price,
    this.regularPrice,
    this.sku,
    this.category,
    this.description = '',
    this.images = const [],
    this.inStock = true,
    this.url,
  });

  final String sourceId;
  final String name;
  final double price;
  final double? regularPrice;
  final String? sku;
  final String? category;
  final String description;
  final List<String> images;
  final bool inStock;
  final String? url;
}

class ImportResult {
  int added = 0;
  int updated = 0;
  int online = 0;
  int failed = 0;
  bool limitReached = false;
  bool onlineLimitReached = false;
}

/// Imports products from the shop's own WooCommerce (WordPress) or Shopify
/// website, using the public product feed the website already shows to visitors.
class WebImportService {
  static const _timeout = Duration(seconds: 25);
  static const _headers = {'Accept': 'application/json', 'User-Agent': 'BizPOS/1.0 (product import)'};

  /// "tajoree.com" → "https://tajoree.com"
  static String normalise(String site) {
    var s = site.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http')) s = 'https://$s';
    final u = Uri.parse(s);
    return '${u.scheme}://${u.host}${u.hasPort && u.port != 443 && u.port != 80 ? ':${u.port}' : ''}';
  }

  static Future<List<WebProduct>> fetch(String site, {void Function(int found)? onProgress}) async {
    final base = normalise(site);
    if (base.isEmpty) throw StateError('Type your website address.');
    try {
      final woo = await _woo(base, onProgress);
      if (woo != null && woo.isNotEmpty) return woo;
      final shopify = await _shopify(base, onProgress);
      if (shopify != null && shopify.isNotEmpty) return shopify;
    } on SocketException {
      throw StateError('Could not reach $base. Check the address and your internet.');
    } on TimeoutException {
      throw StateError('$base is taking too long to answer. Try again.');
    } on http.ClientException {
      throw StateError('Could not reach $base. Check the address and your internet.');
    }
    throw StateError('No products found. BizPOS can read WooCommerce (WordPress) and Shopify stores.');
  }

  // ------------------------------------------------------------ WooCommerce

  static Future<List<WebProduct>?> _woo(String base, void Function(int)? onProgress) async {
    final out = <WebProduct>[];
    for (var page = 1; page <= 50; page++) {
      final r = await http
          .get(Uri.parse('$base/wp-json/wc/store/v1/products?per_page=100&page=$page'), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode == 400 && page > 1) break; // past the last page
      if (r.statusCode != 200) return page == 1 ? null : out;
      final data = _json(r.body);
      if (data is! List) return page == 1 ? null : out;
      if (data.isEmpty) break;
      for (final m in data.whereType<Map>()) {
        final prices = (m['prices'] as Map?) ?? {};
        final minor = int.tryParse('${prices['currency_minor_unit'] ?? 2}') ?? 2;
        double? money(Object? v) {
          final n = double.tryParse('${v ?? ''}');
          return n == null ? null : n / pow(10, minor);
        }

        final price = money(prices['price']) ?? 0;
        final regular = money(prices['regular_price']);
        final cats = ((m['categories'] as List?) ?? []).whereType<Map>().map((c) => _text('${c['name']}')).toList();
        out.add(WebProduct(
          sourceId: 'woo:${m['id']}',
          name: _text('${m['name'] ?? ''}'),
          price: price,
          regularPrice: regular != null && regular > price ? regular : null,
          sku: '${m['sku'] ?? ''}'.trim().isEmpty ? null : '${m['sku']}'.trim(),
          category: cats.isEmpty ? null : cats.first,
          description: _text('${(m['short_description'] ?? '').toString().trim().isNotEmpty ? m['short_description'] : m['description'] ?? ''}'),
          images: ((m['images'] as List?) ?? []).whereType<Map>().map((i) => '${i['src'] ?? ''}').where((s) => s.isNotEmpty).toList(),
          inStock: m['is_in_stock'] != false,
          url: m['permalink'] as String?,
        ));
      }
      onProgress?.call(out.length);
      final pages = int.tryParse(r.headers['x-wp-totalpages'] ?? '');
      if (data.length < 100 || (pages != null && page >= pages)) break;
    }
    return out;
  }

  // --------------------------------------------------------------- Shopify

  static Future<List<WebProduct>?> _shopify(String base, void Function(int)? onProgress) async {
    final out = <WebProduct>[];
    for (var page = 1; page <= 40; page++) {
      final r = await http.get(Uri.parse('$base/products.json?limit=250&page=$page'), headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) return page == 1 ? null : out;
      final data = _json(r.body);
      final list = data is Map ? data['products'] : null;
      if (list is! List) return page == 1 ? null : out;
      if (list.isEmpty) break;
      for (final m in list.whereType<Map>()) {
        final variants = ((m['variants'] as List?) ?? []).whereType<Map>().toList();
        final v = variants.isEmpty ? const {} : variants.first;
        final price = double.tryParse('${v['price'] ?? 0}') ?? 0;
        final compare = double.tryParse('${v['compare_at_price'] ?? ''}');
        out.add(WebProduct(
          sourceId: 'shopify:${m['id']}',
          name: _text('${m['title'] ?? ''}'),
          price: price,
          regularPrice: compare != null && compare > price ? compare : null,
          sku: '${v['sku'] ?? ''}'.trim().isEmpty ? null : '${v['sku']}'.trim(),
          category: '${m['product_type'] ?? ''}'.trim().isEmpty ? null : '${m['product_type']}'.trim(),
          description: _text('${m['body_html'] ?? ''}'),
          images: ((m['images'] as List?) ?? []).whereType<Map>().map((i) => '${i['src'] ?? ''}').where((s) => s.isNotEmpty).toList(),
          inStock: variants.any((x) => x['available'] != false),
          url: '$base/products/${m['handle']}',
        ));
      }
      onProgress?.call(out.length);
      if (list.length < 250) break;
    }
    return out;
  }

  static Object? _json(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Plain text from HTML: tags removed, common entities decoded, trimmed to 500 characters.
  static String _text(String html) {
    var s = html
        .replaceAll(RegExp(r'<\s*(br|/p|/li|/h\d)\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#8217;', "'")
        .replaceAll('&#8211;', '-')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n')
        .trim();
    if (s.length > 500) s = '${s.substring(0, 497)}...';
    return s;
  }

  // ---------------------------------------------------------------- import

  static Future<Uint8List?> _download(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': _headers['User-Agent']!}).timeout(_timeout);
      if (r.statusCode != 200 || r.bodyBytes.length < 100) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Adds new products and updates ones imported before (matched by website id,
  /// then SKU, then exact name). Optionally shows them on the online store with photos.
  static Future<ImportResult> run(
    List<WebProduct> items, {
    required bool updatePrices,
    required bool publish,
    void Function(int done, String name)? onProgress,
  }) async {
    final res = ImportResult();
    final rows = await Db.instance.s.q('SELECT id, name, sku, attrs FROM products WHERE deleted_at IS NULL AND parent_id IS NULL');
    final bySource = <String, String>{};
    final bySku = <String, String>{};
    final byName = <String, String>{};
    for (final r in rows) {
      final id = r['id'] as String;
      try {
        final a = jsonDecode('${r['attrs'] ?? '{}'}');
        final w = a is Map ? (a['_web_id'] ?? a['web_id']) : null;
        if (w != null) bySource['$w'] = id;
      } catch (_) {}
      if ('${r['sku'] ?? ''}'.isNotEmpty) bySku['${r['sku']}'.toLowerCase()] = id;
      byName['${r['name']}'.toLowerCase()] = id;
    }
    final cats = {for (final c in await ProductService.categories('product')) c.name.toLowerCase(): c.id};

    var onlineCount = 0;
    final store = StoreService.instance;
    final shopId = CloudService.instance.shopId;
    if (publish && shopId != null) {
      onlineCount = (await FirebaseFirestore.instance.collection('storefronts/$shopId/items').count().get()).count ?? 0;
    }

    for (var i = 0; i < items.length; i++) {
      final w = items[i];
      onProgress?.call(i, w.name);
      try {
        final existingId = bySource[w.sourceId] ?? (w.sku == null ? null : bySku[w.sku!.toLowerCase()]) ?? byName[w.name.toLowerCase()];
        String? categoryId;
        if (w.category != null && w.category!.isNotEmpty) {
          categoryId = cats[w.category!.toLowerCase()] ??= await ProductService.addCategory(w.category!, 'product');
        }
        Product prod;
        if (existingId != null) {
          final old = await ProductService.byId(existingId);
          if (old == null) continue;
          prod = old;
          if (updatePrices) prod.salePrice = w.price;
          prod.attrs.remove('web_id');
          prod.attrs['_web_id'] = w.sourceId;
          if (!w.inStock && prod.trackStock == false) {
            prod.trackStock = true;
          }
          prod.categoryId ??= categoryId;
          if (prod.allImages.isEmpty && w.images.isNotEmpty) await _savePhotos(prod, w.images);
          await ProductService.save(prod, isNew: false);
          res.updated++;
        } else {
          prod = Product(
            id: newId(),
            name: w.name,
            sku: w.sku,
            categoryId: categoryId,
            salePrice: w.price,
            // Stock counts are not on the website: in-stock items are sold without
            // counting until the shop adds stock; out-of-stock items show as such.
            trackStock: !w.inStock,
            attrs: {'_web_id': w.sourceId},
          );
          if (w.images.isNotEmpty) await _savePhotos(prod, w.images);
          try {
            await ProductService.save(prod, isNew: true);
          } on ProductLimitError {
            res.limitReached = true;
            break;
          }
          res.added++;
        }

        if (publish && shopId != null) {
          final allowance = store.myAllowance;
          final already = (await FirebaseFirestore.instance.doc('storefronts/$shopId/items/${prod.id}').get()).exists;
          if (!already && allowance != null && allowance > 0 && onlineCount >= allowance) {
            res.onlineLimitReached = true;
          } else if (allowance != null) {
            if (!already) {
              await store.publish(prod, currentCount: onlineCount);
              onlineCount++;
            } else {
              await store.productChanged(prod.id);
            }
            final itemRef = FirebaseFirestore.instance.doc('storefronts/$shopId/items/${prod.id}');
            await itemRef.update({
              if (w.description.isNotEmpty) 'description': w.description,
              'oldPrice': w.regularPrice ?? FieldValue.delete(),
            });
            await store.syncPhotos(prod);
            res.online++;
          }
        } else if (existingId != null) {
          await store.productChanged(prod.id);
        }
      } catch (_) {
        res.failed++;
      }
    }
    onProgress?.call(items.length, '');
    Db.instance.notifyChanged();
    return res;
  }

  /// Saves up to 4 website photos with the product on this phone (1600px JPEG).
  static Future<void> _savePhotos(Product prod, List<String> urls) async {
    final names = <String>[];
    for (final url in urls.take(StoreService.maxPhotos)) {
      final bytes = await _download(url);
      if (bytes == null) continue;
      final jpg = await compute(_local, bytes);
      if (jpg == null) continue;
      final dir = await ImageStore.dir();
      final name = '${newId()}.jpg';
      await File(p.join(dir.path, name)).writeAsBytes(jpg);
      names.add(name);
    }
    if (names.isEmpty) return;
    prod.image = names.first;
    prod.moreImages = names.sublist(1);
  }
}

Uint8List? _local(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  final o = img.bakeOrientation(d);
  if (o.width <= 1600 && o.height <= 1600) return Uint8List.fromList(img.encodeJpg(o, quality: 90));
  final r = o.width >= o.height
      ? img.copyResize(o, width: 1600, interpolation: img.Interpolation.average)
      : img.copyResize(o, height: 1600, interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodeJpg(r, quality: 90));
}
