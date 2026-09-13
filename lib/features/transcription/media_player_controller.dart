import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:video_player/video_player.dart';

import '../../core/database/database.dart';
import 'transcript_repository.dart';

part 'media_player_controller.g.dart';

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
///
/// Keyed by project rather than by file path. The path used to be the key, but
/// every caller had to thread it down purely to look this provider up, and the
/// resume position belongs to the project rather than to a file on disk. The
/// provider reads the path itself, so callers pass the id they already hold.
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
  Future<VideoPlayerController> build(String projectId) async {
    _db = ref.read(appDatabaseProvider);

    final project = await _db.findProject(projectId);
    // Surfaces through the screen's existing `error` branch as "player
    // unavailable", which is the honest outcome: the row is gone, so there is
    // no media to play.
    if (project == null) {
      throw StateError('No project $projectId to play');
    }

    final controller = VideoPlayerController.file(File(project.mediaPath));
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
    final stored = await _db.readSetting(playbackPositionKey(projectId));
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
      playbackPositionKey(projectId),
      '${controller.value.position.inMilliseconds}',
    );
  }

  Future<void> seekToWord(int startMs) async {
    final controller = state.value;
    if (controller == null) return;

    final target = Duration(milliseconds: startMs) - _seekLeadIn;
    await controller.seekTo(target < Duration.zero ? Duration.zero : target);
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
