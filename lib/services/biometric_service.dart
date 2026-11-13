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

  /// Employee id enrolled for biometric unlock on this device, or null.
  static Future<String?> enrolledEmployee() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_key);
  }

  static Future<void> enroll(String employeeId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, employeeId);
  }

  static Future<void> disable() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
