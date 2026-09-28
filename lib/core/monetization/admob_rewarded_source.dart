import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization.dart';

/// Rewarded ads from Google AdMob.
class AdMobRewardedSource implements RewardedAdSource {
  const AdMobRewardedSource();

  static const String testUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// How long an export waits for an ad before saying none is available.
  static const Duration _patience = Duration(seconds: 8);

  @override
  Future<LoadedRewardedAd?> load() {
    final loaded = Completer<LoadedRewardedAd?>();
    RewardedAd.load(
      adUnitId: testUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // Arrived after the wait was given up: nobody will show it.
          if (loaded.isCompleted) {
            ad.dispose();
          } else {
            loaded.complete(_AdMobRewardedAd(ad));
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('AdMob: no rewarded ad (${error.code}: ${error.message})');
          if (!loaded.isCompleted) loaded.complete(null);
        },
      ),
    );
    return loaded.future.timeout(_patience, onTimeout: () => null);
  }
}

class _AdMobRewardedAd implements LoadedRewardedAd {
  _AdMobRewardedAd(this._ad);

  final RewardedAd _ad;

  @override
  Future<bool> present() {
    final closed = Completer<bool>();
    var earned = false;
    _ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdMob: could not show (${error.message})');
        ad.dispose();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    _ad.show(onUserEarnedReward: (_, _) => earned = true);
    return closed.future;
  }
}
