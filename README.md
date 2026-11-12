# BizPOS

Offline-first point of sale and business management app for small businesses, built with Flutter for Android and iOS.

Selling never needs the internet. All data lives in SQLite on the phone, survives restarts, and is backed up to Google Drive whenever the phone is online.

## Features

| Module | What it does |
| --- | --- |
| Business types | Templates (grocery, pharmacy, clothing, mobile shop, restaurant, perfume, hardware) or a fully custom type. Each type controls modules, units and extra product fields, editable any time. |
| Dashboard | Today and month sales, profit, expenses, receivables, payables, low stock, 7-day chart, recent sales |
| POS | Product grid with search and categories, camera and hardware barcode scanning, quick items, line and cart discounts (amount or %), inclusive or exclusive tax, split payments across cash/bank/wallet, credit sales, change calculation |
| Products | SKU, barcode, photo, unit, cost and sale price, per-product tax, variants (size/colour...) each with its own price, SKU, barcode and stock, custom fields |
| Inventory | Stock ledger, low-stock alerts, add/remove/count adjustments with reasons, movement history, stock value |
| Categories | Unlimited product and expense categories |
| Customers | Profiles, purchase history, running balance, receive payments |
| Suppliers | Supplier accounts, purchase records, payables, pay supplier |
| Purchases | Stock receiving with landed cost (discount and freight spread over items), weighted average cost, purchase invoices, void |
| Expenses | Custom categories, paid from any account, date and note |
| Accounts | Cash, bank and digital accounts with live balances, transfers, statements |
| Reports | Daily, weekly, monthly, yearly and custom ranges: profit and loss, chart, top products, by category, by account, expenses; PDF export |
| Employees | Roles with fine-grained permissions, per-employee PIN, activity log |
| Invoices | A4 PDF invoice, 58/80 mm receipt, share, system print, Bluetooth and network ESC/POS thermal printers |
| Returns | Refunds, store credit, exchanges (credit carried into a new sale), cancellations with stock and payment reversal |
| Settings | Business profile, currency symbol and decimals, tax, language (English, Urdu with RTL), invoice prefix and footer, auto-print, auto-lock |

## Offline-first design

* No network call is ever needed to sell, print to Bluetooth, or run reports.
* Data is in SQLite (`sqflite`) with a versioned migration system (`lib/core/migrations.dart`).
* Every row has a UUID, `created_at`, `updated_at`, `deleted_at` and `device_id`.
* Stock is a ledger (`stock_movements`), and balances are calculated from transactions. Nothing is stored as an editable total, so merging data from two phones can never lose a sale.
* Invoice numbers include a device code (`INV-3FA2-00012`) so two phones selling offline never clash.

### Backup, restore and conflict handling

* **Google Drive** (optional sign-in): each phone uploads its snapshot to the app's private `appDataFolder`, automatically when the phone comes online and every 15 minutes while open if something changed. Product photos are uploaded once each.
* **Restore / sync** downloads every phone's snapshot and **merges** it:
  * rows that do not exist locally are added (transactions are never overwritten);
  * rows that exist on both sides keep the newest `updated_at`;
  * deletes are soft, so they travel too;
  * stock and balances are recalculated afterwards.
* **Backup file** export/import (`.bizpos`, gzip JSON, optional photos) to share over WhatsApp, email or USB. Import can merge (safe) or replace.
* **Changing phones**: on the new phone choose *Restore from Google Drive* or *Restore from a backup file* on the first screen, then sign in with your old PIN.

## Project layout

```
lib/
  core/        database, migrations, settings/app state, formatting, translations, permissions, business templates
  models/      typed models
  services/    sales, returns, purchases, expenses, ledger, inventory, reports, backup, Drive, PDF, printing
  ui/          screens and shared widgets
test/          unit tests (cart maths)
tool/          patch_platforms.py (permissions, minSdk, signing for generated platform folders)
.github/       Android build (every push) and iOS unsigned build (manual)
```

## Build

See [docs/SETUP.md](docs/SETUP.md) for full instructions, including Google Drive and release signing.

Quick start:

```bash
flutter pub get
flutter run                 # on a connected phone
flutter build apk --release # Android APK
```

Every push to `main` builds a release APK in GitHub Actions. Download it from the run's **Artifacts** section.

## Tech

Flutter 3.24, sqflite, provider, fl_chart, pdf + printing, esc_pos_utils_plus + print_bluetooth_thermal, mobile_scanner, image_picker, google_sign_in + googleapis (Drive v3), connectivity_plus.
