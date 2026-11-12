import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../services/product_service.dart';
import '../common.dart';

/// Unlimited custom categories for products or expenses.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.kind});
  final String kind;

  Future<void> _add(BuildContext context) async {
    final name = await promptText(context, 'New category', label: 'Name');
    if (name == null || name.trim().isEmpty) return;
    await ProductService.addCategory(name, kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(kind == 'expense' ? 'Expense categories' : 'Product categories'))),
      floatingActionButton: FloatingActionButton(onPressed: () => _add(context), child: const Icon(Icons.add)),
      body: LiveData<List<Category>>(
        load: () => ProductService.categories(kind),
        builder: (ctx, cats) => cats.isEmpty
            ? const EmptyState(icon: Icons.category_outlined, text: 'Nothing here yet')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: cats.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = cats[i];
                  return ListTile(
                    leading: const Icon(Icons.label_outline),
                    title: Text(c.name),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final n = await promptText(context, 'Rename category', initial: c.name, label: 'Name');
                          if (n != null && n.trim().isNotEmpty) await ProductService.renameCategory(c.id, n);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(context, 'Delete category', 'Delete "${c.name}"? Items keep working without a category.', danger: true)) {
                            await ProductService.deleteCategory(c.id);
                          }
                        },
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}
