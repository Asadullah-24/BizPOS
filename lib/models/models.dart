import 'dart:convert';

import '../core/db.dart';

List<String> _strList(Object? v) {
  if (v == null || (v is String && v.isEmpty)) return [];
  final d = jsonDecode(v as String);
  return (d as List).map((e) => e.toString()).toList();
}

Map<String, String> _strMap(Object? v) {
  if (v == null || (v is String && v.isEmpty)) return {};
  final d = jsonDecode(v as String) as Map;
  return d.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
}

class BusinessType {
  BusinessType({
    required this.id,
    required this.name,
    required this.icon,
    required this.modules,
    required this.units,
    required this.fields,
    required this.isCustom,
  });

  final String id;
  String name;
  String icon;
  List<String> modules;
  List<String> units;
  List<String> fields;
  bool isCustom;

  factory BusinessType.fromRow(DbRow r) => BusinessType(
        id: r['id'] as String,
        name: r['name'] as String,
        icon: (r['icon'] ?? 'custom') as String,
        modules: _strList(r['modules']),
        units: _strList(r['units']),
        fields: _strList(r['product_fields']),
        isCustom: asBool(r['is_custom']),
      );

  DbRow toRow() => {
        'name': name,
        'icon': icon,
        'modules': jsonEncode(modules),
        'units': jsonEncode(units),
        'product_fields': jsonEncode(fields),
        'is_custom': isCustom ? 1 : 0,
      };

  bool has(String module) => modules.contains(module);
}

class Category {
  Category({required this.id, required this.name, required this.kind, this.color});
  final String id;
  final String name;
  final String kind;
  final int? color;

  factory Category.fromRow(DbRow r) => Category(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: r['kind'] as String,
        color: r['color'] as int?,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    this.categoryId,
    this.unit,
    this.costPrice = 0,
    this.salePrice = 0,
    this.taxRate,
    this.trackStock = true,
    this.lowStock = 0,
    this.image,
    Map<String, String>? attrs,
    this.parentId,
    this.variantName,
    this.hasVariants = false,
    this.active = true,
    this.stock = 0,
  }) : attrs = attrs ?? {};

  final String id;
  String name;
  String? sku;
  String? barcode;
  String? categoryId;
  String? unit;
  double costPrice;
  double salePrice;
  double? taxRate;
  bool trackStock;
  double lowStock;
  String? image;
  Map<String, String> attrs;
  String? parentId;
  String? variantName;
  bool hasVariants;
  bool active;
  double stock;

  /// Extra photos after the main [image] (file names), kept in a hidden attribute.
  /// Attributes whose key starts with "_" are internal and not shown in the form.
  List<String> get moreImages => (attrs['_more_images'] ?? '').split('|').where((e) => e.isNotEmpty).toList();
  set moreImages(List<String> v) => v.isEmpty ? attrs.remove('_more_images') : attrs['_more_images'] = v.join('|');

  /// Main photo first, then the extra ones.
  List<String> get allImages => [if (image != null && image!.isNotEmpty) image!, ...moreImages];

    /// Name shown on receipts and in the cart, including the variant.
  String get displayName =>
      (variantName == null || variantName!.isEmpty) ? name : '$name ($variantName)';

  bool get isLow => trackStock && stock <= lowStock;

  factory Product.fromRow(DbRow r) => Product(
        id: r['id'] as String,
        name: r['name'] as String,
        sku: asStr(r['sku']),
        barcode: asStr(r['barcode']),
        categoryId: asStr(r['category_id']),
        unit: asStr(r['unit']),
        costPrice: asDouble(r['cost_price']),
        salePrice: asDouble(r['sale_price']),
        taxRate: r['tax_rate'] == null ? null : asDouble(r['tax_rate']),
        trackStock: asBool(r['track_stock']),
        lowStock: asDouble(r['low_stock']),
        image: asStr(r['image']),
        attrs: _strMap(r['attrs']),
        parentId: asStr(r['parent_id']),
        variantName: asStr(r['variant_name']),
        hasVariants: asBool(r['has_variants']),
        active: asBool(r['active']),
        stock: asDouble(r['stock']),
      );

  DbRow toRow() => {
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'category_id': categoryId,
        'unit': unit,
        'cost_price': costPrice,
        'sale_price': salePrice,
        'tax_rate': taxRate,
        'track_stock': trackStock ? 1 : 0,
        'low_stock': lowStock,
        'image': image,
        'attrs': jsonEncode(attrs),
        'parent_id': parentId,
        'variant_name': variantName,
        'has_variants': hasVariants ? 1 : 0,
        'active': active ? 1 : 0,
      };
}

/// A customer or a supplier.
class Party {
  Party({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.openingBalance = 0,
    this.notes,
    this.balance = 0,
  });

  final String id;
  String name;
  String? phone;
  String? email;
  String? address;
  double openingBalance;
  String? notes;

  /// Customer: amount they owe us. Supplier: amount we owe them.
  double balance;

  factory Party.fromRow(DbRow r) => Party(
        id: r['id'] as String,
        name: r['name'] as String,
        phone: asStr(r['phone']),
        email: asStr(r['email']),
        address: asStr(r['address']),
        openingBalance: asDouble(r['opening_balance']),
        notes: asStr(r['notes']),
        balance: asDouble(r['balance']),
      );

  DbRow toRow() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'opening_balance': openingBalance,
        'notes': notes,
      };
}

class Account {
  Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.isDefault = false,
    this.balance = 0,
  });

  final String id;
  String name;

  /// cash | bank | digital
  String type;
  double openingBalance;
  bool isDefault;
  double balance;

  factory Account.fromRow(DbRow r) => Account(
        id: r['id'] as String,
        name: r['name'] as String,
        type: r['type'] as String,
        openingBalance: asDouble(r['opening_balance']),
        isDefault: asBool(r['is_default']),
        balance: asDouble(r['balance']),
      );
}

class Role {
  Role({required this.id, required this.name, required this.permissions, this.isSystem = false});
  final String id;
  String name;
  List<String> permissions;
  bool isSystem;

  factory Role.fromRow(DbRow r) => Role(
        id: r['id'] as String,
        name: r['name'] as String,
        permissions: _strList(r['permissions']),
        isSystem: asBool(r['is_system']),
      );
}

class Employee {
  Employee({
    required this.id,
    required this.name,
    this.phone,
    this.roleId,
    this.active = true,
    this.isOwner = false,
  });

  final String id;
  String name;
  String? phone;
  String? roleId;
  bool active;
  bool isOwner;

  factory Employee.fromRow(DbRow r) => Employee(
        id: r['id'] as String,
        name: r['name'] as String,
        phone: asStr(r['phone']),
        roleId: asStr(r['role_id']),
        active: asBool(r['active']),
        isOwner: asBool(r['is_owner']),
      );
}
