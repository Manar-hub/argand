import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/media_converter.dart';
import '../../core/media/thumbnail_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/argand_logo.dart';
import '../../core/video/export_options.dart';
import '../../l10n/app_localizations.dart';
import 'transcript_repository.dart';

/// The frame an export will produce, drawn as large as the space allows.
class VideoCanvas extends StatelessWidget {
  const VideoCanvas({
    super.key,
    required this.ratio,
    required this.picture,
    this.overlay,
    this.foreground,
    this.safeZone = false,
    this.watermark,
    this.pickCorner,
    this.pickedCorner,
  });

  /// The output's width over its height.
  final double ratio;

  final Widget picture;

  /// Drawn along the bottom of the frame -- the captions, where they will be
  /// burned in.
  final Widget? overlay;

  /// Grey out where social apps put their buttons and text (preview only).
  final bool safeZone;

  /// Fills the frame over the picture and under the watermark: the stage's
  /// texts, captions and editing handles. Under the mark because that is the
  /// order the render composites them in.
  final Widget? foreground;

  /// Where to draw the watermark, or null to leave it off.
  final WatermarkCorner? watermark;

  /// Set while the watermark's corner is being chosen: every corner of the
  /// frame becomes a target, and a tap on one reports it here.
  final ValueChanged<WatermarkCorner>? pickCorner;

  /// The corner currently chosen, while [pickCorner] is set. Needed apart
  /// from [watermark] because the mark may be hidden from the preview, and
  /// the chosen corner still has to be shown -- as a firmer outline.
  final WatermarkCorner? pickedCorner;

  @override
  Widget build(BuildContext context) {
    final pickCorner = this.pickCorner;
    final picked = pickCorner == null ? null : pickedCorner;

    return Center(
      child: AspectRatio(
        aspectRatio: ratio,
        child: LayoutBuilder(
          builder: (context, frame) {
            final corner = watermark;
            final shortEdge = math.min(frame.maxWidth, frame.maxHeight);
            final motion = MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220);

            // The mark's inset from each edge, the same shares the render's
            // anchor encodes.
            final inset = EdgeInsets.symmetric(
              horizontal: frame.maxWidth * WatermarkCorner.insetX,
              vertical: frame.maxHeight * WatermarkCorner.insetY,
            );

            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  picture,
                  if (overlay case final overlay?)
                    Positioned(left: 0, right: 0, bottom: 0, child: overlay),
                  ?foreground,
                  if (safeZone)
                    const IgnorePointer(
                      child: CustomPaint(painter: _SafeZonePainter()),
                    ),
                  if (pickCorner != null)
                    for (final target in WatermarkCorner.values)
                      if (target != picked)
                        Padding(
                          padding: inset,
                          child: Align(
                            alignment: _alignmentOf(target),
                            child: _CornerGhost(
                              child: WatermarkMark(shortEdge: shortEdge),
                            ),
                          ),
                        ),
                  // The chosen corner, when the mark itself is hidden.
                  if (picked != null && corner == null)
                    Padding(
                      padding: inset,
                      child: AnimatedAlign(
                        alignment: _alignmentOf(picked),
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: _CornerGhost(
                          firm: true,
                          child: WatermarkMark(shortEdge: shortEdge),
                        ),
                      ),
                    ),
                  if (corner != null)
                    Padding(
                      padding: inset,
                      child: AnimatedAlign(
                        alignment: _alignmentOf(corner),
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: WatermarkMark(shortEdge: shortEdge),
                      ),
                    ),
                  if (pickCorner != null)
                    _CornerTargets(
                      selected: picked,
                      onPicked: pickCorner,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static Alignment _alignmentOf(WatermarkCorner corner) => Alignment(
        corner.horizontal.toDouble(),
        // Alignment's y grows downward; the corner's, like the render's
        // normalised coordinates, grows upward.
        -corner.vertical.toDouble(),
      );
}

/// Where the mark could go: its outline, faint, in a free corner -- or firm,
/// in the chosen one while the mark is hidden from the preview.
class _CornerGhost extends StatelessWidget {
  const _CornerGhost({required this.child, this.firm = false});

  /// The mark itself, kept only for its size.
  final Widget child;

  final bool firm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        // A soft frosted patch over any footage, not a frame: these sit on
        // the picture, not the theme.
        color: firm ? const Color(0x59FFFFFF) : const Color(0x26FFFFFF),
      ),
      child: Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: child,
      ),
    );
  }
}

/// Each quarter of the frame as a target for its corner, so a thumb need
/// not find the corner exactly.
class _CornerTargets extends StatelessWidget {
  const _CornerTargets({required this.selected, required this.onPicked});

  final WatermarkCorner? selected;
  final ValueChanged<WatermarkCorner> onPicked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String nameOf(WatermarkCorner value) => switch (value) {
          WatermarkCorner.topLeft => l10n.watermarkTopLeft,
          WatermarkCorner.topRight => l10n.watermarkTopRight,
          WatermarkCorner.bottomLeft => l10n.watermarkBottomLeft,
          WatermarkCorner.bottomRight => l10n.watermarkBottomRight,
        };

