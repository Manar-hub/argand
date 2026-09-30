import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A glint of light crossing [child] -- the Get Pro buttons, so the gold reads
/// as metal rather than paint.
class AppShine extends StatefulWidget {
  const AppShine({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 250),
    this.period = const Duration(milliseconds: 1800),
    this.gap = const Duration(milliseconds: 3200),
    this.color = Colors.white,
  });

  final Widget child;

  /// The light's colour: white over gold, gold over a plain surface.
  final Color color;

  /// Before the first sweep: long enough for a sheet to finish rising.
  final Duration delay;

  /// One pass, edge to edge.
  final Duration period;

  /// The rest between passes.
  final Duration gap;

  @override
  State<AppShine> createState() => _AppShineState();
}

class _AppShineState extends State<AppShine>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: widget.period)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _next(widget.gap);
    });
  Timer? _start;

  void _next(Duration after) {
    _start?.cancel();
    _start = Timer(after, () {
      if (mounted) _sweep.forward(from: 0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _start?.cancel();
      _start = null;
      _sweep
        ..stop()
        ..value = 0;
      return;
    }
    if (_start != null || _sweep.isAnimating) return;
    _next(widget.delay);
  }

  @override
  void dispose() {
    _start?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _ShinePainter(
        CurvedAnimation(parent: _sweep, curve: Curves.easeInOut),
        widget.color,
      ),
      child: widget.child,
    );
  }
}

class _ShinePainter extends CustomPainter {
  _ShinePainter(this.progress, this.color) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  /// The light's tilt from vertical.
  static const _tilt = 20 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;

    final wide = size.width * 0.22;
    // Just far enough out at both ends that the tilted band is wholly off
    // the face, so the pass spends its time on the gold.
    final reach = wide / 2 + size.height * math.tan(_tilt);
    final x = lerpDouble(-reach, size.width + reach, t)!;

    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(x, size.height / 2)
      ..rotate(_tilt);

    void band(double width, double opacity, double offset) {
      final rect = Rect.fromCenter(
        center: Offset(offset, 0),
        width: width,
        height: size.height * 3,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    band(wide, 0.55, 0);
    band(wide * 0.16, 0.85, -wide * 0.62);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShinePainter old) => old.progress != progress;
}
