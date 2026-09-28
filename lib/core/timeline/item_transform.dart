/// Where something sits in the output frame: a clip's picture, a text, a
/// layer's captions.
library;

import 'dart:math' as math;

/// Position, size and turn of one item in the frame.
class ItemTransform {
  const ItemTransform({
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.rotation = 0,
  });

  /// Untouched: centred, full size, upright.
  static const ItemTransform identity = ItemTransform();

  /// Where captions have always rendered: centred, near the bottom.
  static const ItemTransform captionDefault = ItemTransform(y: -0.82);

  /// The smallest and largest an item may be scaled to. Small enough to make
  /// a picture-in-picture, large enough to punch in on a face; past either
  /// end the item is either unreadable or a few enlarged pixels.
  static const double minScale = 0.25;
  static const double maxScale = 4;

  /// How close to a quarter turn a rotation has to come to land on it.
  static const double snapDegrees = 4;

  final double x;
  final double y;
  final double scale;
  final double rotation;

  ItemTransform copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
  }) {
    return ItemTransform(
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  /// This transform after a gesture that has, since it began, moved by ([panX],
  /// [panY]) in frame pixels (down positive, as the screen measures it), scaled
  /// by [pinch] and turned [turnRadians] clockwise.
  ItemTransform afterGesture({
    required double frameWidth,
    required double frameHeight,
    double panX = 0,
    double panY = 0,
    double pinch = 1,
    double turnRadians = 0,
  }) {
    return ItemTransform(
      x: x + (frameWidth > 0 ? panX / (frameWidth / 2) : 0),
      // Up is positive here and down is positive on screen.
      y: y - (frameHeight > 0 ? panY / (frameHeight / 2) : 0),
      scale: clampScale(scale * pinch),
      rotation: snapRotation(rotation + turnRadians * 180 / math.pi),
    );
  }

  /// Turned a quarter clockwise, as the Rotate tool does.
  ItemTransform quarterTurned() =>
      copyWith(rotation: snapRotation(rotation + 90));

  static double clampScale(double value) =>
      value.clamp(minScale, maxScale).toDouble();

  /// [degrees] brought into (-180, 180], and onto the nearest quarter turn when
  /// within [snapDegrees] of one.
  static double snapRotation(double degrees) {
    var value = degrees % 360;
    if (value > 180) value -= 360;
    if (value <= -180) value += 360;

    final quarter = (value / 90).round() * 90.0;
    if ((value - quarter).abs() <= snapDegrees) {
      value = quarter == -180 ? 180 : quarter;
    }
    return value;
  }

  /// The affine map this transform applies to a whole frame, in normalised
  /// device coordinates, as `(a, b, c, d, tx, ty)` with `x' = a*x + c*y + tx`
  /// and `y' = b*x + d*y + ty`.
  (double, double, double, double, double, double) ndcMatrix({
    required double frameWidth,
    required double frameHeight,
  }) {
    final hw = frameWidth / 2;
    final hh = frameHeight / 2;
    // Clockwise as seen, in a y-up space, is a negative mathematical angle.
    final theta = -rotation * math.pi / 180;
    final cos = math.cos(theta) * scale;
    final sin = math.sin(theta) * scale;

    return (
      cos, // a: x from x
      sin * hw / hh, // b: y from x
      -sin * hh / hw, // c: x from y
      cos, // d: y from y
      x, // tx
      y, // ty
    );
  }

  /// Part way from [a] to [b], turning the short way round, so a quarter turn
  /// from 180 to -90 animates as the 90 degrees it is and not as 270 back.
  static ItemTransform lerp(ItemTransform a, ItemTransform b, double t) {
    final turn = ((b.rotation - a.rotation + 540) % 360) - 180;
    return ItemTransform(
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      scale: a.scale + (b.scale - a.scale) * t,
      rotation: a.rotation + turn * t,
    );
  }

  Map<String, Object?> toJson() =>
      {'x': x, 'y': y, 'scale': scale, 'rotation': rotation};

  static ItemTransform fromJson(Map<String, Object?> json) {
    double read(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;

    return ItemTransform(
      x: read('x', 0),
      y: read('y', 0),
      scale: read('scale', 1),
      rotation: read('rotation', 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ItemTransform &&
      other.x == x &&
      other.y == y &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(x, y, scale, rotation);

  @override
  String toString() =>
      'ItemTransform(x: $x, y: $y, scale: $scale, rotation: $rotation)';
}
