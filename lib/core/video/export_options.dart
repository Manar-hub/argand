/// How the render should be framed and how large it should come out.
///
/// Pure data, kept out of the widget that collects it and out of the channel
/// that sends it, so the mapping from a chosen preset to the numbers Media3
/// wants can be read -- and tested -- without a device.
library;

import '../monetization/monetization.dart';

/// The size of the output, named by its **short edge**.
///
/// Short edge rather than height, because the presets have to mean the same
/// thing in both orientations: "1080p" is 1920x1080 landscape and 1080x1920
/// portrait, and a person choosing it for a 9:16 reel is asking for the
/// familiar one, not for a 608-pixel-wide sliver.
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

  /// Whether this size can be made from a source with [sourceShortEdge]
  /// pixels on its short edge without **upscaling** it.
  ///
  /// A 4K export of a 1080p clip is the same picture in a file four times the
  /// size, blurrier for the resample. Offering it would sell a number rather
  /// than a sharper video, so sizes above the source are not offered. This is
  /// a limit of the footage, not a paywall: nothing here depends on Pro.
  bool availableFor(int? sourceShortEdge) {
    final edge = shortEdge;
    if (edge == null) return true;
    return edge <= (sourceShortEdge ?? _assumedShortEdge);
  }

  /// This size, or the largest one the source can fill when this one would
  /// upscale it.
  ///
  /// What a stored choice means for a particular source: a project set to 4K
  /// whose clip is 1080p exports at 1080p rather than stretching. Falls back
  /// to [source] when even the smallest preset is bigger than the clip.
  ExportQuality fitTo(int? sourceShortEdge) {
    if (availableFor(sourceShortEdge)) return this;
    return values.lastWhere(
      (quality) => quality != source && quality.availableFor(sourceShortEdge),
      orElse: () => source,
    );
  }
}

/// The shape of the output frame.
///
/// Stored as **width over height**, the convention `Presentation` itself uses,
/// so nothing has to be inverted on the way down to the encoder.
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
///
/// **Must match `WATERMARK_TEXT` in `VideoExportChannel.kt`.** It is the
/// product's name rather than interface text, so it is not localised: a
/// translated watermark would be a different brand in every market.
const String watermarkText = 'Argand';

/// Which corner of the frame the watermark sits in.
///
/// Carries its own geometry so the preview and the native render cannot
/// disagree about where "upper right" is: both read the same two numbers.
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
  ///
  /// Larger than [insetX] because a frame's top and bottom are where players
  /// draw their own controls, and a mark tucked under them is a mark nobody
  /// sees.
  static const double insetY = 0.05;

  /// The anchor point in normalised device coordinates, where -1..1 spans the
  /// frame and the centre is 0.
  double get anchorX => horizontal * (1 - 2 * insetX);
  double get anchorY => vertical * (1 - 2 * insetY);
}

/// The watermark's text height, as a share of the output's short edge.
///
/// **Must match `WATERMARK_TEXT_FRACTION` in `VideoExportChannel.kt`**, so the
/// mark in the preview is the size it will be in the file.
const double watermarkTextFraction = 0.030;

/// Everything the export sheet collects.
///
/// [waiver] is what leaves the watermark off. **It is a waiver rather than a
/// boolean** because a boolean could be set by anything, and removing the
/// watermark has to be earned -- by a finished rewarded ad or by Pro, the only
/// two things that can create one (see `WatermarkWaiver`). Without a waiver the
/// small Argand mark is drawn into the picture by the same overlay pass as the
/// captions.
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
  ///
  /// **Keeps no waiver.** A waiver pays for one export with the options the
  /// user was looking at; carrying it through an edit would let one ad cover
  /// whatever was chosen afterwards. [withWaiver] is the one way to attach it.
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
  ///
  /// **Nulls are sent, not omitted.** A missing key and a key holding null mean
  /// the same thing on the far side -- keep the source's own value -- and
  /// sending both shapes for one meaning is how a reader ends up handling only
  /// the one it was written against.
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
///
/// Lives here rather than only in Kotlin so the dialog can say what the file
/// will be before anything is encoded, and so the arithmetic is provable on the
/// host. The native side computes the same frame from the same inputs; the two
/// are checked against each other by reading the dimensions back off an
/// exported file.
///
/// [sourceWidth] and [sourceHeight] describe what the viewer sees, rotation
/// already applied -- a phone video stored landscape with a 90-degree flag is
/// passed in portrait.
typedef ExportFrame = ({int width, int height});

/// Works out the output frame for [options] over a source of this size.
///
/// Returns null when the source size is not known, because a frame guessed
/// from nothing is worse than a dialog that declines to promise one.
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
///
/// What the export sheet can answer from a thumbnail: the shape is known, the
/// pixel count is not. So this answers only when the quality preset names a
/// size, and returns null for Source quality, which needs the real pixels.
///
/// **Takes the ratio itself rather than stand-in dimensions.** Passing a shape
/// through made-up whole numbers rounds it -- 9:16 at a scale of 1000 is 563
/// by 1000, which is 0.563, which promised 720x1278 for a 720x1280 render.
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
///
/// Used only to recognise a source's shape from a small thumbnail; see
/// [mediaRatioFromThumbnail].
const List<double> _standardRatios = [
  16 / 9, 9 / 16, 4 / 3, 3 / 4, 1, 4 / 5, 5 / 4, 3 / 2, 2 / 3, 21 / 9,
];

/// The source's shape, read back from a thumbnail of it.
///
/// **The thumbnail is exact in width and truncated in height.** The native
/// side writes it 160 pixels wide and scales the height to match, dropping the
/// fraction -- so a 9:16 clip comes back 160x284, which reads as 0.5634 rather
/// than 0.5625. That was enough for the export sheet to promise 720x1278 for a
/// render that came out 720x1280.
///
/// The true ratio lies somewhere in `(width / (height + 1), width / height]`.
/// When a standard shape falls in that window it is the answer, and
/// [exact] is true. Otherwise the thumbnail's own ratio is returned with
/// [exact] false: close enough to draw the preview, not close enough to print
/// a pixel size from.
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
