import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_panel_cells.dart';
import 'app_spacing.dart';
import 'app_surface.dart';

// A colour picker shared by the Style panel (caption and text colours) and
// the settings sheet (the action colour), so both pick colours the same way.

/// Colours offered as one-tap presets, beside the spectrum -- few enough to
/// fit the strip without scrolling; the spectrum reaches everything else.
const List<int> appColorSwatches = [
  0xFFFFFFFF,
  0xFF111111,
  0xFFFFE14D,
  0xFFFF4D4D,
  0xFF4DA3FF,
  0xFF5BE37D,
];

/// A colour: one-tap presets, and a spectrum for any other.
class AppColorPicker extends StatefulWidget {
  const AppColorPicker({
    super.key,
    required this.current,
    required this.onChanged,
    this.defaultLabel,
    this.swatches = appColorSwatches,
  });

  final int? current;
  final ValueChanged<int?> onChanged;
  final String? defaultLabel;

  /// The one-tap presets, as ARGB.
  final List<int> swatches;

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

class _AppColorPickerState extends State<AppColorPicker> {
  /// The spectrum's position while a thumb is held; null otherwise, when it
  /// follows [AppColorPicker.current].
  HSLColor? _dragging;

  /// The last hue a colour had, kept for white, black and greys, which have
  /// none of their own -- so dragging the shade of white does not jump to
  /// red.
  double _hue = 0;

  HSLColor get _shown {
    final dragging = _dragging;
    if (dragging != null) return dragging;
    final argb = widget.current;
    if (argb == null) return HSLColor.fromAHSL(1, _hue, 1, 0.5);
    final hsl = HSLColor.fromColor(Color(argb));
    return hsl.saturation < 0.02 ? hsl.withHue(_hue) : hsl;
  }

  void _drag(HSLColor color) => setState(() {
        _dragging = color;
        _hue = color.hue;
      });

  void _release() {
    final color = _dragging;
    if (color == null) return;
    setState(() => _dragging = null);
    widget.onChanged(color.toColor().toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final defaultLabel = widget.defaultLabel;
    final shown = _shown;
    final pure = HSLColor.fromAHSL(1, shown.hue, 1, 0.5).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One strip across the full width, a rule between colours, and the
        // chosen colour filling its whole cell -- the same pattern as every
        // other row of choices.
        AppStrip(
          onCard: true,
          // No Ts on the swatches' rules: plain lines between colours.
          tees: false,
          // A word needs about two swatches' width.
          flex: [
            if (defaultLabel != null) 2,
            for (final _ in widget.swatches) 1,
          ],
          children: [
            if (defaultLabel != null)
              AppChoice(
                selected: widget.current == null && _dragging == null,
                onTap: () => widget.onChanged(null),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                child: Text(
                  defaultLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final argb in widget.swatches)
              _Swatch(
                color: Color(argb),
                selected: argb == widget.current && _dragging == null,
                onTap: () => widget.onChanged(argb),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SpectrumTrack(
          label: l10n.styleHue,
          value: shown.hue / 360,
          colors: [
            for (var hue = 0; hue <= 360; hue += 30)
              HSLColor.fromAHSL(1, hue.toDouble(), 1, 0.5).toColor(),
          ],
          thumb: pure,
          onChanged: (t) => _drag(
            HSLColor.fromAHSL(
              1,
              (t * 360).clamp(0, 359.9),
              1,
              // Hue alone on a white or black would show no change at all;
              // take the pure colour instead.
              shown.lightness < 0.08 || shown.lightness > 0.92
                  ? 0.5
                  : shown.lightness,
            ),
          ),
          onChangeEnd: _release,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SpectrumTrack(
          label: l10n.styleShade,
          value: shown.lightness,
          colors: [Colors.black, pure, Colors.white],
          thumb: shown.toColor(),
          onChanged: (t) => _drag(
            HSLColor.fromAHSL(1, shown.hue, 1, t.clamp(0.0, 1.0)),
          ),
          onChangeEnd: _release,
        ),
      ],
    );
  }
}

/// One colour in the strip: a small square of it, which grows to fill the
/// whole cell when chosen.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  static const double _height = 38;
  static const double _dot = 18;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Semantics(
      label: '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _height,
          // Painted rather than laid out: the cell's width comes from the
          // strip, and the strip measures its height intrinsically, which a
          // LayoutBuilder cannot answer.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: motion,
            curve: Curves.easeOutCubic,
            builder: (context, grown, _) => CustomPaint(
              size: Size.infinite,
              painter: _SwatchPainter(
                color: color,
                grown: grown,
                dot: _dot,
                // A fine edge round the small square, so a swatch the colour of
                // its cell still shows -- white on paper, black on dark -- gone
                // once it fills. On dark it is faint ink, not a frame.
                bleed: surface.outlined ? surface.borderWidth : 0,
                outline: surface.outlined
                    ? surface.outline
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A swatch [grown] from a small centred square (0) to its whole cell (1).
class _SwatchPainter extends CustomPainter {
  _SwatchPainter({
    required this.color,
    required this.grown,
    required this.dot,
    required this.bleed,
    required this.outline,
  });

  final Color color;
  final double grown;
  final double dot;
  final double bleed;
  final Color? outline;

  @override
  void paint(Canvas canvas, Size size) {
    final small = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: dot,
      height: dot,
    );
    final full = Rect.fromLTRB(0, -bleed, size.width, size.height + bleed);
    final rect = Rect.lerp(small, full, grown)!;
    canvas.drawRect(rect, Paint()..color = color);
    if (outline != null && grown < 1) {
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..color = outline!.withValues(alpha: 1 - grown)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.color != color || old.grown != grown || old.outline != outline;
}

/// A gradient track with a thumb: the spectrum's two sliders.
class _SpectrumTrack extends StatelessWidget {
  const _SpectrumTrack({
    required this.label,
    required this.value,
    required this.colors,
    required this.thumb,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;

  /// Where the thumb sits, 0 to 1.
  final double value;

  final List<Color> colors;
  final Color thumb;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  static const double _thumbSize = 26;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;

    return Semantics(
      label: label,
      slider: true,
      value: '${(value * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // The thumb's centre travels between the ends, so the whole thumb
          // always stays on the track.
          final travel = width - _thumbSize;
          double at(Offset local) =>
              ((local.dx - _thumbSize / 2) / travel).clamp(0.0, 1.0);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A tap applies where it lands; a drag previews as it goes and
            // applies on release. Never both, so one gesture is one change.
            onTapUp: (details) {
              onChanged(at(details.localPosition));
              onChangeEnd();
            },
            onHorizontalDragStart: (details) =>
                onChanged(at(details.localPosition)),
            onHorizontalDragUpdate: (details) =>
                onChanged(at(details.localPosition)),
            onHorizontalDragEnd: (_) => onChangeEnd(),
            child: SizedBox(
              height: _thumbSize + 4,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: _thumbSize / 2 - 6,
                    right: _thumbSize / 2 - 6,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        border: surface.border,
                        gradient: LinearGradient(colors: colors),
                      ),
                    ),
                  ),
                  Positioned(
                    left: value.clamp(0.0, 1.0) * travel,
                    // A flat square of the chosen colour on the app's hard
                    // offset shadow, outlined where the theme outlines.
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: thumb,
                        border: surface.border,
                        boxShadow: [
                          BoxShadow(
                            color: surface.shadow,
                            offset: surface.offset / 2,
                            blurRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
