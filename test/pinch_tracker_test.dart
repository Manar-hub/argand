import 'package:argand/core/timeline/pinch_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinchTracker', () {
    test('one finger is not a pinch', () {
      final tracker = PinchTracker();

      expect(tracker.down(1, const Offset(100, 100)), isFalse);
      expect(tracker.isPinching, isFalse);
      expect(tracker.move(1, const Offset(200, 100)), isNull);
    });

    test('a second finger begins a pinch', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));

      expect(tracker.down(2, const Offset(200, 100)), isTrue);
      expect(tracker.isPinching, isTrue);
    });

    test('spreading the fingers scales up, closing them scales down', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));

      // 100pt apart to 200pt apart.
      expect(tracker.move(2, const Offset(300, 100)), 2.0);
      // and back in to 50pt.
      expect(tracker.move(2, const Offset(150, 100)), 0.5);
    });

    test('a vertical pinch zooms just as much as a horizontal one', () {
      // The bug this pins down: measuring only the horizontal component made
      // a near-vertical pinch report a scale of about 1, so the gesture looked
      // broken rather than subtle. The emulator's Ctrl+drag is vertical.
      final horizontal = PinchTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100));
      final vertical = PinchTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(100, 200));

      expect(horizontal.move(2, const Offset(300, 100)), 2.0);
      expect(vertical.move(2, const Offset(100, 300)), 2.0);
    });

    test('a diagonal pinch measures the straight-line distance', () {
      final tracker = PinchTracker();
      tracker.down(1, Offset.zero);
      tracker.down(2, const Offset(3, 4)); // 5pt apart.

      expect(tracker.move(2, const Offset(6, 8)), 2.0); // 10pt apart.
    });

    test('either finger may be the one that moves', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));

      expect(tracker.move(1, const Offset(0, 100)), 2.0);
    });

    test('two fingers landing in the same place do not divide by zero', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(100, 100));

      expect(tracker.move(2, const Offset(200, 100)), isNull);
    });

    test('an untracked pointer is ignored', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));

      expect(tracker.move(99, const Offset(500, 500)), isNull);
    });

    test('lifting a finger ends the pinch and leaves the other tracked', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));

      expect(tracker.up(2), isTrue);
      expect(tracker.isPinching, isFalse);
      expect(tracker.pointerCount, 1);
      // The remaining finger scrubs; it must not go on reporting a scale.
      expect(tracker.move(1, const Offset(400, 100)), isNull);
    });

    test('a third finger moves the pinch onto the newest two', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));

      // Measuring now runs between fingers 2 and 3, 100pt apart, and the
      // caller is told to re-anchor so the scale does not jump.
      expect(tracker.down(3, const Offset(300, 100)), isTrue);
      // The finger that dropped out of the pair no longer drives the scale.
      expect(tracker.move(1, const Offset(50, 100)), isNull);
      expect(tracker.move(3, const Offset(400, 100)), 2.0);
    });

    test('lifting back down to two fingers restarts from their distance', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));
      tracker.down(2, const Offset(200, 100));
      tracker.down(3, const Offset(300, 100));

      // Pair was 2-3; lifting 3 leaves 1-2, a different pair, so it restarts
      // from where those two are rather than from a distance neither of them
      // ever had.
      expect(tracker.up(3), isTrue);
      expect(tracker.isPinching, isTrue);
      expect(tracker.move(2, const Offset(300, 100)), 2.0);
    });

    test('a phantom pointer cannot wedge the gesture', () {
      // The failure this exists for: an up that never arrives used to leave a
      // finger on the track forever, and every later pinch found three
      // pointers and refused to measure. The newest two win, so the next real
      // pinch works.
      final tracker = PinchTracker();
      tracker.down(1, const Offset(0, 0)); // never lifted

      expect(tracker.down(2, const Offset(100, 100)), isTrue);
      expect(tracker.down(3, const Offset(200, 100)), isTrue);
      expect(tracker.isPinching, isTrue);
      expect(tracker.move(3, const Offset(300, 100)), 2.0);
    });

    test('lifting an untracked pointer changes nothing', () {
      final tracker = PinchTracker();
      tracker.down(1, const Offset(100, 100));

      expect(tracker.up(99), isFalse);
      expect(tracker.pointerCount, 1);
    });

    test('clear forgets everything', () {
      final tracker = PinchTracker()
        ..down(1, const Offset(100, 100))
        ..down(2, const Offset(200, 100))
        ..clear();

      expect(tracker.isPinching, isFalse);
      expect(tracker.pointerCount, 0);
    });
  });
}
