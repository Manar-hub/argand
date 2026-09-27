import 'dart:math' as math;

import '../database/database.dart' show TrackKind;
import 'layer_drag.dart';
import 'timeline_selection.dart';

/// One lane as the move rules see it.
typedef TrackSlot = ({String id, TrackKind kind});

/// Anything on a track, as the one set of move and resize rules sees it --
/// a clip, its sound, a transcription, a sentence, a translation line, a
/// text or an image alike.
///
/// **Every kind goes through the same rules.** What differs between kinds is
/// said here as data -- the walls it may not pass, whether it may change
/// track -- rather than as a separate drag for each track, which is how the
/// kinds came to be able to do different things.
typedef TimelineBlock = ({
  TimelineItem item,
  String trackId,
  int startMs,
  int endMs,

  /// Walls the item may not be moved or resized past: the project's ends,
  /// and for a sentence its neighbours, for a sound its file.
  int minStartMs,
  int maxEndMs,

  /// Whether it may leave its track. Clips and their sounds may not.
  bool canChangeTrack,

  /// The transcription a layer is, or a sentence belongs to. A layer's band
  /// and its own sentences share a track without colliding: the sentences
  /// are what is on the band.
  String? layerId,

  /// A sentence still on its layer's track, which follows the layer when it
  /// changes track.
  bool follows,
});

/// Where one item lands: an existing track, or the [newTrack]th new one made
/// under the last.
typedef PlannedBlock = ({
  TimelineItem item,
  int startMs,
  int endMs,
  String? trackId,
  int? newTrack,
});

/// One item's move or resize as the repository commits it: where it was and
/// where it went, in project time, and the track it went to -- an existing
/// one, or the [newTrack]th made by the drop. Both null keeps its track.
typedef ItemPlacement = ({
  TimelineItem item,
  int fromStartMs,
  int fromEndMs,
  int toStartMs,
  int toEndMs,
  String? trackId,
  int? newTrack,
});

/// A move of several items at once, as it would land.
typedef MovePlan = ({
  int deltaMs,
  int deltaRows,
  List<PlannedBlock> blocks,

  /// How many tracks the drop makes under the last one.
  int newTracks,

  /// False when something would land on a track that cannot hold it, or on
  /// top of something already there; the drop is then refused.
  bool valid,
});

bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;

bool _exempt(TimelineBlock a, TimelineBlock b) =>
    a.layerId != null && a.layerId == b.layerId;

