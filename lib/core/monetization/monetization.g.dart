// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monetization.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether Pro is owned.

@ProviderFor(proUnlocked)
final proUnlockedProvider = ProUnlockedProvider._();

/// Whether Pro is owned.

final class ProUnlockedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether Pro is owned.
  ProUnlockedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'proUnlockedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$proUnlockedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return proUnlocked(ref);
  }
}

String _$proUnlockedHash() => r'550d68d1e6325a7a3ab13bb0bd4e454c8231ab78';
