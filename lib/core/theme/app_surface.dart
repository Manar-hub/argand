import 'package:flutter/material.dart';

/// The one visual pattern the whole app is built from: a flat fill, a solid
/// outline, and a hard offset shadow with no blur.
@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.outline,
    required this.shadow,
    required this.borderWidth,
    required this.radius,
    required this.offset,
    this.outlined = true,
  });

  /// Light: a thin near-black line on warm off-white, square-cornered, as in
  /// the reference (the Bruddle kit). The outline carries the structure, so
  /// it is a real line rather than a hairline divider.
  factory AppSurface.light() => const AppSurface(
        outline: Color(0xFF141414),
        shadow: Color(0xFF141414),
        borderWidth: 1.5,
        radius: 0,
        offset: Offset(4, 4),
      );

  /// Dark: no outline -- a card is told from the page by its lighter fill and
  /// lifted by the pale slab under it. The line's room is still kept, so
  /// switching themes moves nothing.
  factory AppSurface.dark() => const AppSurface(
        outline: Color(0xFFEDEAE3),
        shadow: Color(0xFFEDEAE3),
        borderWidth: 1.5,
        radius: 0,
        offset: Offset(4, 4),
        outlined: false,
      );

  final Color outline;
  final Color shadow;

  /// The outline's width, kept in both themes; drawn only when [outlined].
  final double borderWidth;

  /// Whether this theme draws its outline.
  final bool outlined;
  final double radius;

  /// Down and to the right, as in the reference.
  final Offset offset;

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// How far a pressed or chosen surface sinks: half the shadow's drop. The
  /// full drop read as sinking too deep.
  double get pressDepth => offset.dy / 2;

  /// The hard shadow on its own, for something that draws its own shape --
  /// an action button.
  BoxShadow get hardShadow =>
      BoxShadow(color: shadow, offset: offset, blurRadius: 0);

  /// The outline as a side, for a shape: see-through where it is not drawn,
  /// at the same width, so a box is the same size in both themes.
  BorderSide get side => BorderSide(
        color: outlined ? outline : const Color(0x00000000),
        width: borderWidth,
      );

  /// The outline as a box border, see-through where it is not drawn.
  Border get border => Border.fromBorderSide(side);

  /// A bordered surface filled with [fill], flat unless [raised].
  BoxDecoration decoration({required Color fill, bool raised = false}) {
    return BoxDecoration(
      color: fill,
      border: border,
      borderRadius: borderRadius,
      boxShadow: raised
          ? [BoxShadow(color: shadow, offset: offset, blurRadius: 0)]
          : null,
    );
  }

  /// How much room a raised surface needs beyond its own box, so a shadow is
  /// never clipped by a parent or overlapped by the next widget.
  EdgeInsets get shadowGutter =>
      EdgeInsets.only(right: offset.dx, bottom: offset.dy);

  /// Whether this theme's shadow reads against [ground].
  bool showsShadowOn(Color ground) {
    double luminance(Color c) => c.computeLuminance();
    final a = luminance(shadow) + 0.05;
    final b = luminance(ground) + 0.05;
    return (a > b ? a / b : b / a) > 1.2;
  }

  @override
  AppSurface copyWith({
    Color? outline,
    Color? shadow,
    double? borderWidth,
    double? radius,
    Offset? offset,
    bool? outlined,
  }) {
    return AppSurface(
      outline: outline ?? this.outline,
      shadow: shadow ?? this.shadow,
      borderWidth: borderWidth ?? this.borderWidth,
      radius: radius ?? this.radius,
      offset: offset ?? this.offset,
      outlined: outlined ?? this.outlined,
    );
  }

  @override
  AppSurface lerp(covariant AppSurface? other, double t) {
    if (other == null) return this;
    return AppSurface(
      outline: Color.lerp(outline, other.outline, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t),
      radius: lerpDouble(radius, other.radius, t),
      offset: Offset.lerp(offset, other.offset, t)!,
      outlined: t < 0.5 ? outlined : other.outlined,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// A fill that reads as physically pressed when [selected], the child moving
/// down with it and springing back a touch before it locks in.
class PressableSurface extends StatefulWidget {
  const PressableSurface({
    super.key,
    required this.selected,
    required this.fill,
    required this.child,
    this.borderRadius,
    this.border = false,
    this.raised = false,
  });

  final bool selected;
  final Color fill;
  final Widget child;

  /// Defaults to [AppSurface.borderRadius]. Overridable because a chip's
  /// pill shape is rounder than a card's corner.
  final BorderRadius? borderRadius;

  /// Whether the surface draws its own outline -- when the theme has one
  /// ([AppSurface.outlined]).
  final bool border;

  /// Whether the *unselected* surface casts the app's normal outward card
  /// shadow (`AppSurface.decoration`'s), for something that reads as a raised
  /// card at rest — a library row.
  final bool raised;

  @override
  State<PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<PressableSurface>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 120),
    vsync: this,
  )..value = widget.selected ? 1 : 0;

  /// A small overshoot going in — the surface travels slightly past where it
  /// settles, then springs back, the way a mechanical button does — and a
  /// plain ease coming back out, which doesn't need the same flourish.
  late final _depth = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(covariant PressableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected) return;
    if (widget.selected) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse(from: _controller.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final radius = widget.borderRadius ?? surface.borderRadius;

    return AnimatedBuilder(
      animation: _depth,
      builder: (context, child) {
        // The same distance drives the recess band and the child's own shift,
        // so the two never separate -- that's what makes the word read as
        // moving *with* the button rather than floating over it.
        final shift = surface.pressDepth * _depth.value;

        return ClipRRect(
          borderRadius: radius,
          child: CustomPaint(
            painter: _PressablePainter(
              shift: shift,
              fill: widget.fill,
              shadow: _pressedShadow,
              outline: widget.border && surface.outlined
                  ? surface.outline
                  : null,
              borderWidth: surface.borderWidth,
              radius: radius,
              raisedShadow:
                  widget.raised && _depth.value == 0 ? surface.shadow : null,
              raisedOffset: surface.offset,
            ),
            child: Transform.translate(offset: Offset(0, shift), child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Black regardless of theme — see the class doc on [PressableSurface].
const _pressedShadow = Color(0xFF141414);

class _PressablePainter extends CustomPainter {
  _PressablePainter({
    required this.shift,
    required this.fill,
    required this.shadow,
    required this.outline,
    required this.borderWidth,
    required this.radius,
    required this.raisedShadow,
    required this.raisedOffset,
  });

  /// How far the surface has sunk this frame, `0` at rest.
  final double shift;
  final Color fill;
  final Color shadow;
  final Color? outline;
  final double borderWidth;
  final BorderRadius radius;

  /// Non-null only fully at rest on a [PressableSurface.raised] instance —
  /// this and [shift] are never both active, so the card is never both lifted
  /// and sinking at once.
  final Color? raisedShadow;
  final Offset raisedOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;

    if (shift > 0) {
      // The recess the surface, drawn next and shifted down, uncovers along
      // the top.
      canvas.drawRRect(radius.toRRect(outer), Paint()..color = shadow);
    } else if (raisedShadow != null) {
      canvas.drawRRect(
        radius.toRRect(outer.shift(raisedOffset)),
        Paint()..color = raisedShadow!,
      );
    }

    // Bottom pinned to the canvas edge rather than trailing `shift` past it:
    // the outer `ClipRRect` would silently crop anything beyond `size.height`,
    // which is what made the bottom border vanish under a press.
    final surfaceRect = Rect.fromLTWH(0, shift, size.width, size.height - shift);
    final surfaceRRect = radius.toRRect(surfaceRect);
    canvas.drawRRect(surfaceRRect, Paint()..color = fill);
    if (outline != null) {
      canvas.drawRRect(
        surfaceRRect,
        Paint()
          ..color = outline!
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PressablePainter oldDelegate) {
    return shift != oldDelegate.shift ||
        fill != oldDelegate.fill ||
        outline != oldDelegate.outline ||
        raisedShadow != oldDelegate.raisedShadow;
  }
}

/// An action, lifted on the app's hard shadow: every button that *does*
/// something -- Export, Create project, a dialog's confirm -- stands off the
/// page, which is what tells it apart from a choice.
class AppRaised extends StatelessWidget {
  const AppRaised({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    // Pressed, the button travels onto its own shadow -- the shadow stays
    // where it is and the button covers it -- then springs back.
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [surface.hardShadow]),
      child: AppPressDown(travel: surface.offset, child: child),
    );
  }
}

/// Makes [child] give under the finger: it moves by [travel] while pressed and
/// springs back on release, the same feel as a pressed library row.
class AppPressDown extends StatefulWidget {
  const AppPressDown({super.key, required this.child, this.travel});

  final Widget child;
  final Offset? travel;

  @override
  State<AppPressDown> createState() => _AppPressDownState();
}

class _AppPressDownState extends State<AppPressDown> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final travel = widget.travel ?? Offset(0, surface.pressDepth);
    final still = MediaQuery.disableAnimationsOf(context);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _down ? 1 : 0),
        // Quick going in, a small spring coming back, as `PressableSurface`.
        duration: still
            ? Duration.zero
            : Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
        builder: (context, t, child) =>
            Transform.translate(offset: travel * t, child: child),
      ),
    );
  }
}

/// A button set *into* something -- the search square at the end of its field,
/// a cell of the timeline's toolbar -- that moves by [travel] while pressed and
/// comes back on release.
class AppPushIn extends StatefulWidget {
  const AppPushIn({
    super.key,
    required this.face,
    required this.travel,
    required this.child,
    this.clip = true,
  });

  final Color face;
  final Offset travel;
  final bool clip;
  final Widget child;

  @override
  State<AppPushIn> createState() => _AppPushInState();
}

class _AppPushInState extends State<AppPushIn> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final still = MediaQuery.disableAnimationsOf(context);

    final moving = TweenAnimationBuilder<double>(
      tween: Tween(end: _down ? 1 : 0),
      // Quick going in, eased coming out -- no spring past rest, which would
      // open the recess on the other sides.
      duration:
          still ? Duration.zero : Duration(milliseconds: _down ? 90 : 160),
      curve: Curves.easeOut,
      child: ColoredBox(color: widget.face, child: widget.child),
      builder: (context, t, child) => ColoredBox(
        // Only while moving: at rest an ink box under an identical face can
        // still show as a hairline at a fractional edge.
        color: t > 0 ? surface.outline : Colors.transparent,
        child: Transform.translate(offset: widget.travel * t, child: child),
      ),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: widget.clip ? ClipRect(child: moving) : moving,
    );
  }
}

/// Reaches the active [AppSurface] without every widget spelling out the
/// extension lookup.
extension AppSurfaceContext on BuildContext {
  /// Falls back to the matching default rather than throwing.
  AppSurface get surface {
    final theme = Theme.of(this);
    return theme.extension<AppSurface>() ??
        (theme.brightness == Brightness.dark
            ? AppSurface.dark()
            : AppSurface.light());
  }
}
