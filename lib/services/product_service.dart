import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/access.dart';
import '../core/app_state.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../models/models.dart';
import 'activity_log.dart';
import 'inventory_service.dart';

/// Product photos live as files in the app's documents folder; the database
/// keeps only the file name.
class ImageStore {
  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'images'));
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static Future<String> save(File source) async {
    final d = await dir();
    final ext = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final name = '${newId()}$ext';
    await source.copy(p.join(d.path, name));
    return name;
  }

  static Future<File?> file(String? name) async {
    if (name == null || name.isEmpty) return null;
    final f = File(p.join((await dir()).path, name));
    return await f.exists() ? f : null;
  }

  static Future<void> writeBytes(String name, List<int> bytes) async {
    final f = File(p.join((await dir()).path, name));
    await f.writeAsBytes(bytes, flush: true);
  }
}

class VariantInput {
  VariantInput({this.id, required this.name, this.sku, this.barcode, required this.price, required this.cost, this.openingStock = 0});
  String? id;
  String name;
  String? sku;
  String? barcode;
  double price;
  double cost;
  double openingStock;
}

class ProductService {
  /// Products that can go in the cart: active, and not a parent of variants.
  static Future<List<Product>> sellable({String search = '', String? categoryId}) async {
    final where = ['p.deleted_at IS NULL', 'p.active = 1', 'p.has_variants = 0'];
    final args = <Object?>[];
    _filters(where, args, search, categoryId, joinParent: true);
    final rows = await Db.instance.s.q(
      'SELECT p.* FROM products p LEFT JOIN products parent ON parent.id = p.parent_id '
      'WHERE ${where.join(' AND ')} ORDER BY p.name COLLATE NOCASE, p.variant_name COLLATE NOCASE LIMIT 500',
      args,
    );
    return rows.map(Product.fromRow).toList();
  }

  /// Top-level products for the catalogue (variants are shown inside their parent).
  static Future<List<Product>> catalogue({String search = '', String? categoryId, bool lowOnly = false}) async {
    final where = ['p.deleted_at IS NULL', 'p.parent_id IS NULL'];
    final args = <Object?>[];
    _filters(where, args, search, categoryId);
    if (lowOnly) where.add('p.track_stock = 1 AND p.has_variants = 0 AND p.stock <= p.low_stock');
    final rows = await Db.instance.s.q(
      'SELECT p.*, (SELECT COALESCE(SUM(v.stock), 0) FROM products v WHERE v.parent_id = p.id AND v.deleted_at IS NULL) AS variant_stock '
      'FROM products p WHERE ${where.join(' AND ')} ORDER BY p.name COLLATE NOCASE LIMIT 1000',
      args,
    );
    return rows.map((r) {
      final prod = Product.fromRow(r);
      if (prod.hasVariants) prod.stock = asDouble(r['variant_stock']);
      return prod;
    }).toList();
  }

  static void _filters(List<String> where, List<Object?> args, String search, String? categoryId,
      {bool joinParent = false}) {
    if (search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      if (joinParent) {
        where.add("(p.name LIKE ? OR IFNULL(p.sku,'') LIKE ? OR IFNULL(p.barcode,'') LIKE ? OR IFNULL(p.variant_name,'') LIKE ?)");
        args.addAll([like, like, like, like]);
      } else {
        where.add("(p.name LIKE ? OR IFNULL(p.sku,'') LIKE ? OR IFNULL(p.barcode,'') LIKE ?)");
        args.addAll([like, like, like]);
      }
    }
    if (categoryId != null) {
      where.add('p.category_id = ?');
      args.add(categoryId);
    }
  }

  /// Sellable items whose stock is at or below their alert level.
  static Future<List<Product>> lowStock({int limit = 100}) async {
    final rows = await Db.instance.s.q(
      'SELECT * FROM products WHERE deleted_at IS NULL AND active = 1 AND has_variants = 0 '
      'AND track_stock = 1 AND stock <= low_stock ORDER BY stock LIMIT $limit',
    );
    return rows.map(Product.fromRow).toList();
  }

  static Future<Product?> byId(String id) async {
    final r = await Db.instance.s.byId('products', id);
    return r == null ? null : Product.fromRow(r);
  }

  static Future<List<Product>> variants(String parentId) async {
    final rows = await Db.instance.s.q(
      'SELECT * FROM products WHERE parent_id = ? AND deleted_at IS NULL ORDER BY variant_name COLLATE NOCASE',
      [parentId],
    );
    return rows.map(Product.fromRow).toList();
  }

