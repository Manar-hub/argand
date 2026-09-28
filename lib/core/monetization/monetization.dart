import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'monetization.g.dart';

/// Permission to render one video without the watermark.
sealed class WatermarkWaiver {
  const WatermarkWaiver._();

  /// For tests that need an unbranded render without playing an ad.
  @visibleForTesting
  const factory WatermarkWaiver.forTesting() = _TestWaiver;
}

final class _ProWaiver extends WatermarkWaiver {
  const _ProWaiver() : super._();
}

final class _AdRewardWaiver extends WatermarkWaiver {
  const _AdRewardWaiver() : super._();
}

final class _TestWaiver extends WatermarkWaiver {
  const _TestWaiver() : super._();
}

/// The `Settings` key that marks Pro as owned.
const String proUnlockedKey = 'pro.unlocked';

/// Whether Pro is owned.
@riverpod
Future<bool> proUnlocked(Ref ref) async {
  final value = await ref.watch(appDatabaseProvider).readSetting(proUnlockedKey);
  return value == 'true';
}

/// The waiver Pro grants, or null when Pro is not owned.
Future<WatermarkWaiver?> claimProWaiver(AppDatabase db) async {
  final value = await db.readSetting(proUnlockedKey);
  return value == 'true' ? const _ProWaiver() : null;
}

/// How a rewarded ad ended.
sealed class RewardedAdOutcome {
  const RewardedAdOutcome();
}

/// Watched to the end: the one outcome that removes the watermark.
final class AdRewarded extends RewardedAdOutcome {
  const AdRewarded._(this.waiver);

  final WatermarkWaiver waiver;
}

/// Closed before it finished. Nothing is granted, and nothing is exported.
final class AdDismissed extends RewardedAdOutcome {
  const AdDismissed();
}

/// No ad could be loaded: offline, or the network had nothing to show.
final class AdUnavailable extends RewardedAdOutcome {
  const AdUnavailable();
}

/// A source of rewarded ads.
abstract interface class RewardedAds {
  /// Whether an ad could plausibly be shown right now.
  Future<bool> canLoad();

  /// Plays an ad and reports how it ended.
  Future<RewardedAdOutcome> show(BuildContext context);
}

/// Loads a real ad network's rewarded ad -- Google AdMob in the app
/// (`admob_rewarded_source.dart`), a fake in tests.
abstract interface class RewardedAdSource {
  /// A loaded ad, or null when none could be: offline, no fill, timed out.
  Future<LoadedRewardedAd?> load();
}

/// One loaded rewarded ad, shown at most once.
abstract interface class LoadedRewardedAd {
  /// Shows it full screen; true when the reward was earned before it closed.
  Future<bool> present();
}

/// [RewardedAds] on a real ad network.
class SdkRewardedAds implements RewardedAds {
  SdkRewardedAds(this.source);

  final RewardedAdSource source;

  LoadedRewardedAd? _ready;
  Future<LoadedRewardedAd?>? _loading;

  /// When the network last had nothing. Within [_retryAfter] of it, [show]
  /// says so at once instead of making the user wait through another
  /// failing load -- a fallback, if there is one, plays straight away.
  DateTime? _failedAt;
  static const _retryAfter = Duration(minutes: 1);

  Future<LoadedRewardedAd?> _load() {
    final loading = _loading ??= source.load().then((ad) {
      _ready = ad;
      _failedAt = ad == null ? DateTime.now() : null;
      return ad;
    });
    return loading.whenComplete(() => _loading = null);
  }

  bool get _recentlyFailed {
    final failedAt = _failedAt;
    return failedAt != null &&
        DateTime.now().difference(failedAt) < _retryAfter;
  }

  @override
  Future<bool> canLoad() async => (_ready ?? await _load()) != null;

  @override
  Future<RewardedAdOutcome> show(BuildContext context) async {
    if (_ready == null && _recentlyFailed) return const AdUnavailable();
    final ad = _ready ?? await _load();
    _ready = null;
    if (ad == null) return const AdUnavailable();
    final earned = await ad.present();
    // The next one, so a second export does not wait either.
    unawaited(_load());
    return earned
        ? const AdRewarded._(_AdRewardWaiver())
        : const AdDismissed();
  }
}

/// A network's ad first, our own when it has none.
class FallbackRewardedAds implements RewardedAds {
  FallbackRewardedAds({required this.primary, required this.fallback});

  final RewardedAds primary;
  final RewardedAds fallback;

  @override
  Future<bool> canLoad() async =>
      await primary.canLoad() || await fallback.canLoad();

  @override
  Future<RewardedAdOutcome> show(BuildContext context) async {
    final outcome = await primary.show(context);
    if (outcome is! AdUnavailable || !context.mounted) return outcome;
    return fallback.show(context);
  }
}

/// Checks whether the device can reach the network at all.
typedef ReachabilityProbe = Future<bool> Function();

/// Puts an ad on screen and answers whether it was watched to the end.
typedef AdPresenter = Future<bool> Function(BuildContext context);

/// Stands in for a real rewarded ad until an ad SDK is wired.
class PlaceholderRewardedAds implements RewardedAds {
  PlaceholderRewardedAds({
    required this.present,
    ReachabilityProbe? probe,
  }) : _probe = probe ?? isNetworkReachable;

  /// Puts the placeholder on screen.
  final AdPresenter present;

  final ReachabilityProbe _probe;

  @override
  Future<bool> canLoad() => _probe();

  @override
  Future<RewardedAdOutcome> show(BuildContext context) async {
    // Checked again here rather than trusted from an earlier [canLoad]: the
    // user can turn the toggle on and then walk out of signal before tapping
    // Export.
    if (!await _probe()) return const AdUnavailable();
    if (!context.mounted) return const AdDismissed();

    final watched = await present(context);
    return watched
        ? const AdRewarded._(_AdRewardWaiver())
        : const AdDismissed();
  }
}

/// A host to resolve when checking for a connection.
const String _reachabilityHost = 'example.com';

/// Whether a name can be resolved, which is what "online" means for loading an
/// ad.
Future<bool> isNetworkReachable() async {
  try {
    final addresses = await InternetAddress.lookup(_reachabilityHost)
        .timeout(const Duration(seconds: 3));
    return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
  } on SocketException catch (error) {
    // Logged because "offline" and "cannot resolve for some other reason"
    // look identical from the export sheet, and only one of them is real.
    debugPrint('Ad unavailable: lookup failed ($error)');
    return false;
  } on TimeoutException {
    debugPrint('Ad unavailable: lookup timed out');
    return false;
  }
}
