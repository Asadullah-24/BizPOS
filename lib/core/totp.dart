import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 time-based one-time passwords (Google Authenticator, Microsoft
/// Authenticator...). Works fully offline.
class Totp {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String newSecret() {
    final r = Random.secure();
    return base32Encode(List<int>.generate(20, (_) => r.nextInt(256)));
  }

  static String base32Encode(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List base32Decode(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in s.split('')) {
      buffer = (buffer << 5) | _alphabet.indexOf(ch);
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 255);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  /// Code for raw key bytes at [time] (seconds since epoch).
  static String codeForKey(List<int> key, int timeSeconds, {int digits = 6, int period = 30}) {
    var counter = timeSeconds ~/ period;
    final msg = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      msg[i] = counter & 0xff;
      counter >>= 8;
    }
    final h = Hmac(sha1, key).convert(msg).bytes;
    final offset = h[h.length - 1] & 0x0f;
    final bin = ((h[offset] & 0x7f) << 24) | ((h[offset + 1] & 0xff) << 16) | ((h[offset + 2] & 0xff) << 8) | (h[offset + 3] & 0xff);
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (bin % mod).toString().padLeft(digits, '0');
  }

  static String code(String secret, {DateTime? at}) =>
      codeForKey(base32Decode(secret), (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000);

  /// Accepts the current code and one step either side (clock drift).
  static bool verify(String secret, String code, {DateTime? at}) {
    final c = code.replaceAll(RegExp(r'\s'), '');
    if (c.length != 6) return false;
    final key = base32Decode(secret);
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    for (final step in [-1, 0, 1]) {
      if (codeForKey(key, now + step * 30) == c) return true;
    }
    return false;
  }

  static String uri({required String secret, required String account, String issuer = 'BizPOS'}) =>
      'otpauth://totp/${Uri.encodeComponent('$issuer:$account')}?secret=$secret&issuer=${Uri.encodeComponent(issuer)}&digits=6&period=30';
}
