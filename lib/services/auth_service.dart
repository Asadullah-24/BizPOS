import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/db.dart';
import '../models/models.dart';

class AuthService {
  static String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static String hashPin(String pin, String salt) {
    var bytes = utf8.encode('$salt:$pin');
    var digest = sha256.convert(bytes);
    for (var i = 0; i < 5000; i++) {
      digest = sha256.convert([...digest.bytes, ...bytes]);
    }
    return digest.toString();
  }

  static DbRow pinColumns(String pin) {
    final salt = _salt();
    return {'pin_salt': salt, 'pin_hash': hashPin(pin, salt)};
  }

  /// Finds the active employee whose PIN matches.
  static Future<Employee?> login(String pin) async {
    final rows = await Db.instance.s.q(
      'SELECT * FROM employees WHERE deleted_at IS NULL AND active = 1',
    );
    for (final r in rows) {
      final salt = r['pin_salt'] as String?;
      final hash = r['pin_hash'] as String?;
      if (salt == null || hash == null) continue;
      if (hashPin(pin, salt) == hash) return Employee.fromRow(r);
    }
    return null;
  }

  /// True when another active employee already uses this PIN.
  static Future<bool> pinTaken(String pin, {String? exceptId}) async {
    final rows = await Db.instance.s.q(
      'SELECT id, pin_salt, pin_hash FROM employees WHERE deleted_at IS NULL AND active = 1',
    );
    for (final r in rows) {
      if (r['id'] == exceptId) continue;
      final salt = r['pin_salt'] as String?;
      if (salt != null && hashPin(pin, salt) == r['pin_hash']) return true;
    }
    return false;
  }
}