  static Future<Product?> findByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final r = await Db.instance.s.one(
      'SELECT * FROM products WHERE deleted_at IS NULL AND active = 1 AND has_variants = 0 '
      'AND (barcode = ? OR sku = ?) LIMIT 1',
      [c, c],
    );
    return r == null ? null : Product.fromRow(r);
  }

  static Future<bool> codeInUse(String field, String value, {Set<String> exceptIds = const {}}) async {
    if (value.trim().isEmpty) return false;
    final rows = await Db.instance.s.q(
      'SELECT id FROM products WHERE deleted_at IS NULL AND $field = ?',
      [value.trim()],
    );
    return rows.any((r) => !exceptIds.contains(r['id']));
  }

  static Future<String> nextSku() async {
    final n = await Db.instance.s.scalar('SELECT COUNT(*) FROM products');
    final code = Db.instance.deviceId.substring(0, 2).toUpperCase();
    return 'SKU-$code${(n.toInt() + 1).toString().padLeft(5, '0')}';
  }

  /// Creates or updates a product. For new simple products [openingStock] is
  /// recorded as an "opening" stock movement. Variants are saved as child rows.
  /// Products (not counting variants) the shop has now.
  static Future<int> count() async => (await Db.instance.s.scalar(
          'SELECT COUNT(*) FROM products WHERE deleted_at IS NULL AND parent_id IS NULL'))
      .toInt();

  /// Throws [ProductLimitError] when the plan's product limit is reached.
  static Future<void> checkLimit() async {
    final max = Access.instance.maxProducts;
    if (max <= 0) return;
    if (await count() >= max) throw ProductLimitError(max);
  }

  static Future<String> save(
    Product prod, {
    required bool isNew,
    double openingStock = 0,
    List<VariantInput>? variants,
    List<String> removedVariantIds = const [],
  }) async {
    final userId = AppState.instance.user?.id;
    if (isNew) await checkLimit();
    return Db.instance.tx((s) async {
      final row = prod.toRow();
      String id;
      if (isNew) {
        id = await s.insert('products', {...row, 'id': prod.id});
        if (!prod.hasVariants && prod.trackStock && openingStock != 0) {
          await InventoryService.addMovement(s,
              productId: id, qty: openingStock, type: 'opening', unitCost: prod.costPrice, employeeId: userId);
        }
      } else {
        id = prod.id;
        await s.update('products', id, row);
      }

      final touched = <String>[id];
      if (prod.hasVariants && variants != null) {
        for (final v in variants) {
          final vRow = {
            'name': prod.name,
            'variant_name': v.name,
            'sku': v.sku,
            'barcode': v.barcode,
            'category_id': prod.categoryId,
            'unit': prod.unit,
            'cost_price': v.cost,
            'sale_price': v.price,
            'tax_rate': prod.taxRate,
            'track_stock': prod.trackStock ? 1 : 0,
            'low_stock': prod.lowStock,
            'image': prod.image,
            'attrs': row['attrs'],
            'parent_id': id,
            'has_variants': 0,
            'active': prod.active ? 1 : 0,
          };
          if (v.id == null) {
            final vid = await s.insert('products', vRow);
            if (prod.trackStock && v.openingStock != 0) {
              await InventoryService.addMovement(s,
                  productId: vid, qty: v.openingStock, type: 'opening', unitCost: v.cost, employeeId: userId);
            }
            touched.add(vid);
          } else {
            await s.update('products', v.id!, vRow);
            touched.add(v.id!);
          }
        }
        for (final rid in removedVariantIds) {
          await s.softDelete('products', rid);
        }
      }
      await InventoryService.refreshStock(s, touched);
      await ActivityLog.add(isNew ? 'Product added' : 'Product updated',
          entity: 'product', entityId: id, detail: prod.name, s: s);
      return id;
    });
  }

  static Future<void> delete(String id) async {
    await Db.instance.tx((s) async {
      final p = await s.byId('products', id);
      await s.softDelete('products', id);
      final kids = await s.q('SELECT id FROM products WHERE parent_id = ? AND deleted_at IS NULL', [id]);
      for (final k in kids) {
        await s.softDelete('products', k['id'] as String);
      }
      await ActivityLog.add('Product deleted', entity: 'product', entityId: id, detail: '${p?['name']}', s: s);
    });
  }

  // -------------------------------------------------------------- categories
  static Future<List<Category>> categories(String kind) async {
    final rows = await Db.instance.s.q(
      'SELECT * FROM categories WHERE kind = ? AND deleted_at IS NULL ORDER BY sort, name COLLATE NOCASE',
      [kind],
    );
    return rows.map(Category.fromRow).toList();
  }

  static Future<String> addCategory(String name, String kind) async {
    final n = await Db.instance.s.scalar('SELECT COUNT(*) FROM categories WHERE kind = ?', [kind]);
    return Db.instance.s.insert('categories', {'name': name.trim(), 'kind': kind, 'sort': n.toInt()});
  }

  static Future<void> renameCategory(String id, String name) =>
      Db.instance.s.update('categories', id, {'name': name.trim()});

  static Future<void> deleteCategory(String id) => Db.instance.s.softDelete('categories', id);
}


/// The shop has as many products as its plan allows.
class ProductLimitError extends StateError {
  ProductLimitError(this.limit) : super('Your plan allows $limit products. Upgrade to add more.');
  final int limit;
}
