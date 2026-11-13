# BizPOS setup guide

## 1. Get the Android APK (no computer needed)

1. On the phone open <https://github.com/Asadullah-24/BizPOS/releases/latest/download/BizPOS.apk>
   (about 30 MB; `BizPOS-armv7.apk` is for older 32-bit phones, `BizPOS.aab` is for Google Play).
2. Open the downloaded file and allow "Install unknown apps" when asked.

Every push to `main` runs the tests, builds a new APK and replaces the file at that link. Older builds stay in
**Actions** > **Android build** > run > **Artifacts**.

> Without a release keystore (step 3) each build is signed with a temporary key, so Android may refuse to
> install a newer build over an older one. Uninstall first, or set up the keystore once.

## 2. Build locally

Requirements: Flutter 3.24.x (stable), Android Studio or the Android SDK, Java 17. For iOS: a Mac with Xcode 15.3+ and CocoaPods. Minimum iOS version is 15.5 (required by the barcode scanner).
Minimum Android version is 6.0 (API 23).

```bash
flutter pub get
python3 tool/patch_platforms.py   # only needed if you regenerate android/ or ios/
flutter test
flutter run                       # debug on a connected device
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release # for Google Play
```

App id / bundle id: `com.bizpos.bizpos`. To change it, edit `applicationId` and `namespace` in
`android/app/build.gradle` and `PRODUCT_BUNDLE_IDENTIFIER` in Xcode.

## 3. Release signing (Android)

Create a keystore once and keep it safe. Losing it means you cannot update the installed app.

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bizpos
```

**For GitHub Actions** add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | output of `base64 -w0 release.jks` |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | `bizpos` |
| `KEY_PASSWORD` | key password |

**For local builds** create `android/key.properties` (it is git-ignored):

```
storeFile=release.jks
storePassword=...
keyAlias=bizpos
keyPassword=...
```

and put `release.jks` in `android/app/`.

Never commit the keystore or passwords. This repository is public.

## 4. Accounts, free plan and the online super admin panel

**Free to start.** Anyone can install BizPOS and sell straight away. With Firebase configured the first screen
offers *Create free account*, *Sign in*, *Continue with Google* or *Use without an account (offline)*.
Free shops get the core POS with banner ads. Paid features (reports, employees, logo, alerts, reminders, voice)
come from a subscription, an offline code, or a rewarded ad that unlocks one feature for 24 hours.

**Connect Firebase** (once):
1. Create the project, enable Email/Password and Google sign-in, create Firestore (see the chat steps).
2. Put the values from Project settings into `lib/core/firebase_config.dart` (Android, iOS, web client id).
3. Firestore > Rules: paste `firebase/firestore.rules` and publish. Rules tests run in CI (`.github/workflows/rules.yml`).
4. Sign up in the app with your own email (or Google), open *More > Account*, copy your **User ID**.
5. Firestore > Start collection `admins` > Document ID = your User ID > field `role` (string) = `super`.
   Reopen the app: *More > Super admin* appears.

**Super admin panel** (any phone, anywhere, after signing in):
* Overview: shops, paid, free, blocked, revenue this month, pending requests, plans expiring in 7 days.
* Shops: search and filter; open a shop to activate or extend a package (days are added to any time left),
  set free, block/unblock, see devices and payment history, WhatsApp the owner.
* Packages: create, edit, hide or delete packages (name, price text, amount, days or lifetime, features, no ads).
  *Create default packages* adds Starter, Pro monthly, Pro yearly and Lifetime Basic.
* Requests: shops request a package from their Plan screen; approve (records the payment) or reject.
* Settings: branding (footer and support phone for every shop), 2FA on/off for the panel, account password,
  offline unlock codes, change the offline code password.

**Security**
* Shop owner forgets the account password: *Forgot password?* on the sign-in screen sends a reset email.
* Owner forgets the PIN: lock screen > *Owner forgot PIN? Sign in again* > account password (or Google) > new PIN.
* Phone lost or stolen: on another phone sign in > *Account > My devices > Remove*. When the lost phone goes
  online it erases its BizPOS data and signs out. The PIN and optional 2FA protect it until then.
* New phone: sign in, restore data from Google Drive, and the plan comes back automatically.
* Only the super admin can change plans, features, expiry or block shops; this is enforced by Firestore rules,
  not just the app. For the strongest protection sign in to the panel with a Google account that has
  Google 2-Step Verification on, and also turn on the panel's own authenticator code.

## 5. Offline unlock codes (shops without internet)

For shops that never go online, the super admin can still give a signed code. The phone's device code and QR
are on *More > Plan & upgrades*.

**Sign in as super admin**: tap *Super admin* on the activation screen, the login screen or Settings, then enter the
master password and the 6-digit code from your authenticator app (2FA).

**Activate a shop (on site, offline)**
1. On your phone open the console > *Activate or upgrade a shop*.
2. Scan the shop phone's device QR, enter the shop name, owner WhatsApp, category, plan, validity, extra features and credits.
3. *Generate code*. On the shop phone tap *Scan activation QR* and scan it. Or send the code on WhatsApp and the shop pastes it.
4. Or run the console on the shop's own phone: *Set up this phone for a shop* > *Apply on this phone*.
5. Then set up the store: category defaults (grocery, pharmacy, clothing, mobile, restaurant, bakery, salon, car rental,
   perfume, hardware, stationery, auto parts, custom) load automatically.

Codes are Ed25519-signed and bound to one device. They cannot be edited or used on another phone. Credit codes work once.
Renew or upgrade from *My shops* (your register of every shop, with expiry and QR).

**Packages** (`lib/core/packages.dart`)

| Plan | Price | Includes |
| --- | --- | --- |
| Free trial | 14 days | Everything in Basic, 20 voice credits |
| Basic | Rs 15,000 one time | Full offline POS, all current modules, low stock shown in app, 20 credits |
| Pro | Rs 1,000 / month or Rs 10,000 / year | Basic + low-stock and payment alerts, WhatsApp/SMS reminders, unlimited voice, marketplace listing (phase 2) |
| Credits | 50 = Rs 300, 200 = Rs 1,000, 1000 = Rs 4,000 | Voice stock updates, 1 credit each; 3 free credits per rewarded ad (10 ads/day) |

Any paid feature can also be added on its own to Basic from the console. When a plan expires the shop can still see
its data and reports, but selling pauses until renewal.

**Master password**: never stored. The keys are derived from it. To change it:
`python3 tool/admin_key.py "new password"`, add the printed public key to `LicenseKeys.trusted` in
`lib/core/license.dart`, rebuild, and add the printed authenticator secret to your authenticator app.
Keep the old key in the list so existing shops keep working.

**AdMob**: the app ships with Google's test ad ids. Before selling, put your AdMob App ID in
`tool/patch_platforms.py` (Android and iOS) and your rewarded ad unit ids in `lib/services/ads_service.dart`.

## 6. Google Drive backup

Drive backup is optional. Everything else works without it. Google sign-in only works after you register the app
with Google:

1. Go to <https://console.cloud.google.com>, create a project.
2. **APIs & Services > Library**: enable **Google Drive API**.
3. **OAuth consent screen**: External, add your app name and email. Add scope
   `https://www.googleapis.com/auth/drive.appdata`. While in "Testing", add the Google accounts that will use the app as test users
   (or publish the consent screen).