/// Where [moving] would land, dragged [deltaMs] along and [deltaRows] down.
///
/// **Rigid:** the whole group moves by the same amount, and that amount is
/// held back so that no item passes its walls -- a group never deforms.
/// Rows above the top are refused the same way: the group stops at the top
/// track. Rows past the last track become new tracks under it, in order.
///
/// Items that cannot change track keep theirs while the rest move, and a
/// layer carries the sentences that follow it. A media item may not land on
/// the video or audio track, and nothing may land on top of an item it would
/// collide with; either makes the plan invalid rather than moving anything.
MovePlan planMove({
  required List<TimelineBlock> blocks,
  required Set<TimelineItem> moving,
  required int deltaMs,
  required int deltaRows,
  required List<TrackSlot> tracks,
}) {
  final rowOf = {for (final (i, track) in tracks.indexed) track.id: i};
  final movers = [
    for (final block in blocks)
      if (moving.contains(block.item)) block,
  ];
  final movingLayers = {
    for (final block in movers)
      if (block.item.kind == TimelineItemKind.layer) block.item.id,
  };
  final carried = [
    for (final block in blocks)
      if (!moving.contains(block.item) &&
          block.follows &&
          movingLayers.contains(block.layerId))
        block,
  ];

  // Held so that no item passes its walls.
  var delta = deltaMs;
  for (final block in movers) {
    delta = math.max(delta, block.minStartMs - block.startMs);
  }
  for (final block in movers) {
    delta = math.min(delta, block.maxEndMs - block.endMs);
  }

  // Held so that nothing rises above the top track.
  var rows = deltaRows;
  for (final block in [...movers, ...carried]) {
    if (!block.canChangeTrack) continue;
    final row = rowOf[block.trackId];
    if (row != null) rows = math.max(rows, -row);
  }

  var valid = true;
  var newTracks = 0;
  final planned = <PlannedBlock>[];
  final landed = <(TimelineBlock, PlannedBlock)>[];

  for (final block in [...movers, ...carried]) {
    final shifts = moving.contains(block.item);
    final start = shifts ? block.startMs + delta : block.startMs;
    final end = shifts ? block.endMs + delta : block.endMs;

    String? trackId = block.trackId;
    int? newTrack;
    if (block.canChangeTrack && rows != 0) {
      final row = (rowOf[block.trackId] ?? 0) + rows;
      if (row >= tracks.length) {
        newTrack = row - tracks.length;
        trackId = null;
        newTracks = math.max(newTracks, newTrack + 1);
      } else {
        final target = tracks[row];
        trackId = target.id;
        if (target.kind != TrackKind.media) valid = false;
      }
    }

    final result = (
      item: block.item,
      startMs: start,
      endMs: end,
      trackId: trackId,
      newTrack: newTrack,
    );
    planned.add(result);
    landed.add((block, result));
  }

  // Nothing on top of anything that stays where it is.
  final staying = [
    for (final block in blocks)
      if (!moving.contains(block.item) && !carried.contains(block)) block,
  ];
  for (final (block, result) in landed) {
    if (result.trackId == null) continue;
    for (final other in staying) {
      if (other.trackId != result.trackId || _exempt(block, other)) continue;
      if (_overlaps(result.startMs, result.endMs, other.startMs, other.endMs)) {
        valid = false;
      }
    }
  }
  // Nor on top of each other, where two land on the same track.
  for (var i = 0; i < landed.length; i++) {
    for (var j = i + 1; j < landed.length; j++) {
      final (a, ra) = landed[i];
      final (b, rb) = landed[j];
      final sameTrack = ra.trackId != null
          ? ra.trackId == rb.trackId
          : ra.newTrack != null && ra.newTrack == rb.newTrack;
      if (!sameTrack || _exempt(a, b)) continue;
      if (_overlaps(ra.startMs, ra.endMs, rb.startMs, rb.endMs)) valid = false;
    }
  }

  return (
    deltaMs: delta,
    deltaRows: rows,
    blocks: planned,
    newTracks: newTracks,
    valid: valid,
  );
}

/// Where [block] lands with one edge dragged [deltaMs].
///
/// Held inside its own walls and by whatever else is on its track, never
/// shorter than [minimumLayerMs], and snapped to [snapTargets] the way a
/// transcription's edges always have been (`applyLayerDrag`).
LayerBounds planResize({
  required TimelineBlock block,
  required List<TimelineBlock> blocks,
  required LayerGrip grip,
  required int deltaMs,
  required double pixelsPerSecond,
  Iterable<int> snapTargets = const [],
}) {
  final walls = layerBoundsWithin(
    others: [
      for (final other in blocks)
        if (other.item != block.item &&
            other.trackId == block.trackId &&
            !_exempt(block, other))
          (startMs: other.startMs, endMs: other.endMs),
    ],
    layer: (startMs: block.startMs, endMs: block.endMs),
    totalMs: block.maxEndMs,
  );
  return applyLayerDrag(
    layer: (startMs: block.startMs, endMs: block.endMs),
    grip: grip,
    deltaMs: deltaMs,
    lowerBoundMs: math.max(walls.lowerMs, block.minStartMs),
    upperBoundMs: math.min(walls.upperMs, block.maxEndMs),
    pixelsPerSecond: pixelsPerSecond,
    snapTargets: snapTargets,
  );
}

/// A word's timing, as a retime reads and writes it.
typedef RetimedWord = ({String id, int startMs, int endMs});

/// [words] stretched from the span they cover into [startMs]..[endMs], each
/// keeping its share of it -- a sentence moved (the same length, shifted) or
/// resized on the timeline.
List<RetimedWord> retimeWords(
  List<RetimedWord> words, {
  required int startMs,
  required int endMs,
}) {
  if (words.isEmpty) return const [];
  final from = words.map((w) => w.startMs).reduce(math.min);
  final to = words.map((w) => w.endMs).reduce(math.max);
  final span = to - from;
  int map(int ms) => span <= 0
      ? startMs
      : startMs + ((ms - from) * (endMs - startMs) / span).round();
  return [
    for (final word in words)
      (id: word.id, startMs: map(word.startMs), endMs: map(word.endMs)),
  ];
}
