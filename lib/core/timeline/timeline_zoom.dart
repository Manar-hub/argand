/// The timeline's zoom arithmetic, kept apart from the widget that gestures it.
library;

import 'dart:math' as math;

/// Narrowest scale the timeline may be pinched to, in pixels per second.
const double minPixelsPerSecond = 4;

/// Widest scale, in pixels per second.
const double maxPixelsPerSecond = 240;

/// The scale the timeline opens at.
const double defaultPixelsPerSecond = 24;

/// Applies a pinch's [scale] to the scale a pinch began at.
double scalePixelsPerSecond(double startPixelsPerSecond, double scale) {
  if (!scale.isFinite || scale <= 0) return clampPixelsPerSecond(startPixelsPerSecond);
  return clampPixelsPerSecond(startPixelsPerSecond * scale);
}

/// Holds [value] inside the permitted range.
double clampPixelsPerSecond(double value) {
  if (!value.isFinite) return defaultPixelsPerSecond;
  return value.clamp(minPixelsPerSecond, maxPixelsPerSecond);
}

/// The scroll offset that puts [anchorMs] back under the playhead at
/// [pixelsPerSecond], given the content's [maxScrollExtent] at that scale.
double offsetForAnchor({
  required int anchorMs,
  required double pixelsPerSecond,
  required double maxScrollExtent,
}) {
  if (maxScrollExtent <= 0) return 0;
  final target = anchorMs / 1000 * pixelsPerSecond;
  return target.clamp(0.0, maxScrollExtent);
}

/// The project time sitting under the playhead at [offset].
int msAtOffset({required double offset, required double pixelsPerSecond}) {
  if (pixelsPerSecond <= 0) return 0;
  return math.max(0, (offset / pixelsPerSecond * 1000).round());
}
