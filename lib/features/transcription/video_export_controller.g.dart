// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_export_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Renders the project's clips into a single MP4 in the device's Downloads.
///
/// **This is Phase 9's first slice and deliberately renders nothing but the
/// clips.** Captions are not burned in, trims are not applied and no watermark
/// is composited, because none of those exist yet. The point of the slice is to
/// establish the export path itself — everything above depends on it, and the
/// shape of the operations that follow depends on what this turns out to cost.
///
/// **The file goes to the device's Downloads folder**, not app storage. An
/// export the user cannot open, share or find in a file manager is not an
/// export; where it lands is part of the feature, not an implementation detail.
///
/// One export at a time, enforced here *and* natively. A second encode competes
/// for the same hardware codec, which is the same reasoning that makes the
/// per-clip transcription runs sequential rather than parallel.

@ProviderFor(VideoExportController)
final videoExportControllerProvider = VideoExportControllerFamily._();

/// Renders the project's clips into a single MP4 in the device's Downloads.
///
/// **This is Phase 9's first slice and deliberately renders nothing but the
/// clips.** Captions are not burned in, trims are not applied and no watermark
/// is composited, because none of those exist yet. The point of the slice is to
/// establish the export path itself — everything above depends on it, and the
/// shape of the operations that follow depends on what this turns out to cost.
///
/// **The file goes to the device's Downloads folder**, not app storage. An
/// export the user cannot open, share or find in a file manager is not an
/// export; where it lands is part of the feature, not an implementation detail.
///
/// One export at a time, enforced here *and* natively. A second encode competes
/// for the same hardware codec, which is the same reasoning that makes the
/// per-clip transcription runs sequential rather than parallel.
final class VideoExportControllerProvider
    extends $NotifierProvider<VideoExportController, VideoExportStatus> {
  /// Renders the project's clips into a single MP4 in the device's Downloads.
  ///
  /// **This is Phase 9's first slice and deliberately renders nothing but the
  /// clips.** Captions are not burned in, trims are not applied and no watermark
  /// is composited, because none of those exist yet. The point of the slice is to
  /// establish the export path itself — everything above depends on it, and the
  /// shape of the operations that follow depends on what this turns out to cost.
  ///
  /// **The file goes to the device's Downloads folder**, not app storage. An
  /// export the user cannot open, share or find in a file manager is not an
  /// export; where it lands is part of the feature, not an implementation detail.
  ///
  /// One export at a time, enforced here *and* natively. A second encode competes
  /// for the same hardware codec, which is the same reasoning that makes the
  /// per-clip transcription runs sequential rather than parallel.
  VideoExportControllerProvider._({
    required VideoExportControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'videoExportControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$videoExportControllerHash();

  @override
  String toString() {
    return r'videoExportControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VideoExportController create() => VideoExportController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoExportStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoExportStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoExportControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$videoExportControllerHash() =>
    r'e63c4fe735df6e2570e99c3038a870c58d3a6ad6';

/// Renders the project's clips into a single MP4 in the device's Downloads.
///
/// **This is Phase 9's first slice and deliberately renders nothing but the
/// clips.** Captions are not burned in, trims are not applied and no watermark
/// is composited, because none of those exist yet. The point of the slice is to
/// establish the export path itself — everything above depends on it, and the
/// shape of the operations that follow depends on what this turns out to cost.
///
/// **The file goes to the device's Downloads folder**, not app storage. An
/// export the user cannot open, share or find in a file manager is not an
/// export; where it lands is part of the feature, not an implementation detail.
///
/// One export at a time, enforced here *and* natively. A second encode competes
/// for the same hardware codec, which is the same reasoning that makes the
/// per-clip transcription runs sequential rather than parallel.

final class VideoExportControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          VideoExportController,
          VideoExportStatus,
          VideoExportStatus,
          VideoExportStatus,
          String
        > {
  VideoExportControllerFamily._()
    : super(
        retry: null,
        name: r'videoExportControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Renders the project's clips into a single MP4 in the device's Downloads.
  ///
  /// **This is Phase 9's first slice and deliberately renders nothing but the
  /// clips.** Captions are not burned in, trims are not applied and no watermark
  /// is composited, because none of those exist yet. The point of the slice is to
  /// establish the export path itself — everything above depends on it, and the
  /// shape of the operations that follow depends on what this turns out to cost.
  ///
  /// **The file goes to the device's Downloads folder**, not app storage. An
  /// export the user cannot open, share or find in a file manager is not an
  /// export; where it lands is part of the feature, not an implementation detail.
  ///
  /// One export at a time, enforced here *and* natively. A second encode competes
  /// for the same hardware codec, which is the same reasoning that makes the
  /// per-clip transcription runs sequential rather than parallel.

  VideoExportControllerProvider call(String projectId) =>
      VideoExportControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'videoExportControllerProvider';
}

/// Renders the project's clips into a single MP4 in the device's Downloads.
///
/// **This is Phase 9's first slice and deliberately renders nothing but the
/// clips.** Captions are not burned in, trims are not applied and no watermark
/// is composited, because none of those exist yet. The point of the slice is to
/// establish the export path itself — everything above depends on it, and the
/// shape of the operations that follow depends on what this turns out to cost.
///
/// **The file goes to the device's Downloads folder**, not app storage. An
/// export the user cannot open, share or find in a file manager is not an
/// export; where it lands is part of the feature, not an implementation detail.
///
/// One export at a time, enforced here *and* natively. A second encode competes
/// for the same hardware codec, which is the same reasoning that makes the
/// per-clip transcription runs sequential rather than parallel.

abstract class _$VideoExportController extends $Notifier<VideoExportStatus> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  VideoExportStatus build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<VideoExportStatus, VideoExportStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<VideoExportStatus, VideoExportStatus>,
              VideoExportStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
