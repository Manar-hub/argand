// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchases.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(proPurchases)
final proPurchasesProvider = ProPurchasesProvider._();

final class ProPurchasesProvider
    extends $FunctionalProvider<ProPurchases, ProPurchases, ProPurchases>
    with $Provider<ProPurchases> {
  ProPurchasesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proPurchasesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proPurchasesHash();

  @$internal
  @override
  $ProviderElement<ProPurchases> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProPurchases create(Ref ref) {
    return proPurchases(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProPurchases value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProPurchases>(value),
    );
  }
}

String _$proPurchasesHash() => r'f520c7371c93632e2059ac7c61ee59982b3de9ec';
