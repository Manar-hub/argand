// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_player_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the platform decoder for one media file.

@ProviderFor(MediaController)
final mediaControllerProvider = MediaControllerFamily._();

/// Owns the platform decoder for one media file.
final class MediaControllerProvider
    extends $AsyncNotifierProvider<MediaController, VideoPlayerController> {
  /// Owns the platform decoder for one media file.
  MediaControllerProvider._({
    required MediaControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mediaControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaControllerHash();

  @override
  String toString() {
    return r'mediaControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaController create() => MediaController();

  @override
  bool operator ==(Object other) {
    return other is MediaControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaControllerHash() => r'28d156d7ca8c0684242c2312c7857c5cff14cba0';

/// Owns the platform decoder for one media file.

final class MediaControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MediaController,
          AsyncValue<VideoPlayerController>,
          VideoPlayerController,
          FutureOr<VideoPlayerController>,
          String
        > {
  MediaControllerFamily._()
    : super(
        retry: null,
        name: r'mediaControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owns the platform decoder for one media file.

  MediaControllerProvider call(String mediaPath) =>
      MediaControllerProvider._(argument: mediaPath, from: this);

  @override
  String toString() => r'mediaControllerProvider';
}

/// Owns the platform decoder for one media file.

abstract class _$MediaController extends $AsyncNotifier<VideoPlayerController> {
  late final _$args = ref.$arg as String;
  String get mediaPath => _$args;

  FutureOr<VideoPlayerController> build(String mediaPath);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<VideoPlayerController>, VideoPlayerController>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<VideoPlayerController>,
                VideoPlayerController
              >,
              AsyncValue<VideoPlayerController>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The player for one clip.

@ProviderFor(MediaPlayer)
final mediaPlayerProvider = MediaPlayerFamily._();

/// The player for one clip.
final class MediaPlayerProvider
    extends $AsyncNotifierProvider<MediaPlayer, VideoPlayerController> {
  /// The player for one clip.
  MediaPlayerProvider._({
    required MediaPlayerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mediaPlayerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaPlayerHash();

  @override
  String toString() {
    return r'mediaPlayerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaPlayer create() => MediaPlayer();

  @override
  bool operator ==(Object other) {
    return other is MediaPlayerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaPlayerHash() => r'5ba5b63319dabd36824ec58219c827d6a759713c';

/// The player for one clip.

final class MediaPlayerFamily extends $Family
    with
        $ClassFamilyOverride<
          MediaPlayer,
          AsyncValue<VideoPlayerController>,
          VideoPlayerController,
          FutureOr<VideoPlayerController>,
          String
        > {
  MediaPlayerFamily._()
    : super(
        retry: null,
        name: r'mediaPlayerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The player for one clip.

  MediaPlayerProvider call(String clipId) =>
      MediaPlayerProvider._(argument: clipId, from: this);

  @override
  String toString() => r'mediaPlayerProvider';
}

/// The player for one clip.

abstract class _$MediaPlayer extends $AsyncNotifier<VideoPlayerController> {
  late final _$args = ref.$arg as String;
  String get clipId => _$args;

  FutureOr<VideoPlayerController> build(String clipId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<VideoPlayerController>, VideoPlayerController>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<VideoPlayerController>,
                VideoPlayerController
              >,
              AsyncValue<VideoPlayerController>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
