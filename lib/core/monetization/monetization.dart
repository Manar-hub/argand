import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'monetization.g.dart';

/// Permission to render one video without the watermark.
///
/// **Only this library can make one.** Every constructor is private, and the
/// two ways out are a finished rewarded ad and the Pro unlock. An export's
/// options carry a waiver rather than a boolean, so a UI path that wanted to
/// drop the watermark without either has nothing it could pass.
///
/// That is what "the user cannot bypass the ad" rests on. Going offline does
/// not skip the ad; it stops the ad from loading, and no loaded ad means no
/// waiver means the watermark stays. The toggle in the export sheet only says
/// what the user wants -- it never had the power to grant it.
sealed class WatermarkWaiver {
  const WatermarkWaiver._();

  /// For tests that need an unbranded render without playing an ad.
  ///
  /// The analyzer flags any use outside a test, which keeps this from becoming
  /// the bypass the class exists to prevent.
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
///
/// One global flag, as CLAUDE.md §2 specifies, so every Pro check is a single
/// read. Stored locally, which is why **Pro keeps working offline** -- the
/// purchase SDK caches its own entitlement for the same reason. Nothing writes
/// it yet: purchases are not connected.
const String proUnlockedKey = 'pro.unlocked';

/// Whether Pro is owned.
@riverpod
Future<bool> proUnlocked(Ref ref) async {
  final value = await ref.watch(appDatabaseProvider).readSetting(proUnlockedKey);
  return value == 'true';
}

/// The waiver Pro grants, or null when Pro is not owned.
///
/// Reads the flag itself rather than taking a boolean, so a caller cannot
/// claim Pro by passing `true`.
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
///
/// An interface because the real one does not exist yet. RevenueCat, the
/// intended purchase SDK, sells the Pro unlock and serves no ads, so rewarded
/// video needs its own SDK -- Google Mobile Ads is the obvious one. When it
/// arrives it replaces [PlaceholderRewardedAds] behind this interface and
/// nothing that calls it changes.
abstract interface class RewardedAds {
  /// Whether an ad could plausibly be shown right now.
  ///
  /// A hint for the interface, never the gate: the ad's own result from
  /// [show] is what decides, because the connection can drop between the
  /// two calls.
  Future<bool> canLoad();

  /// Plays an ad and reports how it ended.
  Future<RewardedAdOutcome> show(BuildContext context);
}

/// Checks whether the device can reach the network at all.
typedef ReachabilityProbe = Future<bool> Function();

/// Puts an ad on screen and answers whether it was watched to the end.
typedef AdPresenter = Future<bool> Function(BuildContext context);

/// Stands in for a real rewarded ad until an ad SDK is wired.
///
/// **Behaves like one where it matters.** It needs a network to "load", so
/// going offline makes the ad unavailable exactly as a real one would be, and
/// the watermark stays. Only watching it to the end mints a waiver.
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
///
/// Neutral rather than an ad network's own domain. This runs only after the
/// user has chosen to watch an ad, but a lookup of an advertising host is
/// still the kind of traffic a privacy-first app should not generate on a
/// placeholder's behalf. The real SDK does its own loading and replaces this.
const String _reachabilityHost = 'example.com';

/// Whether a name can be resolved, which is what "online" means for loading an
/// ad.
///
/// A DNS lookup rather than a connectivity package: it needs no dependency,
/// and it answers the actual question. Being attached to a Wi-Fi network with
/// no route out reports "connected" to the platform while loading nothing.
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
