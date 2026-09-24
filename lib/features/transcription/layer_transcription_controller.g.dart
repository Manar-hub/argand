// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'layer_transcription_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Transcribes exactly the stretch of timeline a layer covers.
///
/// **A layer is a request; this is what answers it.** The layer says which
/// audio matters, and a run here produces one transcript per clip the layer
/// overlaps — never one per layer, because word timings are relative to a
/// clip's own media and a single transcript spanning two clips would have no
/// coherent timebase.
///
/// Clips are run **one after another, never in parallel**. Two whisper
/// contexts is not a throughput win on a phone, and the emulator already dies
/// at three sequential runs; a layer covering four clips would be four at
/// once. Each transcript is committed as it lands, so a failure part-way keeps
/// what already succeeded. A failed run costs the attempt and nothing else:
/// the clips still play and the layer still stands, so the action can simply
/// be taken again -- the same reasoning import uses for not rolling back a
/// clip that is already committed.
///
/// Two engine properties leak through here and are worth knowing:
///
/// - **Language auto-detection reads only the opening ~30s** of whatever it is
///   given, so two layers over one clip can independently detect different
///   languages. Pinning the language in settings avoids it.
/// - **Speaker numbers come from each diarization run** and are cluster
///   indices with meaning only inside it. They already did not correspond
///   across clips; with layers they no longer correspond *within* one either.

@ProviderFor(LayerTranscriptionController)
final layerTranscriptionControllerProvider =
    LayerTranscriptionControllerFamily._();

