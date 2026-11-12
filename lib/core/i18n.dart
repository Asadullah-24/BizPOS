/// Lightweight translations. English text is the key; add a language by adding
/// a map below and an entry in [I18n.languages]. Missing keys fall back to English.
class I18n {
  static String lang = 'en';

  static const Map<String, String> languages = {
    'en': 'English',
    'ur': 'اردو (Urdu)',
  };

  static const Set<String> rtl = {'ur', 'ar'};

  static bool get isRtl => rtl.contains(lang);

  static final Map<String, Map<String, String>> _tables = {
    'ur': _ur,
  };

  static String t(String en) {
    if (lang == 'en') return en;
    return _tables[lang]?[en] ?? en;
  }
}

String tr(String en) => I18n.t(en);

const Map<String, String> _ur = {
  // Navigation
  'Dashboard': 'ڈیش بورڈ',
  'Sell': 'فروخت',
  'POS': 'پوائنٹ آف سیل',
  'Products': 'مصنوعات',
  'Sales': 'سیلز',
  'More': 'مزید',
  'Inventory': 'اسٹاک',
  'Categories': 'کیٹیگریز',
  'Customers': 'گاہک',
  'Suppliers': 'سپلائرز',
  'Purchases': 'خریداری',
  'Expenses': 'اخراجات',
  'Accounts': 'اکاؤنٹس',
  'Reports': 'رپورٹس',
  'Employees': 'ملازمین',
  'Returns': 'واپسی',
  'Settings': 'سیٹنگز',
  'Backup & restore': 'بیک اپ اور ریسٹور',
  'Activity log': 'سرگرمی لاگ',
  'Roles': 'رولز',
  'Printer': 'پرنٹر',
  'Lock': 'لاک',

  // Common actions
  'Save': 'محفوظ کریں',
  'Cancel': 'منسوخ',
  'Delete': 'حذف کریں',
  'Edit': 'ترمیم',
  'Add': 'شامل کریں',
  'Search': 'تلاش',
  'Done': 'مکمل',
  'Close': 'بند کریں',
  'Yes': 'ہاں',
  'No': 'نہیں',
  'OK': 'ٹھیک ہے',
  'Share': 'شیئر',
  'Print': 'پرنٹ',
  'Scan': 'اسکین',
  'Retry': 'دوبارہ کوشش',
  'Continue': 'جاری رکھیں',
  'Next': 'اگلا',
  'Back': 'واپس',
  'All': 'سب',
  'Name': 'نام',
  'Phone': 'فون',
  'Email': 'ای میل',
  'Address': 'پتہ',
  'Notes': 'نوٹس',
  'Note': 'نوٹ',
  'Date': 'تاریخ',
  'Amount': 'رقم',
  'Total': 'کل',
  'Subtotal': 'ذیلی کل',
  'Discount': 'رعایت',
  'Tax': 'ٹیکس',
  'Paid': 'ادا شدہ',
  'Balance': 'بیلنس',
  'Balance due': 'بقایا',
  'Change': 'باقی رقم',
  'Quantity': 'مقدار',
  'Price': 'قیمت',
  'Cost': 'لاگت',
  'Stock': 'اسٹاک',
  'Category': 'کیٹیگری',
  'Account': 'اکاؤنٹ',
  'Customer': 'گاہک',
  'Supplier': 'سپلائر',
  'Walk-in customer': 'عام گاہک',
  'Nothing here yet': 'ابھی یہاں کچھ نہیں',

  // Dashboard
  'Today': 'آج',
  'This month': 'اس مہینے',
  'Revenue': 'آمدنی',
  'Profit': 'منافع',
  'Net profit': 'خالص منافع',
  'Gross profit': 'مجموعی منافع',
  'Low stock': 'کم اسٹاک',
  'Receivables': 'وصولیاں',
  'Payables': 'ادائیگیاں',
  'Recent sales': 'حالیہ سیلز',
  'Last 7 days': 'پچھلے 7 دن',

  // POS
  'Cart': 'کارٹ',
  'Cart is empty': 'کارٹ خالی ہے',
  'Checkout': 'چیک آؤٹ',
  'Charge': 'وصول کریں',
  'Clear cart': 'کارٹ خالی کریں',
  'Add payment': 'ادائیگی شامل کریں',
  'Complete sale': 'سیل مکمل کریں',
  'Sale completed': 'سیل مکمل ہو گئی',
  'New sale': 'نئی سیل',
  'Remaining': 'باقی',
  'Out of stock': 'اسٹاک ختم',

  // Reports
  'Daily': 'روزانہ',
  'Weekly': 'ہفتہ وار',
  'Monthly': 'ماہانہ',
  'Yearly': 'سالانہ',
  'Custom': 'اپنی مرضی',
  'Top products': 'سب سے زیادہ بکنے والی',

  // Settings
  'Language': 'زبان',
  'Currency': 'کرنسی',
  'Business profile': 'کاروباری پروفائل',
  'Business type': 'کاروبار کی قسم',
  'Change PIN': 'پن تبدیل کریں',
  'Enter PIN': 'پن درج کریں',
  'Wrong PIN': 'غلط پن',
};
