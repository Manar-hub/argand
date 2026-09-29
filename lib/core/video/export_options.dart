/// How the render should be framed and how large it should come out.
library;

import '../monetization/monetization.dart';

/// The size of the output, named by its short edge.
enum ExportQuality {
  /// Half the pixels of 1080p, and the only size the emulator's software
  /// encoder renders at a tolerable speed.
  p720(720),

  p1080(1080),

  /// "2K" as phones and platforms use the word: 2560x1440 landscape.
  p1440(1440),

  /// "4K": 3840x2160 landscape.
  p2160(2160),

  /// Whatever the first clip already is. No scaling stage at all, which is the
  /// only setting that cannot make the picture worse.
  source(null);

  const ExportQuality(this.shortEdge);

  /// Pixels on the short edge, or null to keep the source's own size.
  final int? shortEdge;

  /// What to assume while the source's size is unknown: every phone camera
  /// records at least this much, and offering more on a guess would offer an
  /// upscale.
  static const int _assumedShortEdge = 1080;

  /// Whether this size can be made from a source with [sourceShortEdge] pixels
  /// on its short edge without upscaling it.
  bool availableFor(int? sourceShortEdge) {
    final edge = shortEdge;
    if (edge == null) return true;
    return edge <= (sourceShortEdge ?? _assumedShortEdge);
  }

  /// This size, or the largest one the source can fill when this one would
  /// upscale it.
  ExportQuality fitTo(int? sourceShortEdge) {
    if (availableFor(sourceShortEdge)) return this;
    return values.lastWhere(
      (quality) => quality != source && quality.availableFor(sourceShortEdge),
      orElse: () => source,
    );
  }
}

/// The shape of the output frame.
enum ExportAspect {
  /// The source's own shape, untouched.
  source(null),

  /// Stories, Reels, Shorts.
  portrait9x16(9 / 16),

  square1x1(1),

  /// The tall feed post.
  portrait4x5(4 / 5),

  landscape16x9(16 / 9);

  const ExportAspect(this.ratio);

  /// Width divided by height, or null to keep the source's own shape.
  final double? ratio;
}

/// The mark drawn into a branded export.
const String watermarkText = 'Argand';

/// Which corner of the frame the watermark sits in.
enum WatermarkCorner {
  topLeft(-1, 1),
  topRight(1, 1),
  bottomLeft(-1, -1),
  bottomRight(1, -1);

  const WatermarkCorner(this.horizontal, this.vertical);

  /// -1 for the left edge, 1 for the right.
  final int horizontal;

  /// 1 for the top edge, -1 for the bottom -- normalised device coordinates,
  /// which is what Media3 anchors overlays in, so "up" is positive.
  final int vertical;

  /// How far in from the side the mark sits, as a share of the frame's width.
  static const double insetX = 0.03;

  /// How far in from the top or bottom, as a share of the frame's height.
  static const double insetY = 0.05;

  /// The anchor point in normalised device coordinates, where -1..1 spans the
  /// frame and the centre is 0.
  double get anchorX => horizontal * (1 - 2 * insetX);
  double get anchorY => vertical * (1 - 2 * insetY);
}

/// The logo watermark's plate height (logo plus padding), as a share of the
/// output's short edge. Mirrors WATERMARK_PLATE_FRACTION in
/// VideoExportChannel.kt.
const double watermarkPlateFraction = 0.06;

/// The padding round the logo on its plate, as a share of the logo's height.
const double watermarkPadFraction = 0.25;


/// A caption's text height at scale 1, as a share of the output's short edge.
const double captionTextFraction = 0.045;

/// A text layer's height at scale 1. Larger than a caption: a text is a title
/// or a label, placed on purpose, not a running subtitle.
const double textLayerFraction = 0.06;

/// Everything the export sheet collects.
class ExportOptions {
  const ExportOptions({
    this.quality = ExportQuality.p1080,
    this.aspect = ExportAspect.source,
    this.corner = WatermarkCorner.topRight,
    this.waiver,
  });

  /// What a person gets without touching anything: the shape they shot in, at
  /// a size every platform accepts, branded.
  static const ExportOptions defaults = ExportOptions();

