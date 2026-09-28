// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placeholder_ad_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where rewarded ads come from: Google AdMob, and the built-in test ad below
/// whenever AdMob has none to show (`FallbackRewardedAds`).

@ProviderFor(rewardedAds)
final rewardedAdsProvider = RewardedAdsProvider._();

/// Where rewarded ads come from: Google AdMob, and the built-in test ad below
/// whenever AdMob has none to show (`FallbackRewardedAds`).

final class RewardedAdsProvider
    extends $FunctionalProvider<RewardedAds, RewardedAds, RewardedAds>
    with $Provider<RewardedAds> {
  /// Where rewarded ads come from: Google AdMob, and the built-in test ad below
  /// whenever AdMob has none to show (`FallbackRewardedAds`).
  RewardedAdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rewardedAdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rewardedAdsHash();

  @$internal
  @override
  $ProviderElement<RewardedAds> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RewardedAds create(Ref ref) {
    return rewardedAds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RewardedAds value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RewardedAds>(value),
    );
  }
}

String _$rewardedAdsHash() => r'34c325f1bf94f868ae745fcc78b089d778e55730';
