// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_player_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the platform media player for one clip.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// **Keyed by clip since schema 5**, having been keyed by project before that
/// (and by file path before *that*, which was dropped because every caller had
/// to thread the path down purely to look this provider up). A project now
/// holds several clips and the preview plays whichever is selected, so one
/// player per project would have to be torn down and rebuilt on every
/// selection anyway — the key simply says so. The resume position follows the
/// same move, since where you were in one clip says nothing about another.
///
/// Selecting a different clip disposes this provider and builds the next one,
/// which is what releases the platform decoder: two initialised video decoders
/// on a phone is a real cost, not a theoretical one.

@ProviderFor(MediaPlayer)
final mediaPlayerProvider = MediaPlayerFamily._();

/// Owns the platform media player for one clip.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// **Keyed by clip since schema 5**, having been keyed by project before that
/// (and by file path before *that*, which was dropped because every caller had
/// to thread the path down purely to look this provider up). A project now
/// holds several clips and the preview plays whichever is selected, so one
/// player per project would have to be torn down and rebuilt on every
/// selection anyway — the key simply says so. The resume position follows the
/// same move, since where you were in one clip says nothing about another.
///
/// Selecting a different clip disposes this provider and builds the next one,
/// which is what releases the platform decoder: two initialised video decoders
/// on a phone is a real cost, not a theoretical one.
final class MediaPlayerProvider
    extends $AsyncNotifierProvider<MediaPlayer, VideoPlayerController> {
  /// Owns the platform media player for one clip.
  ///
  /// Lives in a provider rather than in the screen's state so that tap-to-seek
  /// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
  ///
  /// **Keyed by clip since schema 5**, having been keyed by project before that
  /// (and by file path before *that*, which was dropped because every caller had
  /// to thread the path down purely to look this provider up). A project now
  /// holds several clips and the preview plays whichever is selected, so one
  /// player per project would have to be torn down and rebuilt on every
  /// selection anyway — the key simply says so. The resume position follows the
  /// same move, since where you were in one clip says nothing about another.
  ///
  /// Selecting a different clip disposes this provider and builds the next one,
  /// which is what releases the platform decoder: two initialised video decoders
  /// on a phone is a real cost, not a theoretical one.
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

String _$mediaPlayerHash() => r'0e63dce5c70c19e48771f9148bfc0a3ddbd555e0';

/// Owns the platform media player for one clip.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// **Keyed by clip since schema 5**, having been keyed by project before that
/// (and by file path before *that*, which was dropped because every caller had
/// to thread the path down purely to look this provider up). A project now
/// holds several clips and the preview plays whichever is selected, so one
/// player per project would have to be torn down and rebuilt on every
/// selection anyway — the key simply says so. The resume position follows the
/// same move, since where you were in one clip says nothing about another.
///
/// Selecting a different clip disposes this provider and builds the next one,
/// which is what releases the platform decoder: two initialised video decoders
/// on a phone is a real cost, not a theoretical one.

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

  /// Owns the platform media player for one clip.
  ///
  /// Lives in a provider rather than in the screen's state so that tap-to-seek
  /// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
  ///
  /// **Keyed by clip since schema 5**, having been keyed by project before that
  /// (and by file path before *that*, which was dropped because every caller had
  /// to thread the path down purely to look this provider up). A project now
  /// holds several clips and the preview plays whichever is selected, so one
  /// player per project would have to be torn down and rebuilt on every
  /// selection anyway — the key simply says so. The resume position follows the
  /// same move, since where you were in one clip says nothing about another.
  ///
  /// Selecting a different clip disposes this provider and builds the next one,
  /// which is what releases the platform decoder: two initialised video decoders
  /// on a phone is a real cost, not a theoretical one.

  MediaPlayerProvider call(String clipId) =>
      MediaPlayerProvider._(argument: clipId, from: this);

  @override
  String toString() => r'mediaPlayerProvider';
}

/// Owns the platform media player for one clip.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// **Keyed by clip since schema 5**, having been keyed by project before that
/// (and by file path before *that*, which was dropped because every caller had
/// to thread the path down purely to look this provider up). A project now
/// holds several clips and the preview plays whichever is selected, so one
/// player per project would have to be torn down and rebuilt on every
/// selection anyway — the key simply says so. The resume position follows the
/// same move, since where you were in one clip says nothing about another.
///
/// Selecting a different clip disposes this provider and builds the next one,
/// which is what releases the platform decoder: two initialised video decoders
/// on a phone is a real cost, not a theoretical one.

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
