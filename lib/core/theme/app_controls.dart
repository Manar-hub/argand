import 'package:flutter/material.dart';

import 'app_surface.dart';

/// A square slider thumb standing on the app's hard offset shadow: the
/// sharp-corner style has no round parts, and Material's thumb is a disc.
class AppSquareThumb extends SliderComponentShape {
  const AppSquareThumb({
    required this.outline,
    required this.shadow,
    required this.offset,
    this.side = 18,
  });

  /// Null where the theme draws no outline (dark).
  final Color? outline;
  final Color shadow;
  final Offset offset;
  final double side;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(side);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: side, height: side);
    final enabled = enableAnimation.value > 0.5;
    final fill = enabled
        ? (sliderTheme.thumbColor ?? Colors.black)
        : (sliderTheme.disabledThumbColor ?? Colors.grey);

    if (enabled) canvas.drawRect(rect.shift(offset), Paint()..color = shadow);
    canvas.drawRect(rect, Paint()..color = fill);
    if (outline != null) {
      canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..color = outline!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }
}

/// An on/off control in the sharp-corner style: a square track and a square
/// thumb that slides across, the action colour when on.
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables it.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    // On dark there is no outline, so the off track takes the page's tone
    // to stand off whatever card it sits on.
    final offTrack = surface.outlined
        ? scheme.surfaceContainerHighest
        : scheme.surface;

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.38,
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            width: 48,
            height: 26,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? scheme.primary : offTrack,
              border: surface.border,
            ),
            child: AnimatedAlign(
              duration: motion,
              curve: Curves.easeOutCubic,
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                color: value ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
