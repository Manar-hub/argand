import 'dart:math' as math;

import 'project_timeline.dart';

/// Which part of a layer a drag has hold of.
enum LayerGrip { start, end, whole }

/// Shortest a layer may be dragged to.
///
/// Matched to what the engine can say anything about: sherpa discards speech
/// under 0.2s and whisper's VAD floor is 250ms, so a layer below this could be
/// drawn but never usefully run. Stopping the drag here is kinder than letting
/// it shrink to nothing and refusing later.
const int minimumLayerMs = 250;

/// How close an edge must come to a landmark before it snaps to it, in pixels.
///
/// **In pixels rather than milliseconds** so the pull feels the same at every
/// zoom: at a wide zoom-out a few pixels is many seconds, and a millisecond
/// threshold would make snapping either unreachable or inescapable depending
/// on the scale.
const double snapDistance = 12;

/// The result of dragging a layer: where it would now sit.
typedef LayerBounds = ({int startMs, int endMs});

/// Applies a drag of [deltaMs] to a layer and returns where it lands.
///
/// **All the rules live here rather than in the gesture handler.** A drag that
/// is clamped only when it is released looks broken while it is happening —
/// the bar passes through its neighbour and then jumps back — so the limits
/// are applied every frame, which means they have to be a pure function of the
/// drag rather than of any widget state.
///
/// [lowerBoundMs] and [upperBoundMs] are the neighbouring layers' facing edges,
/// or the ends of the project. The layer is held inside them, so dragging into
/// a neighbour simply stops.
///
/// [snapTargets] are moments worth landing exactly on — clip boundaries and the
/// playhead. An edge within [snapDistance] pixels of one takes its value
/// instead, which is what makes a precise edge reachable with a thumb.
LayerBounds applyLayerDrag({
  required LayerBounds layer,
  required LayerGrip grip,
  required int deltaMs,
  required int lowerBoundMs,
  required int upperBoundMs,
  required double pixelsPerSecond,
  Iterable<int> snapTargets = const [],
}) {
  int snap(int ms) {
    if (pixelsPerSecond <= 0) return ms;
    var best = ms;
    var bestDistance = snapDistance;
    for (final target in snapTargets) {
      final distance = ((target - ms) / 1000 * pixelsPerSecond).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = target;
      }
    }
    return best;
  }

  switch (grip) {
    case LayerGrip.start:
      var start = snap(layer.startMs + deltaMs);
      // Never past its own end, and never into the layer before it.
      start = start.clamp(lowerBoundMs, layer.endMs - minimumLayerMs);
      return (startMs: start, endMs: layer.endMs);

    case LayerGrip.end:
      var end = snap(layer.endMs + deltaMs);
      end = end.clamp(layer.startMs + minimumLayerMs, upperBoundMs);
      return (startMs: layer.startMs, endMs: end);

    case LayerGrip.whole:
      final duration = layer.endMs - layer.startMs;
      final rawStart = layer.startMs + deltaMs;
      final rawEnd = layer.endMs + deltaMs;

      // Snapped by whichever edge actually reached a landmark, then moved as
      // one piece. Snapping both independently would stretch the layer while
      // the user was only trying to slide it.
      //
      // Note an edge that found nothing is returned unchanged, so "how far did
      // snapping move it" is zero for it — which is why the choice is made on
      // *whether* each edge snapped first, and only then on which moved least.
      final snappedStart = snap(rawStart);
      final snappedEnd = snap(rawEnd);
      final startSnapped = snappedStart != rawStart;
      final endSnapped = snappedEnd != rawEnd;

      final int start;
      if (startSnapped && endSnapped) {
        start = (snappedStart - rawStart).abs() <= (snappedEnd - rawEnd).abs()
            ? snappedStart
            : snappedEnd - duration;
      } else if (startSnapped) {
        start = snappedStart;
      } else if (endSnapped) {
        start = snappedEnd - duration;
      } else {
        start = rawStart;
      }

      final held = start.clamp(lowerBoundMs, upperBoundMs - duration);
      return (startMs: held, endMs: held + duration);
  }
}

/// Moments a layer edge should land exactly on.
///
/// Clip boundaries, because a layer covering "this clip" is the common case
/// and hitting the seam by eye is not; and the playhead, which turns "park it
/// where I want the edge" into a way of placing an edge precisely without fine
/// motor control.
List<int> layerSnapTargets({
  required ProjectTimeline timeline,
  int? playheadMs,
}) {
  final targets = <int>[0, timeline.totalMs];
  for (final placement in timeline.placements) {
    targets.add(placement.startMs);
    targets.add(placement.startMs + placement.durationMs);
  }
  if (playheadMs != null) targets.add(playheadMs);
  return targets;
}

/// How far a layer may be dragged before it meets its neighbours.
///
/// Returns the facing edge of the layer before and after this one, falling
/// back to the ends of the project. Layers on a track may not overlap, so
/// these are hard walls rather than suggestions.
({int lowerMs, int upperMs}) layerBoundsWithin({
  required Iterable<LayerBounds> others,
  required LayerBounds layer,
  required int totalMs,
}) {
  var lower = 0;
  var upper = math.max(totalMs, layer.endMs);

  for (final other in others) {
    if (other.endMs <= layer.startMs) {
      lower = math.max(lower, other.endMs);
    } else if (other.startMs >= layer.endMs) {
      upper = math.min(upper, other.startMs);
    }
  }

  return (lowerMs: lower, upperMs: upper);
}
