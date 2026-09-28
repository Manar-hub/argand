import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:video_player/video_player.dart';

import '../../core/database/database.dart';
import '../../core/timeline/clip_trim.dart';
import 'timeline_blocks.dart';
import 'transcript_repository.dart';

part 'media_player_controller.g.dart';

/// Owns the platform decoder for one media file.
@riverpod
class MediaController extends _$MediaController {
  /// A video stopped within this much of the end counts as finished, so
  /// reopening it starts over rather than resuming onto the closing frame.
  static const Duration _restartWindow = Duration(seconds: 2);

  /// Captured during [build] rather than read on demand.
  late final AppDatabase _db;

  @override
  Future<VideoPlayerController> build(String mediaPath) async {
    _db = ref.read(appDatabaseProvider);

    final controller = VideoPlayerController.file(File(mediaPath));
    // Disposal is tied to the provider, so leaving the screen releases the
    // platform decoder even if playback was still running -- and saves the
    // position on the way out.
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
@riverpod
class MediaPlayer extends _$MediaPlayer {
  /// Word-level timestamps come from whisper.cpp's DTW alignment, which is
  /// known to drift by a few tens of milliseconds in either direction.
  static const Duration _seekLeadIn = Duration(milliseconds: 60);

  /// The seek that is waiting for the one in flight, if any.
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
    // successfully.
    if ((clip.durationMs ?? 0) <= 0) {
      await db.fillMissingClipDuration(clipId, controller.value.duration);
    }

    _keepToClips(controller, clip);
    return controller;
  }

  /// Stops the file playing past the clip -- see `playbackAfter`.
  void _keepToClips(VideoPlayerController controller, MediaClip clip) {
    var clips = ref.read(projectClipsProvider(clip.projectId)).value ??
        [clip];
    ref.listen(projectClipsProvider(clip.projectId), (_, next) {
      final value = next.value;
      if (value != null) clips = value;
    });
    // Where playback stops past the last clip, in this file's time: the words
    // still on the timeline there run on over black
    // (`ProjectTimeline.runMsWith`).
    int? runsOnTo() {
      final timeline = ref.read(projectTimelineProvider(clip.projectId));
      final last = timeline.placements.lastOrNull;
      if (last == null || last.clipId != clipId) return null;
      final run = ref.read(projectRunMsProvider(clip.projectId));
      if (run <= timeline.totalMs) return null;
      return last.mediaStartMs + (run - last.startMs);
    }

    var inside = false;
    void onTick() {
      final value = controller.value;
      final self = clips.where((c) => c.id == clipId).firstOrNull;
      if (self == null) {
        inside = false;
        return;
      }
      final window = clipWindow(self);
      final positionMs = value.position.inMilliseconds;
      if (positionMs >= window.startMs && positionMs < window.endMs) {
        inside = true;
        return;
      }
      // On past the last clip, under the words still there: no jump, no
      // stop at the out-point -- the picture and sound are hidden
      // (`ProjectStageCanvas`) and it plays on to where the words end.
      final end = positionMs >= window.endMs ? runsOnTo() : null;
      if (end != null) {
        inside = false;
        if (value.isPlaying && positionMs >= end) {
          controller
            ..pause()
            ..seekTo(Duration(milliseconds: end));
        }
        return;
      }
      if (!inside) return;
      inside = false;
      // Left backwards (a seek), or paused: nothing to do.
      if (!value.isPlaying || positionMs < window.endMs) return;

      final next = playbackAfter(self, clips);
      if (next.seekToMs case final target?) {
        controller.seekTo(Duration(milliseconds: target));
      } else if (next.stop) {
        controller
          ..pause()
          ..seekTo(Duration(milliseconds: window.endMs - 1));
      }
    }

    controller.addListener(onTick);
    ref.onDispose(() => controller.removeListener(onTick));
  }

  Future<void> seekToWord(int startMs) async {
    if (!ref.mounted) return;
    final controller = state.value;
    if (controller == null) return;

    final target = Duration(milliseconds: startMs) - _seekLeadIn;
    await controller.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  /// Seeks to an exact position in the clip's media, with no lead-in.
  Future<void> seekTo(int positionMs) async {
    _queuedSeekMs = positionMs;
    if (_seeking) return;

    _seeking = true;
    try {
      // `ref.mounted` on every pass, not just at the start.
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
