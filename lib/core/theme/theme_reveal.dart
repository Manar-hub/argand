import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Switches the theme with a circle that grows out from where you tapped,
/// instead of a cross-fade.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({required this.child, super.key});

  final Widget child;

  static ThemeRevealState? of(BuildContext context) =>
      context.findAncestorStateOfType<ThemeRevealState>();

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();

  late final AnimationController _controller = AnimationController(
    // Long enough to read as a deliberate sweep, short enough that it never
    // stands between a tap and the result.
    duration: const Duration(milliseconds: 480),
    vsync: this,
  );

  ui.Image? _snapshot;
  Offset _center = Offset.zero;

  @override
  void dispose() {
    _snapshot?.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Runs [change], revealing the result from [center].
  Future<void> reveal({
    required Offset center,
    required VoidCallback change,
  }) async {
    // Already sweeping, or the user has asked for no animation.
    if (_controller.isAnimating ||
        MediaQuery.maybeDisableAnimationsOf(context) == true) {
      change();
      return;
    }

    final image = await _capture();
    if (!mounted) {
      image?.dispose();
      return;
    }

    if (image == null) {
      // Capture failed — the frame was not ready, or the boundary was gone.
      // Switching without the flourish is strictly better than not switching.
      change();
      return;
    }

    setState(() {
      _snapshot?.dispose();
      _snapshot = image;
      _center = center;
    });

    // The new theme is painted underneath the photograph, so it is fully
    // rendered before a single pixel of it is shown.
    change();

    try {
      // `.orCancel`, not a bare await.
      await _controller.forward(from: 0).orCancel;
    } on TickerCanceled {
      // Disposed while sweeping. The theme change already applied, which is
      // the part that mattered.
    } finally {
      if (mounted) {
        setState(() {
          _snapshot?.dispose();
          _snapshot = null;
        });
      }
    }
  }

  Future<ui.Image?> _capture() async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    // A boundary still waiting to paint would capture blank.
    if (object.debugNeedsPaint) return null;

    try {
      return await object.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Stack(
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (snapshot != null)
          Positioned.fill(
            // Input is swallowed for the duration. Half a second of dead taps
            // is better than a tap landing on a screen that is mid-wipe.
            child: AbsorbPointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _RevealPainter(
                    image: snapshot,
                    center: _center,
                    // Eases out, so it leaves quickly and settles rather than
                    // arriving at full speed.
                    progress: Curves.easeInOutCubic.transform(_controller.value),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints the old screen with a hole in it.
class _RevealPainter extends CustomPainter {
  const _RevealPainter({
    required this.image,
    required this.center,
    required this.progress,
  });

  final ui.Image image;
  final Offset center;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // The furthest corner from the tap. Anything less and the old screen would
    // still be showing in one corner when the animation ended.
    final radius = _maxRadius(size) * progress;

    final hole = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.save();
    canvas.clipPath(hole);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    canvas.restore();
  }

  double _maxRadius(Size size) {
    final dx = center.dx > size.width / 2 ? center.dx : size.width - center.dx;
    final dy =
        center.dy > size.height / 2 ? center.dy : size.height - center.dy;
    return Offset(dx, dy).distance;
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.progress != progress ||
      old.center != center ||
      !identical(old.image, image);
}
