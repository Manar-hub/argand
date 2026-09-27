import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The few icons the app draws itself -- the ones on screen all the time:
/// export, the two settings, undo and redo, play and pause, fullscreen.
enum AppGlyph { export, settings, gear, undo, redo, play, pause, fullscreen }

/// One of the app's own icons, in the style's geometry rather than
/// Material's: **square caps, mitred corners, no rounding** -- the same hard
/// edges as every card and button -- with the sliders' knobs as squares, as
/// the app's own slider thumb (`AppSquareThumb`) is.
///
/// Drawn on Material's 24-unit grid at its 2-unit stroke, and sized and
/// coloured from the ambient [IconTheme] like an [Icon], so it drops into an
/// [IconButton] and follows its disabled colour and `iconSize`.
class AppIcon extends StatelessWidget {
  const AppIcon(this.glyph, {super.key, this.size, this.color});

  final AppGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    var color = this.color ?? theme.color ?? const Color(0xFF000000);
    if (theme.opacity case final opacity? when opacity < 1) {
      color = color.withValues(alpha: color.a * opacity);
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(glyph, color)),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final AppGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final solid = Paint()..color = color;

    Path poly(List<(double, double)> points) {
      final path = Path()..moveTo(points.first.$1, points.first.$2);
      for (final (x, y) in points.skip(1)) {
        path.lineTo(x, y);
      }
      return path;
    }

    switch (glyph) {
      case AppGlyph.export:
        // Into the tray: an open-headed arrow down, a square-cornered tray.
        canvas.drawPath(poly([(4, 14), (4, 20), (20, 20), (20, 14)]), line);
        canvas.drawPath(poly([(12, 4), (12, 15)]), line);
        canvas.drawPath(poly([(7.5, 10.5), (12, 15), (16.5, 10.5)]), line);

      case AppGlyph.settings:
        // Three sliders, each with a square knob.
        for (final (y, knob) in [(6.0, 15.0), (12.0, 8.0), (18.0, 13.5)]) {
          canvas.drawPath(poly([(3.5, y), (20.5, y)]), line);
          canvas.drawRect(
            Rect.fromCenter(center: Offset(knob, y), width: 5, height: 5),
            solid,
          );
        }

      case AppGlyph.gear:
        // Six square teeth on a ring, and the hole.
        const teeth = 6, outer = 10.2, ring = 7.0, half = 1.8;
        final path = Path();
        final gap = math.asin(half / ring);
        for (var i = 0; i < teeth; i++) {
          final a = i * 2 * math.pi / teeth - math.pi / 2;
          final axis = Offset(math.cos(a), math.sin(a));
          final across = Offset(-axis.dy, axis.dx);
          final foot = math.sqrt(ring * ring - half * half);
          final points = [
            axis * foot - across * half,
            axis * outer - across * half,
            axis * outer + across * half,
            axis * foot + across * half,
          ];
          for (final (j, p) in points.indexed) {
            final q = p + const Offset(12, 12);
            if (i == 0 && j == 0) {
              path.moveTo(q.dx, q.dy);
            } else {
              path.lineTo(q.dx, q.dy);
            }
          }
          // Round the ring to the next tooth.
          path.arcTo(
            Rect.fromCircle(center: const Offset(12, 12), radius: ring),
            a + gap,
            2 * math.pi / teeth - 2 * gap,
            false,
          );
        }
        path.close();
        canvas.drawPath(path, line);
        canvas.drawRect(
          Rect.fromCenter(center: const Offset(12, 12), width: 5, height: 5),
          line,
        );

      case AppGlyph.undo || AppGlyph.redo:
        // A hook with cut corners rather than an arc, back to an open head.
        if (glyph == AppGlyph.redo) {
          canvas
            ..translate(24, 0)
            ..scale(-1, 1);
        }
        canvas.drawPath(
          poly([(4, 9), (15.5, 9), (20, 13.5), (20, 15), (16, 19), (11, 19)]),
          line,
        );
        canvas.drawPath(poly([(8, 5), (4, 9), (8, 13)]), line);

      case AppGlyph.play:
        canvas.drawPath(
          poly([(7, 4.5), (19.5, 12), (7, 19.5)])..close(),
          solid,
        );

      case AppGlyph.pause:
        canvas
          ..drawRect(const Rect.fromLTWH(6, 5, 4.5, 14), solid)
          ..drawRect(const Rect.fromLTWH(13.5, 5, 4.5, 14), solid);

      case AppGlyph.fullscreen:
        // Four corner brackets.
        for (final corner in [
          [(4.0, 9.0), (4.0, 4.0), (9.0, 4.0)],
          [(15.0, 4.0), (20.0, 4.0), (20.0, 9.0)],
          [(20.0, 15.0), (20.0, 20.0), (15.0, 20.0)],
          [(9.0, 20.0), (4.0, 20.0), (4.0, 15.0)],
        ]) {
          canvas.drawPath(poly(corner), line);
        }
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