    return Column(
      children: [
        for (final row in const [
          [WatermarkCorner.topLeft, WatermarkCorner.topRight],
          [WatermarkCorner.bottomLeft, WatermarkCorner.bottomRight],
        ])
          Expanded(
            child: Row(
              children: [
                for (final target in row)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: target == selected,
                      label: nameOf(target),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onPicked(target),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The watermark as the render draws it: the name in white on a dark plate.
class WatermarkMark extends StatelessWidget {
  const WatermarkMark({super.key, required this.shortEdge});

  /// The short edge of the frame it is drawn on, in logical pixels.
  final double shortEdge;

  @override
  Widget build(BuildContext context) {
    // The top bar's lockup on a translucent plate, sized as the render sizes
    // the PNG it is given (`ArgandLogo.watermarkPng`).
    final plate = math.max(shortEdge * watermarkPlateFraction, 8.0);
    final logo = plate / (1 + 2 * watermarkPadFraction);
    return ColoredBox(
      color: watermarkPlateColor,
      child: Padding(
        padding: EdgeInsets.all(logo * watermarkPadFraction),
        child: ArgandLogo(
          semanticLabel: watermarkText,
          height: logo,
          ink: Colors.white,
          hand: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// The project's first frame, shown in the output's shape.
class ProjectFramePreview extends ConsumerStatefulWidget {
  const ProjectFramePreview({
    super.key,
    required this.projectId,
    required this.options,
    required this.showWatermark,
    this.maxHeight = 200,
  });

  final String projectId;
  final ExportOptions options;
  final bool showWatermark;
  final double maxHeight;

  @override
  ConsumerState<ProjectFramePreview> createState() =>
      _ProjectFramePreviewState();
}

class _ProjectFramePreviewState extends ConsumerState<ProjectFramePreview> {
  /// Used only while the first thumbnail is still resolving, which lasts a
  /// frame or two. Landscape because most footage is, so the box rarely has to
  /// change shape once the real answer arrives.
  static const double _unknownRatio = 16 / 9;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _watching;
  double? _sourceRatio;

  /// Whether [_sourceRatio] is known exactly, rather than to the precision of
  /// a 160-pixel thumbnail. Only an exact ratio may be turned into a promised
  /// pixel size.
  bool _sourceRatioExact = false;

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  /// Reads the frame's own width and height, so "Source" can be drawn true.
  void _watch(String path) {
    if (_watching == path) return;
    _watching = path;
    _detach();

    final listener = ImageStreamListener(
      (info, _) {
        final shape = mediaRatioFromThumbnail(
          info.image.width,
          info.image.height,
        );
        // This listener owns the handle it was given; the decoded image itself
        // stays in the cache for the `Image.file` below to draw.
        info.dispose();
        if (!mounted) return;
        setState(() {
          _sourceRatio = shape.ratio;
          _sourceRatioExact = shape.exact;
        });
      },
      // A frame that will not decode simply leaves the fallback shape in
      // place. The sheet still works; it just cannot promise a preview.
      onError: (_, _) {},
    );

    _stream = FileImage(File(path)).resolve(ImageConfiguration.empty)
      ..addListener(listener);
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final l10n = AppLocalizations.of(context);

    final clips = ref.watch(projectClipsProvider(widget.projectId)).value;
    final clip = (clips == null || clips.isEmpty) ? null : clips.first;

    final frames = clip == null
        ? const <String>[]
        : ref
                .watch(clipFramesProvider(
                  mediaPath: clip.mediaPath,
                  cacheDir: ref.watch(mediaConverterProvider).thumbnailDirFor(
                        clipId: clip.id,
                        mediaPath: clip.mediaPath,
                      ),
                  count: 1,
                ))
                .value ??
            const <String>[];

    if (frames.isNotEmpty) _watch(frames.first);

    final ratio =
        widget.options.aspect.ratio ?? _sourceRatio ?? _unknownRatio;

    final picture = frames.isEmpty
        ? const SizedBox.shrink()
        : Image.file(
            File(frames.first),
            // Fitted, with black around it, as the render fits it.
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Padding(
            padding: surface.shadowGutter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: AspectRatio(
                aspectRatio: ratio,
                child: DecoratedBox(
                  decoration: surface.decoration(
                    fill: theme.colorScheme.surfaceContainerHighest,
                    // The picture is what the editor is about: raised.
                    raised: true,
                  ),
                  child: ClipRRect(
                    borderRadius: surface.borderRadius,
                    child: VideoCanvas(
                      ratio: ratio,
                      picture: picture,
                      watermark:
                          widget.showWatermark ? widget.options.corner : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_frameLabel(l10n, ratio) case final label?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// The pixel size, when it is actually known.
  String? _frameLabel(AppLocalizations l10n, double ratio) {
    if (widget.options.aspect.ratio == null && !_sourceRatioExact) {
      return null;
    }

    final frame = exportFrameForShape(
      options: widget.options,
      sourceRatio: ratio,
    );
    if (frame == null) return null;

    return l10n.exportFrameSize(frame.width, frame.height);
  }
}

/// The watermark's plate, in the preview and the rendered PNG.
const Color watermarkPlateColor = Color(0x66000000);

/// The parts of a vertical video that TikTok, Reels and Shorts cover with
/// their buttons, captions and bars, measured on a 1080x1920 template: 254 px
/// at the top, 381 at the bottom, 120 on the left, and on the right 129 px
/// down to y = 720, then 201 px where the like and share column sits. Kept as
/// shares of the frame, so any stage size gets the same zones.
List<Rect> unsafeRects(Size frame) {
  final w = frame.width;
  final h = frame.height;
  final top = h * 254 / 1920;
  final bottom = h - h * 381 / 1920;
  final left = w * 120 / 1080;
  final rightUpper = w - w * 129 / 1080;
  final rightLower = w - w * 201 / 1080;
  final turn = h * 720 / 1920;
  return [
    Rect.fromLTRB(0, 0, w, top),
    Rect.fromLTRB(0, bottom, w, h),
    Rect.fromLTRB(0, top, left, bottom),
    Rect.fromLTRB(rightUpper, top, w, turn),
    Rect.fromLTRB(rightLower, turn, w, bottom),
  ];
}

class _SafeZonePainter extends CustomPainter {
  const _SafeZonePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x59808080);
    for (final rect in unsafeRects(size)) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SafeZonePainter oldDelegate) => false;
}
