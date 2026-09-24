// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_player_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the platform decoder for one **media file**.
///
/// **Keyed by path, not by clip, since clips can be split.** Both halves of a
/// cut address the same file, so a per-clip decoder guaranteed a teardown and a
/// rebuild at a boundary where nothing about the media had changed — a visible
/// reload every time playback crossed a cut the user had just made. Sharing by
/// path makes that transition seamless, because it is literally the same file
/// playing on.
///
/// Two clips over one file therefore share a decoder *and* a resume position.
/// That is the trade: one position per file rather than per clip, in exchange
/// for cuts that do not stutter. Two initialised decoders on a phone is a real
/// cost, so sharing is the cheaper side anyway.
///
/// This is deliberately not the provider screens talk to — see [MediaPlayer],
/// which stays keyed by clip so no caller had to learn about paths.

@ProviderFor(MediaController)
final mediaControllerProvider = MediaControllerFamily._();

/// Owns the platform decoder for one **media file**.
///
/// **Keyed by path, not by clip, since clips can be split.** Both halves of a
/// cut address the same file, so a per-clip decoder guaranteed a teardown and a
/// rebuild at a boundary where nothing about the media had changed — a visible
/// reload every time playback crossed a cut the user had just made. Sharing by
/// path makes that transition seamless, because it is literally the same file
/// playing on.
///
/// Two clips over one file therefore share a decoder *and* a resume position.
/// That is the trade: one position per file rather than per clip, in exchange
/// for cuts that do not stutter. Two initialised decoders on a phone is a real
/// cost, so sharing is the cheaper side anyway.
///
/// This is deliberately not the provider screens talk to — see [MediaPlayer],
/// which stays keyed by clip so no caller had to learn about paths.
final class MediaControllerProvider
    extends $AsyncNotifierProvider<MediaController, VideoPlayerController> {
  /// Owns the platform decoder for one **media file**.
  ///
  /// **Keyed by path, not by clip, since clips can be split.** Both halves of a
  /// cut address the same file, so a per-clip decoder guaranteed a teardown and a
  /// rebuild at a boundary where nothing about the media had changed — a visible
  /// reload every time playback crossed a cut the user had just made. Sharing by
  /// path makes that transition seamless, because it is literally the same file
  /// playing on.
  ///
  /// Two clips over one file therefore share a decoder *and* a resume position.
  /// That is the trade: one position per file rather than per clip, in exchange
  /// for cuts that do not stutter. Two initialised decoders on a phone is a real
  /// cost, so sharing is the cheaper side anyway.
  ///
  /// This is deliberately not the provider screens talk to — see [MediaPlayer],
  /// which stays keyed by clip so no caller had to learn about paths.
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

/// Owns the platform decoder for one **media file**.
///
/// **Keyed by path, not by clip, since clips can be split.** Both halves of a
/// cut address the same file, so a per-clip decoder guaranteed a teardown and a
/// rebuild at a boundary where nothing about the media had changed — a visible
/// reload every time playback crossed a cut the user had just made. Sharing by
/// path makes that transition seamless, because it is literally the same file
/// playing on.
///
/// Two clips over one file therefore share a decoder *and* a resume position.
/// That is the trade: one position per file rather than per clip, in exchange
/// for cuts that do not stutter. Two initialised decoders on a phone is a real
/// cost, so sharing is the cheaper side anyway.
///
/// This is deliberately not the provider screens talk to — see [MediaPlayer],
/// which stays keyed by clip so no caller had to learn about paths.

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

  /// Owns the platform decoder for one **media file**.
  ///
  /// **Keyed by path, not by clip, since clips can be split.** Both halves of a
  /// cut address the same file, so a per-clip decoder guaranteed a teardown and a
  /// rebuild at a boundary where nothing about the media had changed — a visible
  /// reload every time playback crossed a cut the user had just made. Sharing by
  /// path makes that transition seamless, because it is literally the same file
  /// playing on.
  ///
  /// Two clips over one file therefore share a decoder *and* a resume position.
  /// That is the trade: one position per file rather than per clip, in exchange
  /// for cuts that do not stutter. Two initialised decoders on a phone is a real
  /// cost, so sharing is the cheaper side anyway.
  ///
  /// This is deliberately not the provider screens talk to — see [MediaPlayer],
  /// which stays keyed by clip so no caller had to learn about paths.

  MediaControllerProvider call(String mediaPath) =>
      MediaControllerProvider._(argument: mediaPath, from: this);

  @override
  String toString() => r'mediaControllerProvider';
}

