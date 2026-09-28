import 'dart:math' as math;

import 'project_timeline.dart';

/// Which part of a layer a drag has hold of.
enum LayerGrip { start, end, whole }

/// Shortest a layer may be dragged to.
const int minimumLayerMs = 250;

/// How close an edge must come to a landmark before it snaps to it, in pixels.
const double snapDistance = 12;

/// The result of dragging a layer: where it would now sit.
typedef LayerBounds = ({int startMs, int endMs});

/// Applies a drag of [deltaMs] to a layer and returns where it lands.
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
