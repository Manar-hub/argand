/// The timeline's zoom arithmetic, kept apart from the widget that gestures it.
///
/// Extracted because the gesture and the arithmetic fail in completely
/// different ways. A pinch that does not fire is obvious the first time anyone
/// tries it; an anchor computed against the wrong scale is a few pixels of
/// drift that only shows up after several zooms, and by then it looks like the
/// timeline is simply imprecise. These are the parts that can be proven on the
/// host, so they are.
library;

import 'dart:math' as math;

/// Narrowest scale the timeline may be pinched to, in pixels per second.
///
/// A floor exists so a long project cannot collapse into a strip too small to
/// aim a finger at.
const double minPixelsPerSecond = 4;

/// Widest scale, in pixels per second.
///
/// Set by what sentence text needs rather than by anything about the media: at
/// 240 a one-second sentence is 240pt wide, which is a readable line.
const double maxPixelsPerSecond = 240;

/// The scale the timeline opens at.
const double defaultPixelsPerSecond = 24;

/// Applies a pinch's [scale] to the scale a pinch began at.
///
/// Multiplicative rather than additive, so a pinch feels the same whether it
/// starts zoomed in or out — doubling the distance between two fingers doubles
/// the scale at either end of the range.
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
///
/// **The offset is the playhead.** The track is padded by half the viewport at
/// each end, so the pixel under the centre line is exactly `offset` pixels into
/// the project — which is what makes this a multiplication rather than a
/// correction against the viewport width.
///
/// Clamped, because the anchor may sit beyond what the new scale can scroll to:
/// zooming out shortens the content, and the moment that was under the playhead
/// can end up past the end of it.
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
///
/// The exact inverse of [offsetForAnchor] before clamping, and the single
/// conversion from pixels back to time — the scrub and the zoom anchor both
/// read the playhead through this, so they cannot disagree about where it is.
int msAtOffset({required double offset, required double pixelsPerSecond}) {
  if (pixelsPerSecond <= 0) return 0;
  return math.max(0, (offset / pixelsPerSecond * 1000).round());
}