  final ExportQuality quality;
  final ExportAspect aspect;

  /// Where the watermark goes when there is one.
  final WatermarkCorner corner;

  final WatermarkWaiver? waiver;

  /// Whether the render will carry the watermark.
  bool get watermark => waiver == null;

  /// A copy with the shape or size changed.
  ExportOptions copyWith({
    ExportQuality? quality,
    ExportAspect? aspect,
    WatermarkCorner? corner,
  }) {
    return ExportOptions(
      quality: quality ?? this.quality,
      aspect: aspect ?? this.aspect,
      corner: corner ?? this.corner,
    );
  }

  /// These options, rendered without the watermark.
  ExportOptions withWaiver(WatermarkWaiver waiver) => ExportOptions(
        quality: quality,
        aspect: aspect,
        corner: corner,
        waiver: waiver,
      );

  /// What crosses the channel.
  Map<String, Object?> encode() => {
        'aspectRatio': aspect.ratio,
        'shortEdge': quality.shortEdge,
        'watermark': watermark,
        'watermarkAnchorX': corner.anchorX,
        'watermarkAnchorY': corner.anchorY,
      };

  @override
  bool operator ==(Object other) =>
      other is ExportOptions &&
      other.quality == quality &&
      other.aspect == aspect &&
      other.corner == corner &&
      other.waiver == waiver;

  @override
  int get hashCode => Object.hash(quality, aspect, corner, waiver);
}

/// The pixel frame a render will produce.
typedef ExportFrame = ({int width, int height});

/// Works out the output frame for [options] over a source of this size.
ExportFrame? exportFrameFor({
  required ExportOptions options,
  required int sourceWidth,
  required int sourceHeight,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) return null;

  final sourceShortEdge =
      sourceWidth < sourceHeight ? sourceWidth : sourceHeight;
  final requested = options.quality.shortEdge ?? sourceShortEdge;

  return _frame(
    ratio: options.aspect.ratio ?? sourceWidth / sourceHeight,
    // Never above the source. The render refuses to upscale even when asked
    // (see `ExportQuality.availableFor`), so the promise must not either.
    shortEdge: requested < sourceShortEdge ? requested : sourceShortEdge,
  );
}

/// The output frame for a source known only by its shape.
ExportFrame? exportFrameForShape({
  required ExportOptions options,
  required double sourceRatio,
}) {
  final shortEdge = options.quality.shortEdge;
  if (shortEdge == null || sourceRatio <= 0) return null;

  return _frame(
    ratio: options.aspect.ratio ?? sourceRatio,
    shortEdge: shortEdge,
  );
}

ExportFrame _frame({required double ratio, required int shortEdge}) {
  // Which edge is short depends on the *output* shape, not the source's: a
  // portrait reframe of a landscape clip is short across, and sizing it by
  // height would produce a 1080-wide, 1920-tall frame from a "720p" request.
  final width = ratio < 1 ? shortEdge : (shortEdge * ratio).round();
  final height = ratio < 1 ? (shortEdge / ratio).round() : shortEdge;

  return (width: _even(width), height: _even(height));
}

/// H.264 encodes in 16x16 macroblocks and rejects odd dimensions outright, so
/// a ratio that lands on one is nudged down rather than failing the export.
int _even(int value) => value.isEven ? value : value - 1;

/// The shapes footage actually comes in, width over height.
const List<double> _standardRatios = [
  16 / 9, 9 / 16, 4 / 3, 3 / 4, 1, 4 / 5, 5 / 4, 3 / 2, 2 / 3, 21 / 9,
];

/// The source's shape, read back from a thumbnail of it.
({double ratio, bool exact}) mediaRatioFromThumbnail(int width, int height) {
  if (width <= 0 || height <= 0) return (ratio: 1, exact: false);

  final upper = width / height;
  final lower = width / (height + 1);

  for (final standard in _standardRatios) {
    if (standard > lower && standard <= upper) {
      return (ratio: standard, exact: true);
    }
  }
  return (ratio: upper, exact: false);
}
