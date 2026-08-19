// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_player_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).

@ProviderFor(MediaPlayer)
final mediaPlayerProvider = MediaPlayerFamily._();

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
final class MediaPlayerProvider
    extends $AsyncNotifierProvider<MediaPlayer, VideoPlayerController> {
  /// Owns the platform media player for one project.
  ///
  /// Lives in a provider rather than in the screen's state so that tap-to-seek
  /// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
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

String _$mediaPlayerHash() => r'3a29d71a0ef1ade4ad2c1156cfb5ed92ba08f3e2';

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).

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

  /// Owns the platform media player for one project.
  ///
  /// Lives in a provider rather than in the screen's state so that tap-to-seek
  /// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).

  MediaPlayerProvider call(String mediaPath) =>
      MediaPlayerProvider._(argument: mediaPath, from: this);

  @override
  String toString() => r'mediaPlayerProvider';
}

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).

abstract class _$MediaPlayer extends $AsyncNotifier<VideoPlayerController> {
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
