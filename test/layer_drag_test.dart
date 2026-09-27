import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/layer_drag.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// 24 pixels per second, the timeline's default scale: one pixel is ~42ms, so
/// [snapDistance] of 12 pixels reaches about 500ms.
const double pps = 24;

LayerBounds layer(int startMs, int endMs) =>
    (startMs: startMs, endMs: endMs);

MediaClip clip(String id, int durationMs, int position) => MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: position,
      mediaPath: '/media/$id.mp4',
      durationMs: durationMs,
      title: id,
      scale: 1,
      rotation: 0,
      offsetX: 0,
      offsetY: 0,
      audioStartOffsetMs: 0,
      audioEndOffsetMs: 0,
      audioMuted: false,
    );

void main() {
  group('applyLayerDrag', () {
    test('dragging the end extends the layer', () {
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.end,
        deltaMs: 2000,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
      );

      expect(result, (startMs: 1000, endMs: 7000));
    });

    test('dragging the start moves only the start', () {
      final result = applyLayerDrag(
        layer: layer(4000, 9000),
        grip: LayerGrip.start,
        deltaMs: -1500,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
      );

      expect(result, (startMs: 2500, endMs: 9000));
    });

    test('dragging the whole layer keeps its length', () {
      final result = applyLayerDrag(
        layer: layer(1000, 6000),
        grip: LayerGrip.whole,
        deltaMs: 3000,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
      );

      expect(result, (startMs: 4000, endMs: 9000));
    });

    test('stops at the neighbour rather than passing through it', () {
      // Clamped every frame rather than on release: a bar that travelled into
      // its neighbour and then jumped back would look broken while it moved.
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.end,
        deltaMs: 99000,
        lowerBoundMs: 0,
        upperBoundMs: 7000,
        pixelsPerSecond: pps,
      );

      expect(result, (startMs: 1000, endMs: 7000));
    });

    test('a moved layer stops with its far edge at the neighbour', () {
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.whole,
        deltaMs: 99000,
        lowerBoundMs: 0,
        upperBoundMs: 10000,
        pixelsPerSecond: pps,
      );

      expect(result, (startMs: 6000, endMs: 10000));
    });

    test('cannot be shrunk below what the engine can transcribe', () {
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.end,
        deltaMs: -99000,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
      );

      expect(result.endMs - result.startMs, minimumLayerMs);
    });

    test('the start cannot be dragged past the end', () {
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.start,
        deltaMs: 99000,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
      );

      expect(result.endMs - result.startMs, minimumLayerMs);
      expect(result.endMs, 5000);
    });

    test('an edge near a landmark snaps onto it', () {
      // Dropped 200ms short of a clip boundary at 10000.
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.end,
        deltaMs: 4800,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
        snapTargets: const [10000],
      );

      expect(result.endMs, 10000);
    });

    test('an edge far from a landmark is left alone', () {
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.end,
        deltaMs: 2000,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
        snapTargets: const [10000],
      );

      expect(result.endMs, 7000);
    });

    test('snap reach follows the zoom, not the clock', () {
      // The same 2000ms miss: out of reach at the default scale, well inside
      // it once the axis is compressed, because the pull is a distance on
      // screen rather than an interval in the media.
      LayerBounds at(double scale) => applyLayerDrag(
            layer: layer(1000, 5000),
            grip: LayerGrip.end,
            deltaMs: 3000,
            lowerBoundMs: 0,
            upperBoundMs: 60000,
            pixelsPerSecond: scale,
            snapTargets: const [10000],
          );

      expect(at(24).endMs, 8000);
      expect(at(4).endMs, 10000);
    });

    test('moving snaps by whichever edge is closer to a landmark', () {
      // Snapping both edges independently would stretch a layer the user was
      // only trying to slide.
      final result = applyLayerDrag(
        layer: layer(1000, 5000),
        grip: LayerGrip.whole,
        deltaMs: 8800,
        lowerBoundMs: 0,
        upperBoundMs: 60000,
        pixelsPerSecond: pps,
        snapTargets: const [10000],
      );

      expect(result, (startMs: 10000, endMs: 14000));
    });
  });

  group('layerBoundsWithin', () {
    test('walls are the facing edges of the nearest layers', () {
      final bounds = layerBoundsWithin(
        others: [layer(0, 2000), layer(12000, 15000)],
        layer: layer(5000, 8000),
        totalMs: 30000,
      );

      expect(bounds, (lowerMs: 2000, upperMs: 12000));
    });

    test('with no neighbours the project is the wall', () {
      final bounds = layerBoundsWithin(
        others: const [],
        layer: layer(5000, 8000),
        totalMs: 30000,
      );

      expect(bounds, (lowerMs: 0, upperMs: 30000));
    });

    test('a layer already past the project end keeps its room', () {
      // Clips can be removed from under a layer, leaving it hanging off the
      // end. Shrinking the wall to the new total would yank it backwards as a
      // side effect of an unrelated edit.
      final bounds = layerBoundsWithin(
        others: const [],
        layer: layer(5000, 40000),
        totalMs: 30000,
      );

      expect(bounds.upperMs, 40000);
    });
  });

  group('layerSnapTargets', () {
    test('offers every clip seam and the playhead', () {
      final timeline = ProjectTimeline.fromClips([
        clip('a', 10000, 0),
        clip('b', 5000, 1),
      ]);

      expect(
        layerSnapTargets(timeline: timeline, playheadMs: 7321),
        containsAll(<int>[0, 10000, 15000, 7321]),
      );
    });

    test('works with no playhead', () {
      final timeline = ProjectTimeline.fromClips([clip('a', 10000, 0)]);

      expect(layerSnapTargets(timeline: timeline), containsAll(<int>[0, 10000]));
    });
  });
}
