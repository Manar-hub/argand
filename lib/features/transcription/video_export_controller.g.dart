// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_export_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Renders the project's clips into a single MP4 in the device's Downloads.

@ProviderFor(VideoExportController)
final videoExportControllerProvider = VideoExportControllerFamily._();

/// Renders the project's clips into a single MP4 in the device's Downloads.
final class VideoExportControllerProvider
    extends $NotifierProvider<VideoExportController, VideoExportStatus> {
  /// Renders the project's clips into a single MP4 in the device's Downloads.
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
    r'0ba7946b64b8fdee631ea8b318da569cc39c326a';

/// Renders the project's clips into a single MP4 in the device's Downloads.

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

  VideoExportControllerProvider call(String projectId) =>
      VideoExportControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'videoExportControllerProvider';
}

/// Renders the project's clips into a single MP4 in the device's Downloads.

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
