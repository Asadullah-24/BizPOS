/// Permission keys stored in roles.permissions (JSON list).
class Perm {
  static const dashboard = 'dashboard.view';
  static const sell = 'pos.sell';
  static const discount = 'pos.discount';
  static const editPrice = 'pos.edit_price';
  static const salesView = 'sales.view';
  static const salesCancel = 'sales.cancel';
  static const returns = 'returns.manage';
  static const products = 'products.manage';
  static const inventory = 'inventory.adjust';
  static const purchases = 'purchases.manage';
  static const customers = 'customers.manage';
  static const suppliers = 'suppliers.manage';
  static const expenses = 'expenses.manage';
  static const accounts = 'accounts.manage';
  static const reports = 'reports.view';
  static const employees = 'employees.manage';
  static const settings = 'settings.manage';
  static const backup = 'backup.manage';

  static const Map<String, String> labels = {
    dashboard: 'View dashboard',
    sell: 'Sell at POS',
    discount: 'Give discounts',
    editPrice: 'Change prices at POS',
    salesView: 'View sales and invoices',
    salesCancel: 'Cancel sales',
    returns: 'Process returns and refunds',
    products: 'Manage products and categories',
    inventory: 'Adjust stock',
    purchases: 'Manage purchases',
    customers: 'Manage customers',
    suppliers: 'Manage suppliers',
    expenses: 'Manage expenses',
    accounts: 'Manage accounts and transfers',
    reports: 'View reports and profit',
    employees: 'Manage employees and roles',
    settings: 'Change settings',
    backup: 'Backup and restore',
  };

  static List<String> get all => labels.keys.toList();

  static const List<String> manager = [
    dashboard, sell, discount, editPrice, salesView, salesCancel, returns, products, inventory,
    purchases, customers, suppliers, expenses, accounts, reports,
  ];

  static const List<String> cashier = [sell, discount, salesView, returns, customers];

  static const List<String> stockKeeper = [products, inventory, purchases, suppliers];
}
