import 'package:flutter/material.dart';

/// The one visual pattern the whole app is built from: a flat fill, a solid
/// outline, and a **hard offset shadow with no blur**.
///
/// Zero blur is what makes it read as neo-brutalist rather than as ordinary
/// Material elevation — a blurred shadow is a light source, an offset one is a
/// printed layer. Because it is the signature move, it lives in exactly one
/// place; a second definition somewhere would drift and the app would stop
/// looking like itself.
///
/// A [ThemeExtension] rather than constants, because the rule genuinely differs
/// between themes: the outline and the shadow are near-black on a light ground
/// and off-white on a dark one, because a black shadow on `#161616` is not a
/// subtler shadow, it is no shadow. Anything reading these values gets the
/// right ones for the active theme without asking which one is on.
@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.outline,
    required this.shadow,
    required this.borderWidth,
    required this.radius,
    required this.offset,
  });

  /// Light: near-black on warm off-white. The outline carries the structure,
  /// so it is a real line rather than a hairline divider.
  factory AppSurface.light() => const AppSurface(
        outline: Color(0xFF141414),
        shadow: Color(0xFF141414),
        borderWidth: 2,
        radius: 14,
        offset: Offset(0, 4),
      );

  /// Dark inverts the same rule: the shadow is a *pale* slab, because a black
  /// one on a `#161616` ground is not a subtler shadow, it is no shadow — dark
  /// cards sat flat while light cards were raised, and the two themes stopped
  /// being one design.
  ///
  /// It is deliberately **dimmer than the outline**, which light does not need
  /// to be. On paper, ink at full strength is just ink; on near-black, the
  /// same move at full strength puts the brightest thing on the screen behind
  /// the card rather than in it, and the eye goes to the shadow instead of the
  /// content. Pulling it back to a mid grey keeps the card lifted while
  /// leaving the outline as the strongest edge, which is the job the outline
  /// is for.
  ///
  /// A solid grey rather than the outline at low alpha, so the value does not
  /// change with whatever the shadow happens to fall across.
  factory AppSurface.dark() => const AppSurface(
        outline: Color(0xFFEDEAE3),
        shadow: Color(0xFF6E6B65),
        borderWidth: 2,
        radius: 14,
        offset: Offset(0, 4),
      );

  final Color outline;
  final Color shadow;
  final double borderWidth;
  final double radius;

  /// Straight down, with no sideways component.
  ///
  /// A diagonal offset is the more common take on this style, but it makes a
  /// full-width card look skewed — the shadow runs off one edge and not the
  /// other. Dropping it vertically keeps wide surfaces square, which is what
  /// reference image 3 does and why its cards sit calmly at phone width.
  final Offset offset;

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// A bordered, optionally raised surface filled with [fill].
  ///
  /// [raised] is false for things that sit *in* the page rather than on it —
  /// an inset field, a row inside an already-raised card. Nesting one offset
  /// shadow inside another reads as noise, which is the trap this style falls
  /// into when every element is treated as a card.
  BoxDecoration decoration({required Color fill, bool raised = true}) {
    return BoxDecoration(
      color: fill,
      border: Border.all(color: outline, width: borderWidth),
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
  ///
  /// Both themes must pass. A shadow that cannot be seen is not a quieter
  /// version of the style, it is the style missing from one theme.
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
  }) {
    return AppSurface(
      outline: outline ?? this.outline,
      shadow: shadow ?? this.shadow,
      borderWidth: borderWidth ?? this.borderWidth,
      radius: radius ?? this.radius,
      offset: offset ?? this.offset,
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
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// A fill that reads as physically pressed when [selected], the child moving
/// down with it and springing back a touch before it locks in.
///
/// A hard-edged band of shadow shows along the top when pressed — always a
/// near-black (`_pressedShadow`), regardless of theme: a shadow inside a
/// recess only reads as a shadow when it is genuinely dark, unlike
/// [AppSurface.dark]'s deliberately pale outward shadow, which exists for a
/// *raised* card against a near-black ground, a different situation. No
/// blur, matching every shadow this app draws.
///
/// **Painted, not bordered.** A first version used [BoxDecoration.border]
/// with a thickened top side, which is simple but has a real Flutter
/// limitation: a [Border] with differing per-side widths is not "uniform",
/// and `BoxDecoration` only honours `borderRadius` for a uniform border — the
/// pressed band silently squared off every corner, most visible on the near-
/// white dark-theme outline. A [CustomPainter] draws both the recess and the
/// surface as explicit rounded rects instead, which are round regardless.
///
/// Modelled on an old recorder's transport buttons: proud until pressed, then
/// sinking into the deck with a small bounce before settling. Unselected
/// reads exactly as before, so adopting this for an existing chip or segment
/// only changes what selection looks like.
///
/// A widget rather than a one-off per call site, so any future selectable
/// item — a segment, a chip, a list row — gets the same feedback for free.
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

  /// Whether the surface draws its own outline. Off by default for a segment
  /// that already sits inside a bordered row — a border on every child too
  /// would read as boxes inside a box (see `_SegmentRow`).
  final bool border;

  /// Whether the *unselected* surface casts the app's normal outward card
  /// shadow (`AppSurface.decoration`'s), for something that reads as a raised
  /// card at rest — a library row, say — rather than a flat control like a
  /// chip or segment. Selecting it still swaps to the inward band, which is
  /// what makes the whole thing read as the card sinking onto the page rather
  /// than merely losing its shadow.
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
        // The same distance drives the recess band and the child's own
        // shift, so the two never separate -- that's what makes the word
        // read as moving *with* the button rather than floating over it.
        final shift = surface.offset.dy * _depth.value;

        return ClipRRect(
          borderRadius: radius,
          child: CustomPaint(
            painter: _PressablePainter(
              shift: shift,
              fill: widget.fill,
              shadow: _pressedShadow,
              outline: widget.border ? surface.outline : null,
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
    // which is what made the bottom border vanish under a press. Shrinking
    // the surface instead reads correctly too -- a pressed front face is
    // smaller as well as further back, not just shifted off the edge.
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

/// Reaches the active [AppSurface] without every widget spelling out the
/// extension lookup.
extension AppSurfaceContext on BuildContext {
  /// Falls back to the matching default rather than throwing.
  ///
  /// A widget rendered under a bare `MaterialApp` — a test host, a route
  /// pushed with its own theme — would otherwise take the whole screen down on
  /// a null check. The fallback is the same value `AppTheme` installs, so the
  /// only thing lost is the ability to override it.
  AppSurface get surface {
    final theme = Theme.of(this);
    return theme.extension<AppSurface>() ??
        (theme.brightness == Brightness.dark
            ? AppSurface.dark()
            : AppSurface.light());
  }
}
