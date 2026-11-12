/// Modules a business type can switch on or off.
class Mod {
  static const pos = 'pos';
  static const products = 'products';
  static const inventory = 'inventory';
  static const variants = 'variants';
  static const barcode = 'barcode';
  static const customers = 'customers';
  static const suppliers = 'suppliers';
  static const purchases = 'purchases';
  static const expenses = 'expenses';
  static const accounts = 'accounts';
  static const reports = 'reports';
  static const employees = 'employees';
  static const returns = 'returns';
  static const tax = 'tax';

  static const Map<String, String> labels = {
    pos: 'Point of sale',
    products: 'Products',
    inventory: 'Inventory tracking',
    variants: 'Product variants (size, color...)',
    barcode: 'Barcode scanning',
    customers: 'Customers and credit',
    suppliers: 'Suppliers',
    purchases: 'Purchases',
    expenses: 'Expenses',
    accounts: 'Accounts (cash, bank, digital)',
    reports: 'Reports',
    employees: 'Employees',
    returns: 'Returns and refunds',
    tax: 'Taxes',
  };

  static List<String> get all => labels.keys.toList();
}

class BusinessTemplate {
  const BusinessTemplate({
    required this.key,
    required this.name,
    required this.icon,
    required this.modules,
    required this.units,
    required this.fields,
    required this.productCategories,
    required this.expenseCategories,
  });

  final String key;
  final String name;
  final String icon;
  final List<String> modules;
  final List<String> units;

  /// Extra product fields shown on the product form for this business type.
  final List<String> fields;
  final List<String> productCategories;
  final List<String> expenseCategories;
}

const _baseExpenses = ['Rent', 'Electricity', 'Salaries', 'Transport', 'Internet & phone', 'Other'];

const List<String> _allButVariants = [
  Mod.pos, Mod.products, Mod.inventory, Mod.barcode, Mod.customers, Mod.suppliers, Mod.purchases,
  Mod.expenses, Mod.accounts, Mod.reports, Mod.employees, Mod.returns, Mod.tax,
];

const List<BusinessTemplate> businessTemplates = [
  BusinessTemplate(
    key: 'grocery',
    name: 'Grocery / General store',
    icon: 'grocery',
    modules: _allButVariants,
    units: ['pcs', 'kg', 'g', 'ltr', 'ml', 'dozen', 'pack'],
    fields: ['Brand'],
    productCategories: ['Groceries', 'Beverages', 'Snacks', 'Dairy', 'Household', 'Personal care'],
    expenseCategories: _baseExpenses,
  ),
  BusinessTemplate(
    key: 'pharmacy',
    name: 'Pharmacy / Medical store',
    icon: 'pharmacy',
    modules: _allButVariants,
    units: ['pcs', 'strip', 'box', 'bottle', 'tube'],
    fields: ['Formula', 'Company', 'Batch no', 'Expiry date'],
    productCategories: ['Tablets', 'Syrups', 'Injections', 'Surgical', 'Baby care', 'Cosmetics'],
    expenseCategories: _baseExpenses,
  ),
  BusinessTemplate(
    key: 'clothing',
    name: 'Clothing / Fashion',
    icon: 'clothing',
    modules: [..._allButVariants, Mod.variants],
    units: ['pcs', 'suit', 'meter', 'pair'],
    fields: ['Brand', 'Fabric', 'Season'],
    productCategories: ['Men', 'Women', 'Kids', 'Unstitched', 'Accessories'],
    expenseCategories: _baseExpenses,
  ),
  BusinessTemplate(
    key: 'mobile',
    name: 'Mobile & electronics shop',
    icon: 'mobile',
    modules: [..._allButVariants, Mod.variants],
    units: ['pcs', 'set'],
    fields: ['Brand', 'Model', 'IMEI / Serial', 'Warranty'],
    productCategories: ['Phones', 'Accessories', 'Chargers', 'Covers', 'Repairs'],
    expenseCategories: _baseExpenses,
  ),
  BusinessTemplate(
    key: 'restaurant',
    name: 'Restaurant / Cafe',
    icon: 'restaurant',
    modules: [
      Mod.pos, Mod.products, Mod.customers, Mod.suppliers, Mod.purchases, Mod.expenses,
      Mod.accounts, Mod.reports, Mod.employees, Mod.returns, Mod.tax, Mod.variants,
    ],
    units: ['plate', 'cup', 'pcs', 'serving'],
    fields: ['Preparation time'],
    productCategories: ['Starters', 'Main course', 'Fast food', 'Drinks', 'Desserts'],
    expenseCategories: ['Ingredients', 'Gas', ..._baseExpenses],
  ),
  BusinessTemplate(
    key: 'perfume',
    name: 'Perfume & cosmetics',
    icon: 'perfume',
    modules: [..._allButVariants, Mod.variants],
    units: ['pcs', 'ml', 'bottle'],
    fields: ['Inspired by', 'Concentration', 'Gender'],
    productCategories: ['Men', 'Women', 'Unisex', 'Attar', 'Gift sets'],
    expenseCategories: ['Packaging', 'Courier', 'Ads', ..._baseExpenses],
  ),
  BusinessTemplate(
    key: 'hardware',
    name: 'Hardware & building material',
    icon: 'hardware',
    modules: _allButVariants,
    units: ['pcs', 'kg', 'ft', 'meter', 'bag', 'box'],
    fields: ['Brand', 'Size'],
    productCategories: ['Tools', 'Electrical', 'Plumbing', 'Paint', 'Fasteners'],
    expenseCategories: _baseExpenses,
  ),
  BusinessTemplate(
    key: 'custom',
    name: 'Custom business',
    icon: 'custom',
    modules: _allButVariants,
    units: ['pcs'],
    fields: [],
    productCategories: ['General'],
    expenseCategories: _baseExpenses,
  ),
];
