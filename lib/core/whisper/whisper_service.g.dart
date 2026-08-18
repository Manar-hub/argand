// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'whisper_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(whisperService)
final whisperServiceProvider = WhisperServiceProvider._();

final class WhisperServiceProvider
    extends $FunctionalProvider<WhisperService, WhisperService, WhisperService>
    with $Provider<WhisperService> {
  WhisperServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'whisperServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$whisperServiceHash();

  @$internal
  @override
  $ProviderElement<WhisperService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WhisperService create(Ref ref) {
    return whisperService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WhisperService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WhisperService>(value),
    );
  }
}

String _$whisperServiceHash() => r'1266930a74c7d76fe63ca3a935a92d3db6e1d2de';
