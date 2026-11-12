# BizPOS setup guide

## 1. Get the Android APK (no computer needed)

1. On the phone open <https://github.com/Asadullah-24/BizPOS/releases/latest/download/BizPOS.apk>.
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

## 4. Google Drive backup

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

## 5. iOS

* The `ios/` folder is a normal Xcode project (`ios/Runner.xcworkspace`).
* GitHub Actions has a manual **iOS build (unsigned)** workflow that checks the project compiles on macOS. It cannot produce an
  installable IPA because that needs your Apple signing certificate.
* To ship: on a Mac run `flutter build ipa`, or open `ios/Runner.xcworkspace` in Xcode, set your Team under
  Signing & Capabilities, then Product > Archive > Distribute (App Store Connect or Ad Hoc).
* Bluetooth printing on iOS only works with BLE printers; many cheap thermal printers are Bluetooth Classic and work on Android only.
  Network (Wi-Fi/LAN) ESC/POS printers and AirPrint work on both.

## 6. Printers

* **Bluetooth (Android)**: pair the printer in phone settings, then Settings > Printer > Find.
* **Network**: ESC/POS printers on port 9100, set the IP in Settings > Printer.
* **System print**: any printer Android/iOS can print to (Wi-Fi, AirPrint, Mopria), or save as PDF.
* Thermal receipts print ASCII only (printer code page). Urdu text and symbols like ₨ are replaced with `?`.
  The PDF invoice uses the built-in Helvetica font; for Urdu in PDFs bundle a font such as Noto Nastaliq Urdu.

## 7. Developer notes

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
