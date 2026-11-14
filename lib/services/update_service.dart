import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/db.dart';
import '../core/ids.dart';
import 'cloud_service.dart';

/// App updates set by the super admin in settings/app:
///   latestVersion   e.g. "1.3.0": phones on an older version see "Update available"
///   minVersion      e.g. "1.2.0": phones below this must update before using the app
///   updateMessage   what is new, shown on the update card
///   apkUrl          download link for phones that installed the APK directly
///   appStoreUrl     App Store link for iPhones
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const packageName = 'com.bizpos.bizpos';
  static const playUrl = 'https://play.google.com/store/apps/details?id=$packageName';
  static const defaultApkUrl = 'https://github.com/Asadullah-24/BizPOS/releases/download/latest/BizPOS.apk';

  String version = '';
  String build = '';
  bool fromPlay = false;

  /// Play Store reports a newer build (Android installs from Play only).
  bool playHasUpdate = false;

  /// "Later" was tapped for this version during this session.
  bool _snoozed = false;

  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
      fromPlay = !kIsWeb && Platform.isAndroid && info.installerStore == 'com.android.vending';
    } catch (_) {}
    if (fromPlay) {
      try {
        final u = await InAppUpdate.checkForUpdate();
        playHasUpdate = u.updateAvailability == UpdateAvailability.updateAvailable;
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Compares "1.10.2" style versions: negative when [a] is older than [b].
  static int compare(String a, String b) {
    List<int> parts(String v) => v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  Map<String, dynamic> get _s => CloudService.instance.appSettings;
  String get latest => '${_s['latestVersion'] ?? ''}'.trim();
  String get minimum => '${_s['minVersion'] ?? ''}'.trim();
  String get message => '${_s['updateMessage'] ?? ''}'.trim();

  /// This version can no longer be used.
  bool get mustUpdate => CloudService.instance.settingsLive && version.isNotEmpty && minimum.isNotEmpty && compare(version, minimum) < 0;

  /// A newer version exists and the user may update now or later.
  bool get canUpdate {
    if (version.isEmpty || mustUpdate || _snoozed) return false;
    if (CloudService.instance.settingsLive && latest.isNotEmpty && compare(version, latest) < 0) {
      final key = 'update_later_$latest';
      final at = Local.prefs.getInt(key) ?? 0;
      return nowMs() - at > 24 * 3600000;
    }
    return playHasUpdate;
  }

  Future<void> later() async {
    _snoozed = true;
    if (latest.isNotEmpty) await Local.prefs.setInt('update_later_$latest', nowMs());
    notifyListeners();
  }

  /// Opens the right place to update: Google's in-app update for Play installs,
  /// the App Store on iPhone, otherwise the APK download link.
  Future<void> update() async {
    if (fromPlay) {
      try {
        final u = await InAppUpdate.checkForUpdate();
        if (u.updateAvailability == UpdateAvailability.updateAvailable) {
          if (mustUpdate || u.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
          } else {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
          }
          return;
        }
      } catch (_) {}
      await launchUrl(Uri.parse(playUrl), mode: LaunchMode.externalApplication);
      return;
    }
    if (!kIsWeb && Platform.isIOS) {
      final url = '${_s['appStoreUrl'] ?? ''}'.trim();
      if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final apk = '${_s['apkUrl'] ?? ''}'.trim();
    await launchUrl(Uri.parse(apk.isEmpty ? defaultApkUrl : apk), mode: LaunchMode.externalApplication);
  }
}