/// Owns the platform decoder for one **media file**.
///
/// **Keyed by path, not by clip, since clips can be split.** Both halves of a
/// cut address the same file, so a per-clip decoder guaranteed a teardown and a
/// rebuild at a boundary where nothing about the media had changed — a visible
/// reload every time playback crossed a cut the user had just made. Sharing by
/// path makes that transition seamless, because it is literally the same file
/// playing on.
///
/// Two clips over one file therefore share a decoder *and* a resume position.
/// That is the trade: one position per file rather than per clip, in exchange
/// for cuts that do not stutter. Two initialised decoders on a phone is a real
/// cost, so sharing is the cheaper side anyway.
///
/// This is deliberately not the provider screens talk to — see [MediaPlayer],
/// which stays keyed by clip so no caller had to learn about paths.

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
///
/// **Still keyed by clip**, so every screen keeps asking the question it
/// actually has — "play this clip" — while [MediaController] underneath decides
/// that two clips over one file share a decoder. Splitting a clip therefore
/// costs no reload: both halves resolve to the same controller.
///
/// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
/// word timings in the database. A trimmed clip's in-point is already folded
/// into those numbers, so nothing at this layer needs to know about trimming.

@ProviderFor(MediaPlayer)
final mediaPlayerProvider = MediaPlayerFamily._();

/// The player for one clip.
///
/// **Still keyed by clip**, so every screen keeps asking the question it
/// actually has — "play this clip" — while [MediaController] underneath decides
/// that two clips over one file share a decoder. Splitting a clip therefore
/// costs no reload: both halves resolve to the same controller.
///
/// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
/// word timings in the database. A trimmed clip's in-point is already folded
/// into those numbers, so nothing at this layer needs to know about trimming.
final class MediaPlayerProvider
    extends $AsyncNotifierProvider<MediaPlayer, VideoPlayerController> {
  /// The player for one clip.
  ///
  /// **Still keyed by clip**, so every screen keeps asking the question it
  /// actually has — "play this clip" — while [MediaController] underneath decides
  /// that two clips over one file share a decoder. Splitting a clip therefore
  /// costs no reload: both halves resolve to the same controller.
  ///
  /// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
  /// word timings in the database. A trimmed clip's in-point is already folded
  /// into those numbers, so nothing at this layer needs to know about trimming.
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

String _$mediaPlayerHash() => r'd25ea9057e86b3b3be61af08d9bfd54e0d2869e5';

/// The player for one clip.
///
/// **Still keyed by clip**, so every screen keeps asking the question it
/// actually has — "play this clip" — while [MediaController] underneath decides
/// that two clips over one file share a decoder. Splitting a clip therefore
/// costs no reload: both halves resolve to the same controller.
///
/// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
/// word timings in the database. A trimmed clip's in-point is already folded
/// into those numbers, so nothing at this layer needs to know about trimming.

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
  ///
  /// **Still keyed by clip**, so every screen keeps asking the question it
  /// actually has — "play this clip" — while [MediaController] underneath decides
  /// that two clips over one file share a decoder. Splitting a clip therefore
  /// costs no reload: both halves resolve to the same controller.
  ///
  /// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
  /// word timings in the database. A trimmed clip's in-point is already folded
  /// into those numbers, so nothing at this layer needs to know about trimming.

  MediaPlayerProvider call(String clipId) =>
      MediaPlayerProvider._(argument: clipId, from: this);

  @override
  String toString() => r'mediaPlayerProvider';
}

/// The player for one clip.
///
/// **Still keyed by clip**, so every screen keeps asking the question it
/// actually has — "play this clip" — while [MediaController] underneath decides
/// that two clips over one file share a decoder. Splitting a clip therefore
/// costs no reload: both halves resolve to the same controller.
///
/// Seeking here is in **media time**, matching `ProjectTimeline.clipAt` and the
/// word timings in the database. A trimmed clip's in-point is already folded
/// into those numbers, so nothing at this layer needs to know about trimming.

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
