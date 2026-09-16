import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:video_player/video_player.dart';

import '../../core/database/database.dart';
import 'transcript_repository.dart';

part 'media_player_controller.g.dart';

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
@riverpod
class MediaPlayer extends _$MediaPlayer {
  /// Word-level timestamps come from whisper.cpp's DTW alignment, which is
  /// known to drift by a few tens of milliseconds in either direction. Seeking
  /// to the raw start time therefore lands mid-word often enough to feel
  /// broken, so playback starts slightly ahead of it.
  static const Duration _seekLeadIn = Duration(milliseconds: 60);

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
  Future<VideoPlayerController> build(String clipId) async {
    _db = ref.read(appDatabaseProvider);

    final clip = await _db.findClip(clipId);
    // Surfaces through the screen's existing `error` branch as "player
    // unavailable", which is the honest outcome: the row is gone, so there is
    // no media to play.
    if (clip == null) {
      throw StateError('No clip $clipId to play');
    }

    final controller = VideoPlayerController.file(File(clip.mediaPath));
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

    // The platform player is the most authoritative thing that will ever read
    // this file, so it is what repairs a clip whose duration was never probed
    // successfully -- including every clip the schema-5 migration inherited
    // from a project row that had none.
    if ((clip.durationMs ?? 0) <= 0) {
      await _db.fillMissingClipDuration(clipId, controller.value.duration);
    }

    await _restore(controller);
    return controller;
  }

  Future<void> _restore(VideoPlayerController controller) async {
    final stored = await _db.readSetting(playbackPositionKey(clipId));
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
      playbackPositionKey(clipId),
      '${controller.value.position.inMilliseconds}',
    );
  }

  Future<void> seekToWord(int startMs) async {
    final controller = state.value;
    if (controller == null) return;

    final target = Duration(milliseconds: startMs) - _seekLeadIn;
    await controller.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  /// Seeks to an exact position in this clip, with no lead-in.
  ///
  /// Distinct from [seekToWord], which deliberately lands slightly *before* its
  /// target to absorb DTW timestamp drift. Scrubbing has no such drift to
  /// absorb: the user is pointing at a place on a ruler and expects that place,
  /// and a 60ms lead-in would make the playhead disagree with the frame under
  /// it by a visible margin.
  Future<void> seekTo(int positionMs) async {
    final controller = state.value;
    if (controller == null) return;

    final duration = controller.value.duration;
    var target = Duration(milliseconds: positionMs);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    await controller.seekTo(target);
  }

  Future<void> togglePlayback() async {
    final controller = state.value;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      // Saved on pause as well as on disposal: pausing is the point at which
      // the user has decided where they are, and it is also the state most
      // likely to be sitting there when the OS reclaims the process.
      _write(controller);
    } else {
      await controller.play();
    }
  }
}
