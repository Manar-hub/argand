import 'package:argand/core/timeline/timeline_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scalePixelsPerSecond', () {
    test('multiplies rather than adds, so a pinch feels the same at any zoom',
        () {
      expect(scalePixelsPerSecond(24, 2), 48);
      expect(scalePixelsPerSecond(48, 2), 96);
      expect(scalePixelsPerSecond(48, 0.5), 24);
    });

    test('holds the permitted range at both ends', () {
      expect(scalePixelsPerSecond(24, 100), maxPixelsPerSecond);
      expect(scalePixelsPerSecond(24, 0.001), minPixelsPerSecond);
    });

    test('a degenerate scale leaves the zoom where it was', () {
      // Zero, NaN and infinity all arrive when a pointer is lost mid-gesture.
      expect(scalePixelsPerSecond(24, 0), 24);
      expect(scalePixelsPerSecond(24, double.nan), 24);
      expect(scalePixelsPerSecond(24, double.infinity), 24);
    });
  });

  group('offsetForAnchor', () {
    test('puts the anchored moment back under the playhead', () {
      // 10s at 24px/s is 240px in; at 48px/s the same moment is 480px in.
      expect(
        offsetForAnchor(
            anchorMs: 10000, pixelsPerSecond: 48, maxScrollExtent: 5000),
        480,
      );
    });

    test('clamps when zooming out puts the anchor past the end', () {
      // Zooming out shortens the content, so the moment that was under the
      // playhead can fall beyond what the new scale can scroll to.
      expect(
        offsetForAnchor(
            anchorMs: 600000, pixelsPerSecond: 4, maxScrollExtent: 1000),
        1000,
      );
    });

    test('content that cannot scroll sits at zero', () {
      expect(
        offsetForAnchor(
            anchorMs: 10000, pixelsPerSecond: 24, maxScrollExtent: 0),
        0,
      );
    });
  });

  group('msAtOffset', () {
    test('is the inverse of the offset calculation', () {
      const anchor = 7321;
      final offset = offsetForAnchor(
        anchorMs: anchor,
        pixelsPerSecond: 96,
        maxScrollExtent: 100000,
      );

      expect(msAtOffset(offset: offset, pixelsPerSecond: 96), anchor);
    });

    test('survives a round trip at every permitted scale', () {
      // A sign or ordering error here would show as the playhead drifting off
      // the moment it was holding, a little more with each pinch.
      for (final pps in [minPixelsPerSecond, 24.0, 96.0, maxPixelsPerSecond]) {
        final offset = offsetForAnchor(
          anchorMs: 45000,
          pixelsPerSecond: pps,
          maxScrollExtent: 1000000,
        );

        expect(
          msAtOffset(offset: offset, pixelsPerSecond: pps),
          closeTo(45000, 1),
          reason: 'round trip drifted at $pps px/s',
        );
      }
    });

    test('never reports a negative time', () {
      expect(msAtOffset(offset: -50, pixelsPerSecond: 24), 0);
    });

    test('a nonsensical scale yields zero rather than dividing by it', () {
      expect(msAtOffset(offset: 100, pixelsPerSecond: 0), 0);
    });
  });
}
