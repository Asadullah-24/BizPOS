import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprint / face unlock for the lock screen.
///
/// The setting is stored per device (not synced): it remembers which
/// employee unlocked with biometrics on this phone. The PIN always keeps
/// working as a fallback.
class BiometricService {
  BiometricService._();

  static const _key = 'biometric_employee';
  static final LocalAuthentication _auth = LocalAuthentication();

  /// True when the phone has a fingerprint or face enrolled.
  static Future<bool> available() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the system fingerprint / face prompt. Returns true on success.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static const _listKey = 'biometric_employees';
  static const _lastKey = 'biometric_last';

  /// Employees (owner and staff) who unlock with fingerprint on this phone.
  static Future<List<String>> enrolled() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_listKey) ?? [];
    final old = p.getString(_key);
    if (old != null) {
      if (!list.contains(old)) list.add(old);
      await p.setStringList(_listKey, list);
      await p.remove(_key);
    }
    return list;
  }

  static Future<bool> isEnrolled(String employeeId) async => (await enrolled()).contains(employeeId);

  static Future<void> enroll(String employeeId) async {
    final p = await SharedPreferences.getInstance();
    final list = await enrolled();
    if (!list.contains(employeeId)) list.add(employeeId);
    await p.setStringList(_listKey, list);
  }

  static Future<void> remove(String employeeId) async {
    final p = await SharedPreferences.getInstance();
    final list = await enrolled()..remove(employeeId);
    await p.setStringList(_listKey, list);
  }

  /// Who unlocked with fingerprint last (asked first on the lock screen).
  static Future<String?> last() async => (await SharedPreferences.getInstance()).getString(_lastKey);

  static Future<void> setLast(String employeeId) async =>
      (await SharedPreferences.getInstance()).setString(_lastKey, employeeId);

  /// Whether this employee was already offered fingerprint unlock.
  static Future<bool> offered(String employeeId) async =>
      (await SharedPreferences.getInstance()).getBool('biometric_offered_$employeeId') ?? false;

  static Future<void> markOffered(String employeeId) async =>
      (await SharedPreferences.getInstance()).setBool('biometric_offered_$employeeId', true);
}
