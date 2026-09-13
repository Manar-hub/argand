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
///
/// Keyed by project rather than by file path. The path used to be the key, but
/// every caller had to thread it down purely to look this provider up, and the
/// resume position belongs to the project rather than to a file on disk. The
/// provider reads the path itself, so callers pass the id they already hold.

@ProviderFor(MediaPlayer)
final mediaPlayerProvider = MediaPlayerFamily._();

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// Keyed by project rather than by file path. The path used to be the key, but
/// every caller had to thread it down purely to look this provider up, and the
/// resume position belongs to the project rather than to a file on disk. The
/// provider reads the path itself, so callers pass the id they already hold.
final class MediaPlayerProvider
    extends $AsyncNotifierProvider<MediaPlayer, VideoPlayerController> {
  /// Owns the platform media player for one project.
  ///
  /// Lives in a provider rather than in the screen's state so that tap-to-seek
  /// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
  ///
  /// Keyed by project rather than by file path. The path used to be the key, but
  /// every caller had to thread it down purely to look this provider up, and the
  /// resume position belongs to the project rather than to a file on disk. The
  /// provider reads the path itself, so callers pass the id they already hold.
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

String _$mediaPlayerHash() => r'd894220cdf05ab0352e9c9b78b41ad0052280df6';

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// Keyed by project rather than by file path. The path used to be the key, but
/// every caller had to thread it down purely to look this provider up, and the
/// resume position belongs to the project rather than to a file on disk. The
/// provider reads the path itself, so callers pass the id they already hold.

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
  ///
  /// Keyed by project rather than by file path. The path used to be the key, but
  /// every caller had to thread it down purely to look this provider up, and the
  /// resume position belongs to the project rather than to a file on disk. The
  /// provider reads the path itself, so callers pass the id they already hold.

  MediaPlayerProvider call(String projectId) =>
      MediaPlayerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'mediaPlayerProvider';
}

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// Keyed by project rather than by file path. The path used to be the key, but
/// every caller had to thread it down purely to look this provider up, and the
/// resume position belongs to the project rather than to a file on disk. The
/// provider reads the path itself, so callers pass the id they already hold.

abstract class _$MediaPlayer extends $AsyncNotifier<VideoPlayerController> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<VideoPlayerController> build(String projectId);
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
