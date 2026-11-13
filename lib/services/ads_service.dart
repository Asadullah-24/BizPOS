import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/license.dart';
import '../core/packages.dart';

/// Rewarded ads that give voice credits. Needs internet.
///
/// The ad unit ids below are Google's public test ids. Replace them with your
/// own AdMob ids (and the App ID in AndroidManifest.xml / Info.plist, see
/// tool/patch_platforms.py) before publishing.
class AdsService {
  static const _androidRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _iosRewarded = 'ca-app-pub-3940256099942544/1712485313';

  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  /// Shows a rewarded ad. Returns the credits earned (0 if the ad was closed early).
  static Future<int> watchForCredits() async {
    final lic = LicenseService.instance;
    if (await lic.adsWatchedToday() >= Credits.adsPerDay) {
      throw StateError('Daily ad limit reached. Try again tomorrow or buy credits.');
    }
    await _init();
    final loaded = Completer<RewardedAd>();
    await RewardedAd.load(
      adUnitId: Platform.isIOS ? _iosRewarded : _androidRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) => loaded.completeError(StateError('No ad available right now (${e.message}). Check the internet.')),
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('The ad took too long to load. Try again.'),
    );
    final done = Completer<int>();
    var earned = 0;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        if (!done.isCompleted) done.completeError(StateError('The ad could not be shown.'));
      },
    );
    await ad.show(onUserEarnedReward: (_, __) async {
      earned = Credits.perAd;
      await lic.earn(Credits.perAd.toDouble(), 'Rewarded ad');
    });
    return done.future;
  }
}
