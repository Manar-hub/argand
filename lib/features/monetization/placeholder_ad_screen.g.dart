// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'placeholder_ad_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where rewarded ads come from.
///
/// The placeholder until an ad SDK is chosen. Kept alive because it holds no
/// state worth rebuilding and is asked for on every export.

@ProviderFor(rewardedAds)
final rewardedAdsProvider = RewardedAdsProvider._();

/// Where rewarded ads come from.
///
/// The placeholder until an ad SDK is chosen. Kept alive because it holds no
/// state worth rebuilding and is asked for on every export.

final class RewardedAdsProvider
    extends $FunctionalProvider<RewardedAds, RewardedAds, RewardedAds>
    with $Provider<RewardedAds> {
  /// Where rewarded ads come from.
  ///
  /// The placeholder until an ad SDK is chosen. Kept alive because it holds no
  /// state worth rebuilding and is asked for on every export.
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

String _$rewardedAdsHash() => r'2689d158e7febb575555817e71f78e3483d9e046';