4. **Credentials > Create credentials > OAuth client ID > Android**
   * Package name: `com.bizpos.bizpos`
   * SHA-1: from your **release** keystore: `keytool -list -v -keystore release.jks -alias bizpos`
   * Add a second Android client with the debug SHA-1 if you also test debug builds
     (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`).
5. **iOS**: create an OAuth client of type iOS with bundle id `com.bizpos.bizpos`. Then add to `ios/Runner/Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

No `google-services.json` is needed: the app uses `google_sign_in` with the Drive `appDataFolder` scope only, so it
cannot see the user's other Drive files.

### How backup works

* Each phone uploads `bizpos-<device-id>.bizpos` (gzip JSON of all tables) to the hidden app folder.
* Photos upload once each as `img-<file>`.
* Automatic: when the phone comes online, when the app is reopened, and every 15 minutes while open, if anything changed.
* **Restore / sync** downloads every phone's file and merges. Use it on a new phone, or to combine two phones on one account.

## 7. iOS

* The `ios/` folder is a normal Xcode project (`ios/Runner.xcworkspace`).
* GitHub Actions has a manual **iOS build (unsigned)** workflow that checks the project compiles on macOS. It cannot produce an
  installable IPA because that needs your Apple signing certificate.
* To ship: on a Mac run `flutter build ipa`, or open `ios/Runner.xcworkspace` in Xcode, set your Team under
  Signing & Capabilities, then Product > Archive > Distribute (App Store Connect or Ad Hoc).
* Bluetooth printing on iOS only works with BLE printers; many cheap thermal printers are Bluetooth Classic and work on Android only.
  Network (Wi-Fi/LAN) ESC/POS printers and AirPrint work on both.

## 8. Printers

* **Bluetooth (Android)**: pair the printer in phone settings, then Settings > Printer > Find.
* **Network**: ESC/POS printers on port 9100, set the IP in Settings > Printer.
* **System print**: any printer Android/iOS can print to (Wi-Fi, AirPrint, Mopria), or save as PDF.
* Thermal receipts print ASCII only (printer code page). Urdu text and symbols like ₨ are replaced with `?`.
  The PDF invoice uses the built-in Helvetica font; for Urdu in PDFs bundle a font such as Noto Nastaliq Urdu.

## 9. Developer notes

### Database migrations

`lib/core/migrations.dart` holds a map `version -> SQL statements`. To change the schema:

1. Add a new entry, e.g. `2: ['ALTER TABLE products ADD COLUMN brand TEXT']`.
2. Bump `schemaVersion` to 2.
3. Never edit a migration that has shipped.

Backups record their schema version. The app refuses to import a backup from a newer schema, and imports older
backups by matching columns that exist.

### Sync rules

* All synced tables have `id` (UUID), `created_at`, `updated_at`, `deleted_at`, `device_id`.
* Deletes must be soft (`Store.softDelete`).
* Never store totals that can be derived. Stock comes from `stock_movements`, balances from `payments`, `sales`,
  `returns` and `purchases`.
* Inside `Db.instance.tx((s) async { ... })` use only `s`. Calling `Db.instance.s` inside a transaction deadlocks sqflite.

### Adding a language

Add a map to `lib/core/i18n.dart` and list it in `I18n.languages`. English text is the key; missing keys fall back to English.
RTL languages go in `I18n.rtl`.

### PIN recovery

* Employees: the owner resets their PIN in Employees.
* Owner: on the lock screen tap **Owner forgot PIN? Verify with Google** and sign in with the Google account used for Drive
  backup, then choose a new PIN. This option only appears when Drive backup is on, so turn it on early.
