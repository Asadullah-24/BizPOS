import 'dart:convert';

import '../core/app_state.dart';
import '../core/business_templates.dart';
import '../core/db.dart';
import '../core/permissions.dart';
import 'auth_service.dart';

/// First-run setup: business type, default data and the owner account.
class SetupService {
  static Future<void> createBusiness({
    required String businessName,
    required BusinessTemplate template,
    String? customTypeName,
    required String currencySymbol,
    required int decimals,
    required String ownerName,
    required String pin,
    required String language,
  }) async {
    await Db.instance.tx((s) async {
      final typeId = await s.insert('business_types', {
        'name': (customTypeName != null && customTypeName.trim().isNotEmpty)
            ? customTypeName.trim()
            : template.name,
        'icon': template.icon,
        'modules': jsonEncode(template.modules),
        'units': jsonEncode(template.units),
        'product_fields': jsonEncode(template.fields),
        'is_custom': template.key == 'custom' ? 1 : 0,
      });

      for (var i = 0; i < template.productCategories.length; i++) {
        await s.insert('categories', {
          'name': template.productCategories[i],
          'kind': 'product',
          'sort': i,
        });
      }
      for (var i = 0; i < template.expenseCategories.length; i++) {
        await s.insert('categories', {
          'name': template.expenseCategories[i],
          'kind': 'expense',
          'sort': i,
        });
      }

      await s.insert('accounts', {'name': 'Cash', 'type': 'cash', 'is_default': 1});
      await s.insert('accounts', {'name': 'Bank', 'type': 'bank'});
      await s.insert('accounts', {'name': 'Digital wallet', 'type': 'digital'});

      final ownerRole = await s.insert('roles', {
        'name': 'Owner',
        'permissions': jsonEncode(Perm.all),
        'is_system': 1,
      });
      await s.insert('roles', {'name': 'Manager', 'permissions': jsonEncode(Perm.manager)});
      await s.insert('roles', {'name': 'Cashier', 'permissions': jsonEncode(Perm.cashier)});
      await s.insert('roles', {'name': 'Stock keeper', 'permissions': jsonEncode(Perm.stockKeeper)});

      await s.insert('employees', {
        'name': ownerName.trim(),
        'role_id': ownerRole,
        'is_owner': 1,
        'active': 1,
        ...AuthService.pinColumns(pin),
      });

      final settings = <String, String>{
        'business_name': businessName.trim(),
        'business_type_id': typeId,
        'currency_symbol': currencySymbol.trim(),
        'currency_decimals': '$decimals',
        'language': language,
        'tax_enabled': '0',
        'tax_rate': '0',
        'tax_inclusive': '0',
        'invoice_prefix': 'INV',
        'invoice_footer': 'Thank you for your business!',
        'receipt_paper': '58',
        'onboarded': '1',
      };
      for (final e in settings.entries) {
        await s.ex.insert('settings', {'key': e.key, 'value': e.value, 'updated_at': DateTime.now().millisecondsSinceEpoch});
      }
    });
    await AppState.instance.load();
  }
}
