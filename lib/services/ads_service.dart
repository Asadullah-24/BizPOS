import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/access.dart';

/// AdMob for the free tier: banner ads, and rewarded ads that unlock one paid
/// feature for 24 hours. Needs internet.
///
/// The ids below are Google's public test ids. Replace them with your own AdMob
/// ids (and the App ID in tool/patch_platforms.py) before publishing.
class AdsService {
  static const _androidRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _iosRewarded = 'ca-app-pub-3940256099942544/1712485313';
  static const _androidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _iosBanner = 'ca-app-pub-3940256099942544/2934735716';

  /// Turned off in tests (no ad SDK there).
  static bool disabled = false;

  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  static String get bannerUnit => Platform.isIOS ? _iosBanner : _androidBanner;

  /// Shows a rewarded ad. Returns true when the user watched it to the end.
  static Future<bool> showRewarded() async {
    if (disabled) return false;
    await _init();
    final loaded = Completer<RewardedAd>();
    await RewardedAd.load(
      adUnitId: Platform.isIOS ? _iosRewarded : _androidRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) => loaded.completeError(StateError('No ad available right now. Check the internet and try again.')),
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('The ad took too long to load. Try again.'),
    );
    final done = Completer<bool>();
    var earned = false;
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
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }

  /// Watch an ad to use [feature] for 24 hours.
  static Future<bool> unlock(String feature) async {
    final ok = await showRewarded();
    if (ok) Access.instance.grantUnlock(feature);
    return ok;
  }
}

/// Small banner shown to free shops. Shows nothing offline or for paid shops.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (AdsService.disabled) return;
    AdsService._init().then((_) {
      if (!mounted) return;
      _ad = BannerAd(
        adUnitId: AdsService.bannerUnit,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) => ad.dispose(),
        ),
      )..load();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(height: ad.size.height.toDouble(), width: ad.size.width.toDouble(), child: AdWidget(ad: ad));
  }
}
