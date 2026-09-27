import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/database/database.dart';
import '../../core/timeline/audio_window.dart';
import 'clip_controller.dart';
import 'media_player_controller.dart';
import 'transcript_repository.dart';

/// Plays, in the preview, the sound of *other* clips that reaches under the
/// picture being shown -- an L-cut carrying on under the next clip, a J-cut
/// starting before its own.
///
/// **Its own players, never the shared picture decoders.** Each sound under
/// the playhead gets an audio-only player for its file, held within a few
/// frames of where the playhead says it should be and paused the moment the
/// picture pauses. Draws nothing.
///
/// Heard while the picture under the playhead plays: the preview plays one
/// clip at a time, so a tail under the next clip is heard when playback runs
/// there.
class OverlapAudio extends ConsumerStatefulWidget {
  const OverlapAudio({
    super.key,
    required this.projectId,
    required this.clipId,
    required this.mediaPositionMs,
  });

  final String projectId;

  /// The clip whose picture is showing, and where its media is.
  final String clipId;
  final int mediaPositionMs;

  @override
  ConsumerState<OverlapAudio> createState() => _OverlapAudioState();
}

class _OverlapAudioState extends ConsumerState<OverlapAudio> {
  final Map<String, VideoPlayerController> _players = {};
  final Set<String> _opening = {};

  /// How far a sound may drift from the picture before it is put back.
  static const _tolerance = Duration(milliseconds: 150);

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final hidden = ref.watch(hiddenTracksProvider(projectId));
    final clips = ref.watch(projectClipsProvider(projectId)).value ??
        const <MediaClip>[];
    final timeline = ref.watch(projectTimelineProvider(projectId));
    final main = ref.watch(mediaPlayerProvider(widget.clipId)).value;
    final playing = main?.value.isPlaying ?? false;
    final projectMs = timeline.projectMsOf(
      clipId: widget.clipId,
      clipMs: widget.mediaPositionMs,
    );

    // Every other clip's sound under the playhead, and where in its file.
    final wanted = <String, (MediaClip, int)>{};
    if (!hidden.contains(TimelineTrack.audio) && projectMs != null) {
      for (final clip in clips) {
        if (clip.id == widget.clipId || clip.audioMuted) continue;
        final span = audioSpan(timeline, clip);
        if (span == null) continue;
        if (projectMs >= span.startMs && projectMs < span.endMs) {
          wanted[clip.id] =
              (clip, span.mediaStartMs + (projectMs - span.startMs));
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(wanted, playing);
    });
    return const SizedBox.shrink();
  }

  Future<void> _sync(Map<String, (MediaClip, int)> wanted, bool playing) async {
    for (final id in [..._players.keys]) {
      if (!wanted.containsKey(id)) {
        await _players.remove(id)!.dispose();
      } else if (!playing && _players[id]!.value.isPlaying) {
        await _players[id]!.pause();
      }
    }
    if (!playing) return;

    for (final MapEntry(key: id, value: (clip, mediaMs)) in wanted.entries) {
      final player = _players[id];
      if (player == null) {
        if (_opening.add(id)) {
          final opened = VideoPlayerController.file(File(clip.mediaPath));
          try {
            await opened.initialize();
          } on Exception {
            _opening.remove(id);
            await opened.dispose();
            continue;
          }
          _opening.remove(id);
          if (!mounted) {
            await opened.dispose();
            return;
          }
          _players[id] = opened;
          await opened.seekTo(Duration(milliseconds: mediaMs));
          await opened.play();
        }
        continue;
      }
      final target = Duration(milliseconds: mediaMs);
      if (!player.value.isPlaying) {
        await player.seekTo(target);
        await player.play();
      } else if ((player.value.position - target).abs() > _tolerance) {
        await player.seekTo(target);
      }
    }
  }
}
