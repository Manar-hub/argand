import '../database/database.dart';
import 'clip_trim.dart';

/// Where one clip sits on the project timeline.
typedef ClipPlacement = ({
  String clipId,
  int index,
  int startMs,
  int durationMs,

  /// Where this clip's window begins inside its media file.
  int mediaStartMs,
});

/// A range's intersection with one clip, in both timebases at once.
typedef ClipRange = ({
  String clipId,
  int clipStartMs,
  int clipEndMs,
  int projectStartMs,
  int projectEndMs,
});

/// Where each clip falls on one shared project-wide time axis.
class ProjectTimeline {
  const ProjectTimeline._(this.placements, this.totalMs);

  /// Lays clips end to end in the order given.
  factory ProjectTimeline.fromClips(List<MediaClip> clips) {
    final placements = <ClipPlacement>[];
    var offset = 0;

    for (final (index, clip) in clips.indexed) {
      // **The trimmed length, not the file's.** Once a clip carries in/out
      // points these stop being the same number, and measuring the file would
      // put every later clip at the wrong place on the ruler.
      final duration = trimmedDurationMs(clip);
      final safe = duration < 0 ? 0 : duration;
      placements.add((
        clipId: clip.id,
        index: index,
        startMs: offset,
        durationMs: safe,
        mediaStartMs: clipWindow(clip).startMs,
      ));
      offset += safe;
    }

    return ProjectTimeline._(List.unmodifiable(placements), offset);
  }

  static final empty = ProjectTimeline._(List.unmodifiable(<ClipPlacement>[]), 0);

  final List<ClipPlacement> placements;

  /// The project's running time: every clip's duration, summed.
  final int totalMs;

  bool get isEmpty => placements.isEmpty;

  ClipPlacement? placementOf(String clipId) {
    for (final placement in placements) {
      if (placement.clipId == clipId) return placement;
    }
    return null;
  }

  /// Converts a position inside one clip's media to project time.
  int? projectMsOf({required String clipId, required int clipMs}) {
    final placement = placementOf(clipId);
    if (placement == null) return null;
    return placement.startMs + (clipMs - placement.mediaStartMs);
  }

  /// Which clip covers [projectMs], and how far into it that lands.
  ({String clipId, int clipMs})? clipAt(int projectMs) {
    if (placements.isEmpty) return null;

    if (projectMs < 0) {
      final first = placements.first;
      return (clipId: first.clipId, clipMs: first.mediaStartMs);
    }

    for (final placement in placements) {
      final end = placement.startMs + placement.durationMs;
      // Half-open, so a position exactly on a boundary belongs to the clip
      // starting there rather than the one ending.
      if (projectMs < end) {
        return (
          clipId: placement.clipId,
          clipMs: placement.mediaStartMs + (projectMs - placement.startMs),
        );
      }
    }

    final last = placements.last;
    return (clipId: last.clipId, clipMs: last.mediaStartMs + last.durationMs);
  }

  /// How long the project runs: to the end of its clips -- or on past the last
  /// one, to [contentEndMs], when something is still on the timeline there.
  int runMsWith({required int contentEndMs, int? lastFileMs}) {
    if (placements.isEmpty || lastFileMs == null) return totalMs;
    final last = placements.last;
    final fileEnd = last.startMs + (lastFileMs - last.mediaStartMs);
    final end = contentEndMs < fileEnd ? contentEndMs : fileEnd;
    return end > totalMs ? end : totalMs;
  }

  /// Where [projectMs] falls past the end of the clips, while the project
  /// still runs ([runMsWith]): in the last clip's file, beyond its out-point.
  /// Null inside the clips, and from [runMs] on.
  ({String clipId, int clipMs})? tailAt(int projectMs, {required int runMs}) {
    if (placements.isEmpty || projectMs < totalMs || projectMs >= runMs) {
      return null;
    }
    final last = placements.last;
    return (
      clipId: last.clipId,
      clipMs: last.mediaStartMs + (projectMs - last.startMs),
    );
  }

  /// Splits a project-timeline range into the per-clip work it implies.
  List<ClipRange> rangesFor({required int startMs, required int endMs}) {
    if (endMs <= startMs) return const [];

    final ranges = <ClipRange>[];
    for (final placement in placements) {
      final clipEnd = placement.startMs + placement.durationMs;
      final from = startMs > placement.startMs ? startMs : placement.startMs;
      final to = endMs < clipEnd ? endMs : clipEnd;
      if (to <= from) continue;

      ranges.add((
        clipId: placement.clipId,
        // Media time, because this is what slices the WAV and what
        // `saveClipTranscript` offsets its words by -- both of which address
        // the file, not the window.
        clipStartMs: placement.mediaStartMs + (from - placement.startMs),
        clipEndMs: placement.mediaStartMs + (to - placement.startMs),
        projectStartMs: from,
        projectEndMs: to,
      ));
    }
    return ranges;
  }
}
