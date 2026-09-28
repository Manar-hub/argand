import 'dart:ui' show Offset;

/// Turns raw pointer events into a pinch scale factor.
class PinchTracker {
  /// Insertion-ordered, which is what makes "the two most recent" meaningful.
  final Map<int, Offset> _points = {};

  /// The two pointers currently being measured, oldest first.
  List<int> _pair = const [];

  double _startDistance = 0;

  /// Whether two fingers are being measured.
  bool get isPinching => _pair.length == 2;

  /// How many pointers are being tracked, including any the pinch ignores.
  int get pointerCount => _points.length;

  /// Records a pointer landing.
  bool down(int pointer, Offset position) {
    _points[pointer] = position;
    return _choosePair();
  }

  /// Records a pointer moving.
  double? move(int pointer, Offset position) {
    if (!_points.containsKey(pointer)) return null;
    _points[pointer] = position;
    if (!isPinching || _startDistance <= 0) return null;
    if (!_pair.contains(pointer)) return null;
    return _spread / _startDistance;
  }

  /// Records a pointer lifting or being cancelled.
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
  double get _spread {
    if (_pair.length != 2) return 0;
    final a = _points[_pair[0]];
    final b = _points[_pair[1]];
    if (a == null || b == null) return 0;
    return (a - b).distance;
  }
}
