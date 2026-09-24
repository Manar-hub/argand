import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:video_player/video_player.dart';

import '../../core/database/database.dart';
import 'transcript_repository.dart';

part 'media_player_controller.g.dart';

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
@riverpod
class MediaController extends _$MediaController {
  /// A video stopped within this much of the end counts as finished, so
  /// reopening it starts over rather than resuming onto the closing frame.
  static const Duration _restartWindow = Duration(seconds: 2);

  /// Captured during [build] rather than read on demand.
  ///
  /// The position is saved from `onDispose`, by which point `ref` is closing
  /// and `ref.read` is no longer safe. The database provider is `keepAlive`, so
  /// holding the instance across disposal is sound.
  late final AppDatabase _db;

  @override
  Future<VideoPlayerController> build(String mediaPath) async {
    _db = ref.read(appDatabaseProvider);

    final controller = VideoPlayerController.file(File(mediaPath));
    // Disposal is tied to the provider, so leaving the screen releases the
    // platform decoder even if playback was still running -- and saves the
    // position on the way out, which is what makes navigating away remember
    // where you were.
    //
    // Note there is no "app is closing" hook doing this work. Android can kill
    // a backgrounded process without running any Dart, so anything that must
    // survive has to be written at the moment it becomes true, not at exit.
    ref.onDispose(() {
      _write(controller);
      controller.dispose();
    });

    await controller.initialize();
    await _restore(controller);
    return controller;
  }

  Future<void> _restore(VideoPlayerController controller) async {
    final stored = await _db.readSetting(playbackPositionKey(mediaPath));
    final ms = int.tryParse(stored ?? '');
    if (ms == null || ms <= 0) return;

    final target = Duration(milliseconds: ms);
    final duration = controller.value.duration;
    if (duration > Duration.zero && target >= duration - _restartWindow) return;

    await controller.seekTo(target);
  }

  /// Fire-and-forget, because `onDispose` cannot await.
  void _write(VideoPlayerController controller) {
    if (!controller.value.isInitialized) return;
    _db.writeSetting(
      playbackPositionKey(mediaPath),
      '${controller.value.position.inMilliseconds}',
    );
  }

  /// Saves where playback is, without waiting for disposal.
  void remember() {
    final controller = state.value;
    if (controller != null) _write(controller);
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
@riverpod
class MediaPlayer extends _$MediaPlayer {
  /// Word-level timestamps come from whisper.cpp's DTW alignment, which is
  /// known to drift by a few tens of milliseconds in either direction. Seeking
  /// to the raw start time therefore lands mid-word often enough to feel
  /// broken, so playback starts slightly ahead of it.
  static const Duration _seekLeadIn = Duration(milliseconds: 60);

  /// The seek that is waiting for the one in flight, if any.
  ///
  /// **Scrubbing issues a seek per scroll frame** -- up to sixty a second --
  /// and each is an async hop to the platform. Firing them all leaves the
  /// decoder permanently behind the finger and the picture never settles, so
  /// only one is ever in flight and only the newest target is kept. The
  /// intermediate ones are worth nothing: nobody wants to see a frame the
  /// finger has already passed.
  int? _queuedSeekMs;
  bool _seeking = false;

  @override
  Future<VideoPlayerController> build(String clipId) async {
    final db = ref.read(appDatabaseProvider);

    final clip = await db.findClip(clipId);
    // Surfaces through the screen's existing `error` branch as "player
    // unavailable", which is the honest outcome: the row is gone, so there is
    // no media to play.
    if (clip == null) {
      throw StateError('No clip $clipId to play');
    }

    // Watched, not read: this is what keeps the shared decoder alive for as
    // long as any clip over that file is being played.
    final controller =
        await ref.watch(mediaControllerProvider(clip.mediaPath).future);

    // The platform player is the most authoritative thing that will ever read
    // this file, so it is what repairs a clip whose duration was never probed
    // successfully -- including every clip the schema-5 migration inherited
    // from a project row that had none.
    if ((clip.durationMs ?? 0) <= 0) {
      await db.fillMissingClipDuration(clipId, controller.value.duration);
    }

    return controller;
  }

  Future<void> seekToWord(int startMs) async {
    if (!ref.mounted) return;
    final controller = state.value;
    if (controller == null) return;

    final target = Duration(milliseconds: startMs) - _seekLeadIn;
    await controller.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  /// Seeks to an exact position in the clip's media, with no lead-in.
  ///
  /// Distinct from [seekToWord], which deliberately lands slightly *before* its
  /// target to absorb DTW timestamp drift. Scrubbing has no such drift to
  /// absorb: the user is pointing at a place on a ruler and expects that place,
  /// and a 60ms lead-in would make the playhead disagree with the frame under
  /// it by a visible margin.
  ///
  /// Coalesced rather than queued — see [_queuedSeekMs].
  Future<void> seekTo(int positionMs) async {
    _queuedSeekMs = positionMs;
    if (_seeking) return;

    _seeking = true;
    try {
      // **`ref.mounted` on every pass, not just at the start.** Scrubbing
      // across a clip boundary disposes the player for the clip being left
      // while this loop is still awaiting a seek on it, and touching `state`
      // afterwards throws `UnmountedRefException` out of an otherwise healthy
      // drag -- which is what it did on every crossing.
      while (_queuedSeekMs != null && ref.mounted) {
        final next = _queuedSeekMs!;
        _queuedSeekMs = null;
        await _seekNow(next);
      }
    } finally {
      _seeking = false;
    }
  }

  Future<void> _seekNow(int positionMs) async {
    if (!ref.mounted) return;
    final controller = state.value;
    if (controller == null) return;

    final duration = controller.value.duration;
    var target = Duration(milliseconds: positionMs);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    await controller.seekTo(target);
  }

  Future<void> togglePlayback() async {
    if (!ref.mounted) return;
    final controller = state.value;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      // Saved on pause as well as on disposal: pausing is the point at which
      // the user has decided where they are, and it is also the state most
      // likely to be sitting there when the OS reclaims the process.
      final clip = await ref.read(appDatabaseProvider).findClip(clipId);
      if (clip != null && ref.mounted) {
        ref.read(mediaControllerProvider(clip.mediaPath).notifier).remember();
      }
    } else {
      await controller.play();
    }
  }
}
