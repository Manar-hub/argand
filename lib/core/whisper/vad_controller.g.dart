// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vad_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether whisper.cpp is told to transcribe only the speech regions of a file.

@ProviderFor(SilenceSkippingEnabled)
final silenceSkippingEnabledProvider = SilenceSkippingEnabledProvider._();

/// Whether whisper.cpp is told to transcribe only the speech regions of a file.
final class SilenceSkippingEnabledProvider
    extends $AsyncNotifierProvider<SilenceSkippingEnabled, bool> {
  /// Whether whisper.cpp is told to transcribe only the speech regions of a file.
  SilenceSkippingEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'silenceSkippingEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$silenceSkippingEnabledHash();

  @$internal
  @override
  SilenceSkippingEnabled create() => SilenceSkippingEnabled();
}

String _$silenceSkippingEnabledHash() =>
    r'82b30270209ec2bce053ea804d20381355b73c8e';

/// Whether whisper.cpp is told to transcribe only the speech regions of a file.

abstract class _$SilenceSkippingEnabled extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
