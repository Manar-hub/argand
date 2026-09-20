import 'dart:ui' show Offset;

/// Turns raw pointer events into a pinch scale factor.
///
/// **Exists because a gesture recogniser could not be used here.** The
/// timeline's scale sits inside a horizontally scrolling view, and the
/// scroll's own drag recogniser claims the gesture the moment it passes touch
/// slop — a `ScaleGestureRecognizer` in the same arena is rejected and its
/// callbacks never fire, so a pinch reads as a sideways drag and nothing else.
/// Raw pointer events take no part in the arena, so they arrive whatever else
/// has claimed the pointer; this is the small amount of bookkeeping that
/// replaces the recogniser.
///
/// **It pinches with the two most recent fingers and re-baselines whenever
/// that pair changes.** Bookkeeping built on pointer ids has to assume every
/// down is matched by an up, and a missed one would otherwise leave a phantom
/// finger on the track that quietly breaks every later pinch — a gesture that
/// works once and then never again. Choosing the newest two means a stale
/// pointer is ignored as soon as two real ones arrive, so the tracker recovers
/// by itself rather than needing to be right every time.
///
/// Keeping it apart from the widget is what makes it testable: a pinch cannot
/// be injected into an emulator without root, so the alternative was shipping
/// it unproven.
class PinchTracker {
  /// Insertion-ordered, which is what makes "the two most recent" meaningful.
  final Map<int, Offset> _points = {};

  /// The two pointers currently being measured, oldest first.
  List<int> _pair = const [];

  double _startDistance = 0;

  /// Whether two fingers are being measured.
  ///
  /// The caller disables scrolling while this holds, so a pinch does not also
  /// scrub the player.
  bool get isPinching => _pair.length == 2;

  /// How many pointers are being tracked, including any the pinch ignores.
  int get pointerCount => _points.length;

  /// Records a pointer landing.
  ///
  /// Returns true when the caller should re-capture what the pinch is anchored
  /// to — either a pinch just began, or the pair being measured changed.
  bool down(int pointer, Offset position) {
    _points[pointer] = position;
    return _choosePair();
  }

  /// Records a pointer moving.
  ///
  /// Returns the scale relative to where the current pinch began, or null when
  /// there is nothing to scale — fewer than two fingers, a pointer that is not
  /// one of the measured pair, or a pair that began with no distance between
  /// them.
  double? move(int pointer, Offset position) {
    if (!_points.containsKey(pointer)) return null;
    _points[pointer] = position;
    if (!isPinching || _startDistance <= 0) return null;
    if (!_pair.contains(pointer)) return null;
    return _spread / _startDistance;
  }

  /// Records a pointer lifting or being cancelled.
  ///
  /// Returns true when the caller should re-sync: the pinch ended, or it
  /// continues between a different pair and must start afresh from their
  /// current distance rather than jumping.
  bool up(int pointer) {
    if (_points.remove(pointer) == null) return false;
    final wasPinching = isPinching;
    final rebaselined = _choosePair();
    return rebaselined || wasPinching != isPinching;
  }

  /// Forgets every pointer — for a widget being disposed mid-gesture.
  void clear() {
    _points.clear();
    _pair = const [];
    _startDistance = 0;
  }

  /// Picks the two most recent pointers, restarting the measurement if that is
  /// a different pair than before. Returns whether it restarted.
  bool _choosePair() {
    final ids = _points.keys.toList(growable: false);
    final next = ids.length >= 2
        ? ids.sublist(ids.length - 2)
        : const <int>[];

    if (next.length == _pair.length &&
        (next.isEmpty || (next[0] == _pair[0] && next[1] == _pair[1]))) {
      return false;
    }

    _pair = next;
    _startDistance = _spread;
    return isPinching;
  }

  /// Straight-line distance between the measured pair.
  ///
  /// Deliberately not the horizontal component alone, even though the axis
  /// being zoomed is horizontal. A pinch is rarely axis-aligned, and measuring
  /// only the horizontal part makes a near-vertical pinch report a scale of
  /// about 1 — which reads as the gesture doing nothing rather than as it
  /// zooming a little.
  double get _spread {
    if (_pair.length != 2) return 0;
    final a = _points[_pair[0]];
    final b = _points[_pair[1]];
    if (a == null || b == null) return 0;
    return (a - b).distance;
  }
}
