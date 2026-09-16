import '../database/database.dart';

/// Where one clip sits on the project timeline.
typedef ClipPlacement = ({
  String clipId,
  int index,
  int startMs,
  int durationMs,
});

/// A range's intersection with one clip, in both timebases at once.
///
/// [clipStartMs]/[clipEndMs] are what the engine needs — offsets into that
/// clip's own media. [projectStartMs]/[projectEndMs] are what the timeline
/// draws. Carrying both is the point: converting between them requires the
/// clip's placement, and every caller that had to redo that conversion would
/// be a second copy of the rule.
typedef ClipRange = ({
  String clipId,
  int clipStartMs,
  int clipEndMs,
  int projectStartMs,
  int projectEndMs,
});

/// Where each clip falls on one shared project-wide time axis.
///
/// **Word timings stay clip-relative** — whisper is fed one clip's audio and
/// reports offsets into it, and there is no compositor that could define a
/// single continuous recording. What this adds is the *arrangement*: clips lie
/// end to end in `position` order, so a project has a total length and every
/// clip has a start, which is what a ruler measures and what lets a range drawn
/// on the timeline be turned back into per-clip work.
///
/// Pure and synchronous, holding no providers and touching no database beyond
/// the [MediaClip] rows handed in, so the rule is host-testable and lives in
/// exactly one place. The alternative — each widget folding its own running
/// sum — is how the ruler and the track came to disagree in the first place.
///
/// **Intervals are half-open, `[start, end)`.** A range ending exactly on a
/// clip boundary yields nothing in the next clip, which is the only rule under
/// which two adjacent ranges tile without sharing a millisecond.
class ProjectTimeline {
  const ProjectTimeline._(this.placements, this.totalMs);

  /// Lays clips end to end in the order given.
  ///
  /// A clip with no usable duration contributes zero and occupies a zero-width
  /// slot rather than being dropped: it still exists, still plays, and still
  /// shows on the track — it simply cannot be measured yet. `MediaPlayer`
  /// repairs such a duration the first time it opens the clip, at which point
  /// the timeline rebuilds from the corrected rows.
  factory ProjectTimeline.fromClips(List<MediaClip> clips) {
    final placements = <ClipPlacement>[];
    var offset = 0;

    for (final (index, clip) in clips.indexed) {
      final duration = clip.durationMs ?? 0;
      final safe = duration < 0 ? 0 : duration;
      placements.add((
        clipId: clip.id,
        index: index,
        startMs: offset,
        durationMs: safe,
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

  /// Converts a position inside one clip to a position on the project timeline.
  ///
  /// Null when the clip is not part of this arrangement — it was removed, or
  /// the timeline was built from a different project.
  int? projectMsOf({required String clipId, required int clipMs}) {
    final placement = placementOf(clipId);
    if (placement == null) return null;
    return placement.startMs + clipMs;
  }

  /// Which clip covers [projectMs], and how far into it that lands.
  ///
  /// Clamped to the arrangement rather than returning null past the ends: the
  /// playhead can be dragged beyond the last frame, and the honest answer there
  /// is "the end of the last clip", not "nowhere".
  ({String clipId, int clipMs})? clipAt(int projectMs) {
    if (placements.isEmpty) return null;

    if (projectMs < 0) {
      return (clipId: placements.first.clipId, clipMs: 0);
    }

    for (final placement in placements) {
      final end = placement.startMs + placement.durationMs;
      // Half-open, so a position exactly on a boundary belongs to the clip
      // starting there rather than the one ending.
      if (projectMs < end) {
        return (clipId: placement.clipId, clipMs: projectMs - placement.startMs);
      }
    }

    final last = placements.last;
    return (clipId: last.clipId, clipMs: last.durationMs);
  }

  /// Splits a project-timeline range into the per-clip work it implies.
  ///
  /// Returns **every** non-empty intersection, slivers included. This is
  /// geometry and holds no policy: a caller drawing coverage wants the slivers
  /// because they are real, while a caller about to run an engine has its own
  /// minimum below which a range cannot be answered. Mixing the two here would
  /// make the drawing wrong to serve the engine.
  ///
  /// Zero-duration clips can never intersect anything, so they are skipped by
  /// the same arithmetic that handles a range falling in a gap.
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
        clipStartMs: from - placement.startMs,
        clipEndMs: to - placement.startMs,
        projectStartMs: from,
        projectEndMs: to,
      ));
    }
    return ranges;
  }
}
