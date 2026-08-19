import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:video_player/video_player.dart';

part 'media_player_controller.g.dart';

/// Owns the platform media player for one project.
///
/// Lives in a provider rather than in the screen's state so that tap-to-seek
/// is a call into a service, not logic embedded in a widget (CLAUDE.md 4).
@riverpod
class MediaPlayer extends _$MediaPlayer {
  @override
  Future<VideoPlayerController> build(String mediaPath) async {
    final controller = VideoPlayerController.file(File(mediaPath));
    // Disposal is tied to the provider, so leaving the screen releases the
    // platform decoder even if playback was still running.
    ref.onDispose(controller.dispose);
    await controller.initialize();
    return controller;
  }

  /// Word-level timestamps come from whisper.cpp's DTW alignment, which is
  /// known to drift by a few tens of milliseconds in either direction. Seeking
  /// to the raw start time therefore lands mid-word often enough to feel
  /// broken, so playback starts slightly ahead of it.
  static const Duration _seekLeadIn = Duration(milliseconds: 60);

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
    } else {
      await controller.play();
    }
  }
}
