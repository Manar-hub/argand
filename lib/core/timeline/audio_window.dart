/// Where a clip's **sound** sits: its own stretch of the media and its own
/// span on the timeline, which may reach past its picture (J/L cuts) or stop
/// short of it.
///
/// Stored as two offsets from the picture window (`MediaClips.audio*OffsetMs`)
/// so a split or a picture trim carries the sound along. Everything here is
/// pure, mirroring `clip_trim.dart`, so the drag, the lane and the export all
/// read the same numbers.
library;

import 'dart:math' as math;

import '../database/database.dart';
import 'clip_trim.dart';
import 'project_timeline.dart';

/// A clip's sound relative to its picture: added to the picture window's
/// start and end.
typedef AudioOffsets = ({int startOffsetMs, int endOffsetMs});

/// The stretch of the media the sound plays, held inside the file.
///
/// [offsets] replaces the stored ones -- a drag in progress.
ClipWindow audioWindow(MediaClip clip, {AudioOffsets? offsets}) {
  final picture = clipWindow(clip);
  final media = math.max(0, clip.durationMs ?? 0);
  final start = (picture.startMs +
          (offsets?.startOffsetMs ?? clip.audioStartOffsetMs))
      .clamp(0, media);
  final end = (picture.endMs + (offsets?.endOffsetMs ?? clip.audioEndOffsetMs))
      .clamp(start, media);
  return (startMs: start, endMs: end);
}

/// Where the sound plays on the timeline, and from where in the media:
/// clamped to the timeline, so a J-cut on the first clip starts at zero and
/// an L-cut on the last ends with the video. Null when the clip is not on
/// [timeline] or its sound has no length left.
({int startMs, int endMs, int mediaStartMs})? audioSpan(
  ProjectTimeline timeline,
  MediaClip clip, {
  AudioOffsets? offsets,
}) {
  final placement = timeline.placementOf(clip.id);
  if (placement == null) return null;

  final window = audioWindow(clip, offsets: offsets);
  var start = placement.startMs + (window.startMs - placement.mediaStartMs);
  var end = placement.startMs + (window.endMs - placement.mediaStartMs);
  var mediaStart = window.startMs;
  if (start < 0) {
    mediaStart -= start;
    start = 0;
  }
  if (end > timeline.totalMs) end = timeline.totalMs;
  if (end <= start) return null;
  return (startMs: start, endMs: end, mediaStartMs: mediaStart);
}

/// Applies a drag on one end of a clip's sound and returns the offsets it
/// lands on.
///
/// Clamped every frame, as `applyTrim` is: never before the file starts or
/// after it ends, never off either end of the timeline, never shorter than
/// [minimumClipMs]. The other end stays where it is.
AudioOffsets applyAudioTrim({
  required MediaClip clip,
  required ClipEdge edge,
  required int deltaMs,
  required int placementStartMs,
  required int totalMs,
  AudioOffsets? from,
}) {
  final picture = clipWindow(clip);
  final media = math.max(0, clip.durationMs ?? 0);
  final length = picture.endMs - picture.startMs;
  final s = from?.startOffsetMs ?? clip.audioStartOffsetMs;
  final e = from?.endOffsetMs ?? clip.audioEndOffsetMs;

  switch (edge) {
    case ClipEdge.start:
      final lowest = math.max(-picture.startMs, -placementStartMs);
      final highest = length + e - minimumClipMs;
      if (highest < lowest) return (startOffsetMs: s, endOffsetMs: e);
      return (
        startOffsetMs: (s + deltaMs).clamp(lowest, highest),
        endOffsetMs: e,
      );
    case ClipEdge.end:
      final lowest = s + minimumClipMs - length;
      final highest = math.min(
        media - picture.endMs,
        totalMs - placementStartMs - length,
      );
      if (highest < lowest) return (startOffsetMs: s, endOffsetMs: e);
      return (
        startOffsetMs: s,
        endOffsetMs: (e + deltaMs).clamp(lowest, highest),
      );
  }
}

/// Packs spans into as few rows as hold them with none overlapping: earliest
/// start first, each into the first row already clear by then. The audio lane
/// draws a row per entry, and the export mixes one sequence per entry.
List<List<T>> packLanes<T>(
  List<T> items, {
  required int Function(T) startOf,
  required int Function(T) endOf,
}) {
  final lanes = <List<T>>[];
  for (final item in [...items]..sort((a, b) => startOf(a) - startOf(b))) {
    final lane = lanes
        .where((lane) => endOf(lane.last) <= startOf(item))
        .firstOrNull;
    if (lane != null) {
      lane.add(item);
    } else {
      lanes.add([item]);
    }
  }
  return lanes;
}
