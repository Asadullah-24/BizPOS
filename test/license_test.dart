import 'dart:convert';

import 'package:bizpos/core/db.dart';
import 'package:bizpos/core/license.dart';
import 'package:bizpos/core/totp.dart';
import 'package:bizpos/models/models.dart';
import 'package:bizpos/services/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Public test vector produced by tool/admin_key.py with password "test-password-123".
const testPassword = 'test-password-123';
const testPublicKey = 'bX-2DqGStn1nvQ5vvJ5hUBRlI4awixygow2VCWd3s6U';
const testTotpSecret = 'QCSNNWSBTBLQORI7S42GE6MWZJSBOVKT';
// Code signed in Python with the test key (device TESTDEV1, basic, alerts, 20 credits).
const pythonCode =
    'BZ1.eyJ2IjoxLCJ0IjoiYWN0IiwiZCI6IlRFU1RERVYxIiwicyI6InN0b3JlLTEiLCJuIjoibm9uY2UtMSIsInAiOiJiYXNpYyIsImYiOlsiYWxlcnRzIl0sImUiOjAsImMiOjIwLCJpIjoxNzAwMDAwMDAwMDAwfQ'
    '.iD-4wQw-HMD4Skb7EA2LWP24WkjUtdTJq8y0kivufBmtKdKFYhxsgYd9hv8Ora5kZ6wY60V2AeRtxp9SG85TCg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TOTP', () {
    test('RFC 6238 SHA1 vectors', () {
      final key = utf8.encode('12345678901234567890');
      expect(Totp.codeForKey(key, 59), '287082');
      expect(Totp.codeForKey(key, 1111111109), '081804');
      expect(Totp.codeForKey(key, 1234567890), '005924');
    });

    test('base32 round trip and verify window', () {
      final secret = Totp.newSecret();
      expect(Totp.base32Encode(Totp.base32Decode(secret)), secret);
      final now = DateTime.now();
      expect(Totp.verify(secret, Totp.code(secret, at: now), at: now), isTrue);
      expect(Totp.verify(secret, Totp.code(secret, at: now.subtract(const Duration(seconds: 30))), at: now), isTrue);
      expect(Totp.verify(secret, Totp.code(secret, at: now.subtract(const Duration(minutes: 5))), at: now), isFalse);
    });
  });

  group('license codes', () {
    late SuperAdminKey key;

    setUpAll(() async {
      key = await LicenseKeys.derive(testPassword);
      if (!LicenseKeys.trusted.contains(testPublicKey)) LicenseKeys.trusted.add(testPublicKey);
    });

    test('Dart key derivation matches tool/admin_key.py', () {
      expect(key.publicKey, testPublicKey);
      expect(key.totpSecret, testTotpSecret);
      expect(key.isTrusted, isTrue);
    });

    test('a wrong password gives an untrusted key', () async {
      final wrong = await LicenseKeys.derive('wrong password');
      expect(wrong.isTrusted, isFalse);
    });

    test('verifies a code signed by Python', () async {
      final p = await LicenseCodec.decode(pythonCode);
      expect(p, isNotNull);
      expect(p!.device, 'TESTDEV1');
      expect(p.plan, 'basic');
      expect(p.features, ['alerts']);
      expect(p.credits, 20);
      expect(p.expires, 0);
    });

    test('rejects tampered codes and unknown keys', () async {
      final parts = pythonCode.split('.');
      final payload = utf8.decode(LicenseKeys.unb64(parts[1])).replaceFirst('"basic"', '"pro"');
      final forged = '${parts[0]}.${LicenseKeys.b64(utf8.encode(payload))}.${parts[2]}';
      expect(await LicenseCodec.decode(forged), isNull);
      expect(await LicenseCodec.decode('garbage'), isNull);
      final other = await LicenseKeys.derive('someone else');
      final code = await LicenseCodec.encode(
        LicensePayload(type: 'act', device: 'TESTDEV1', nonce: 'x', issued: 1, plan: 'pro'),
        other,
      );
      expect(await LicenseCodec.decode(code), isNull);
    });

    test('round trip with all fields', () async {
      final code = await LicenseCodec.encode(
        LicensePayload(
          type: 'act', device: 'ABCD1234', nonce: 'n1', issued: 5, storeId: 's1', storeName: 'Shop',
          plan: 'pro', features: ['voice'], expires: 99, credits: 7, footer: 'Powered by X', phone: '0300',
        ),
        key,
      );
      final p = (await LicenseCodec.decode(code))!;
      expect([p.storeName, p.plan, p.expires, p.credits, p.footer, p.phone], ['Shop', 'pro', 99, 7, 'Powered by X', '0300']);
    });
  });

  group('LicenseService on a device', () {
    final lic = LicenseService.instance;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      Db.fileName = 'license_test.db';
      await Db.instance.init();
      await Db.instance.wipe();
      if (!LicenseKeys.trusted.contains(testPublicKey)) LicenseKeys.trusted.add(testPublicKey);
      SuperAdmin.key = await LicenseKeys.derive(testPassword);
      await lic.load();
    });

    test('a new phone is not activated', () {
      expect(lic.everActivated, isFalse);
      expect(lic.canSell, isFalse);
    });

    test('codes for another phone are refused', () async {
      final code = await SuperAdmin.issue(type: 'act', device: 'FFFF0000', plan: 'basic');
      await expectLater(lic.apply(code), throwsStateError);
    });

    test('trial, then expiry, then lifetime basic plus a paid feature', () async {
      final expired = await SuperAdmin.issue(
        type: 'act', device: lic.deviceCode, plan: 'trial', storeName: 'Test Shop', expires: nowMs() - 1000, credits: 20,
      );
      await lic.apply(expired);
      expect(lic.everActivated, isTrue);
      expect(lic.active, isFalse);
      expect(lic.storeName, 'Test Shop');
      expect(lic.credits, 20);

      final basic = await SuperAdmin.issue(type: 'act', device: lic.deviceCode, plan: 'basic', features: ['alerts'], phone: '03001234567');
      await lic.apply(basic);
      expect(lic.active, isTrue);
      expect(lic.planKey, 'basic');
      expect(lic.planExpires, 0);
      expect(lic.has('alerts'), isTrue);
      expect(lic.has('voice'), isFalse);
      expect(lic.phone, '03001234567');

      final pro = await SuperAdmin.issue(type: 'act', device: lic.deviceCode, plan: 'pro', expires: nowMs() + 86400000 * 30);
      await lic.apply(pro);
      expect(lic.planKey, 'pro');
      expect(lic.has('voice'), isTrue);
      expect(lic.daysLeft, inInclusiveRange(29, 30));
    });

    test('credit codes work once and credits can be spent', () async {
      final before = lic.credits;
      final code = await SuperAdmin.issue(type: 'cred', device: lic.deviceCode, credits: 50);
      await lic.apply(code);
      expect(lic.credits, before + 50);
      await expectLater(lic.apply(code), throwsStateError);
      await lic.spend(1, 'test');
      expect(lic.credits, before + 49);
      await expectLater(lic.spend(100000, 'too much'), throwsStateError);
    });
  });

  group('voice parser', () {
    final products = [
      Product(id: '1', name: 'Rice'),
      Product(id: '2', name: 'Sugar', unit: 'kg'),
      Product(id: '3', name: 'Milk Pack'),
      Product(id: '4', name: 'Basmati Rice'),
      Product(id: '5', name: 'Cheeni'),
      Product(id: '6', name: 'Shirt', variantName: 'Red / M', parentId: 'x'),
    ];

    VoiceCommand? p(String s) => VoiceParser.parse(s, products);

    test('English phrases', () {
      final a = p('sugar 10 kg add')!;
      expect([a.product.id, a.action, a.qty], ['2', 'add', 10]);
      final b = p('remove 2 milk')!;
      expect([b.product.id, b.action, b.qty], ['3', 'remove', 2]);
      final c = p('add basmati rice 5')!;
      expect([c.product.id, c.qty], ['4', 5]);
      final d = p('count rice 25')!;
      expect([d.product.id, d.action, d.qty], ['1', 'set', 25]);
      expect(p('add 10kg sugar')!.qty, 10);
      expect(p('add two sugar')!.qty, 2);
    });

    test('Roman Urdu and Urdu digits', () {
      final a = p('cheeni das kilo jama karo')!;
      expect([a.product.id, a.action, a.qty], ['5', 'add', 10]);
      final b = p('sugar ۵ nikalo')!;
      expect([b.product.id, b.action, b.qty], ['2', 'remove', 5]);
    });

    test('variants and nothing matched', () {
      expect(p('add 3 shirt red')!.product.id, '6');
      expect(p('hello there'), isNull);
      expect(p(''), isNull);
    });
  });
}
