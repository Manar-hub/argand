// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'layer_transcription_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Transcribes exactly the stretch of timeline a layer covers.

@ProviderFor(LayerTranscriptionController)
final layerTranscriptionControllerProvider =
    LayerTranscriptionControllerFamily._();

/// Transcribes exactly the stretch of timeline a layer covers.
final class LayerTranscriptionControllerProvider
    extends
        $NotifierProvider<
          LayerTranscriptionController,
          LayerTranscriptionStatus
        > {
  /// Transcribes exactly the stretch of timeline a layer covers.
  LayerTranscriptionControllerProvider._({
    required LayerTranscriptionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'layerTranscriptionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$layerTranscriptionControllerHash();

  @override
  String toString() {
    return r'layerTranscriptionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LayerTranscriptionController create() => LayerTranscriptionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LayerTranscriptionStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LayerTranscriptionStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LayerTranscriptionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$layerTranscriptionControllerHash() =>
    r'51320aaefb0d432d31015ecd85b1c7cc40010d7a';

/// Transcribes exactly the stretch of timeline a layer covers.

final class LayerTranscriptionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          LayerTranscriptionController,
          LayerTranscriptionStatus,
          LayerTranscriptionStatus,
          LayerTranscriptionStatus,
          String
        > {
  LayerTranscriptionControllerFamily._()
    : super(
        retry: null,
        name: r'layerTranscriptionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Transcribes exactly the stretch of timeline a layer covers.

  LayerTranscriptionControllerProvider call(String layerId) =>
      LayerTranscriptionControllerProvider._(argument: layerId, from: this);

  @override
  String toString() => r'layerTranscriptionControllerProvider';
}

/// Transcribes exactly the stretch of timeline a layer covers.

abstract class _$LayerTranscriptionController
    extends $Notifier<LayerTranscriptionStatus> {
  late final _$args = ref.$arg as String;
  String get layerId => _$args;

  LayerTranscriptionStatus build(String layerId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<LayerTranscriptionStatus, LayerTranscriptionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LayerTranscriptionStatus, LayerTranscriptionStatus>,
              LayerTranscriptionStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