/// Transcribes exactly the stretch of timeline a layer covers.
///
/// **A layer is a request; this is what answers it.** The layer says which
/// audio matters, and a run here produces one transcript per clip the layer
/// overlaps — never one per layer, because word timings are relative to a
/// clip's own media and a single transcript spanning two clips would have no
/// coherent timebase.
///
/// Clips are run **one after another, never in parallel**. Two whisper
/// contexts is not a throughput win on a phone, and the emulator already dies
/// at three sequential runs; a layer covering four clips would be four at
/// once. Each transcript is committed as it lands, so a failure part-way keeps
/// what already succeeded. A failed run costs the attempt and nothing else:
/// the clips still play and the layer still stands, so the action can simply
/// be taken again -- the same reasoning import uses for not rolling back a
/// clip that is already committed.
///
/// Two engine properties leak through here and are worth knowing:
///
/// - **Language auto-detection reads only the opening ~30s** of whatever it is
///   given, so two layers over one clip can independently detect different
///   languages. Pinning the language in settings avoids it.
/// - **Speaker numbers come from each diarization run** and are cluster
///   indices with meaning only inside it. They already did not correspond
///   across clips; with layers they no longer correspond *within* one either.
final class LayerTranscriptionControllerProvider
    extends
        $NotifierProvider<
          LayerTranscriptionController,
          LayerTranscriptionStatus
        > {
  /// Transcribes exactly the stretch of timeline a layer covers.
  ///
  /// **A layer is a request; this is what answers it.** The layer says which
  /// audio matters, and a run here produces one transcript per clip the layer
  /// overlaps — never one per layer, because word timings are relative to a
  /// clip's own media and a single transcript spanning two clips would have no
  /// coherent timebase.
  ///
  /// Clips are run **one after another, never in parallel**. Two whisper
  /// contexts is not a throughput win on a phone, and the emulator already dies
  /// at three sequential runs; a layer covering four clips would be four at
  /// once. Each transcript is committed as it lands, so a failure part-way keeps
  /// what already succeeded. A failed run costs the attempt and nothing else:
  /// the clips still play and the layer still stands, so the action can simply
  /// be taken again -- the same reasoning import uses for not rolling back a
  /// clip that is already committed.
  ///
  /// Two engine properties leak through here and are worth knowing:
  ///
  /// - **Language auto-detection reads only the opening ~30s** of whatever it is
  ///   given, so two layers over one clip can independently detect different
  ///   languages. Pinning the language in settings avoids it.
  /// - **Speaker numbers come from each diarization run** and are cluster
  ///   indices with meaning only inside it. They already did not correspond
  ///   across clips; with layers they no longer correspond *within* one either.
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
    r'e2cf9f65e754738c8bf65b84a43f84a59c9ceeb8';

/// Transcribes exactly the stretch of timeline a layer covers.
///
/// **A layer is a request; this is what answers it.** The layer says which
/// audio matters, and a run here produces one transcript per clip the layer
/// overlaps — never one per layer, because word timings are relative to a
/// clip's own media and a single transcript spanning two clips would have no
/// coherent timebase.
///
/// Clips are run **one after another, never in parallel**. Two whisper
/// contexts is not a throughput win on a phone, and the emulator already dies
/// at three sequential runs; a layer covering four clips would be four at
/// once. Each transcript is committed as it lands, so a failure part-way keeps
/// what already succeeded. A failed run costs the attempt and nothing else:
/// the clips still play and the layer still stands, so the action can simply
/// be taken again -- the same reasoning import uses for not rolling back a
/// clip that is already committed.
///
/// Two engine properties leak through here and are worth knowing:
///
/// - **Language auto-detection reads only the opening ~30s** of whatever it is
///   given, so two layers over one clip can independently detect different
///   languages. Pinning the language in settings avoids it.
/// - **Speaker numbers come from each diarization run** and are cluster
///   indices with meaning only inside it. They already did not correspond
///   across clips; with layers they no longer correspond *within* one either.

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
  ///
  /// **A layer is a request; this is what answers it.** The layer says which
  /// audio matters, and a run here produces one transcript per clip the layer
  /// overlaps — never one per layer, because word timings are relative to a
  /// clip's own media and a single transcript spanning two clips would have no
  /// coherent timebase.
  ///
  /// Clips are run **one after another, never in parallel**. Two whisper
  /// contexts is not a throughput win on a phone, and the emulator already dies
  /// at three sequential runs; a layer covering four clips would be four at
  /// once. Each transcript is committed as it lands, so a failure part-way keeps
  /// what already succeeded. A failed run costs the attempt and nothing else:
  /// the clips still play and the layer still stands, so the action can simply
  /// be taken again -- the same reasoning import uses for not rolling back a
  /// clip that is already committed.
  ///
  /// Two engine properties leak through here and are worth knowing:
  ///
  /// - **Language auto-detection reads only the opening ~30s** of whatever it is
  ///   given, so two layers over one clip can independently detect different
  ///   languages. Pinning the language in settings avoids it.
  /// - **Speaker numbers come from each diarization run** and are cluster
  ///   indices with meaning only inside it. They already did not correspond
  ///   across clips; with layers they no longer correspond *within* one either.

  LayerTranscriptionControllerProvider call(String layerId) =>
      LayerTranscriptionControllerProvider._(argument: layerId, from: this);

  @override
  String toString() => r'layerTranscriptionControllerProvider';
}

/// Transcribes exactly the stretch of timeline a layer covers.
///
/// **A layer is a request; this is what answers it.** The layer says which
/// audio matters, and a run here produces one transcript per clip the layer
/// overlaps — never one per layer, because word timings are relative to a
/// clip's own media and a single transcript spanning two clips would have no
/// coherent timebase.
///
/// Clips are run **one after another, never in parallel**. Two whisper
/// contexts is not a throughput win on a phone, and the emulator already dies
/// at three sequential runs; a layer covering four clips would be four at
/// once. Each transcript is committed as it lands, so a failure part-way keeps
/// what already succeeded. A failed run costs the attempt and nothing else:
/// the clips still play and the layer still stands, so the action can simply
/// be taken again -- the same reasoning import uses for not rolling back a
/// clip that is already committed.
///
/// Two engine properties leak through here and are worth knowing:
///
/// - **Language auto-detection reads only the opening ~30s** of whatever it is
///   given, so two layers over one clip can independently detect different
///   languages. Pinning the language in settings avoids it.
/// - **Speaker numbers come from each diarization run** and are cluster
///   indices with meaning only inside it. They already did not correspond
///   across clips; with layers they no longer correspond *within* one either.

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
