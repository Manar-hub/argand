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
/// between themes: the outline and the shadow are near-black on a light ground,
/// and on a dark one the shadow is a pale slab and **there is no outline** --
/// an off-white 2pt frame round every card, chip and button read as cheap
/// (the user's call, 2026-09-24). Anything reading these values gets the right
/// ones for the active theme without asking which one is on.
@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.outline,
    required this.shadow,
    required this.borderWidth,
    required this.radius,
    required this.offset,
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

  /// Dark: **no outline** -- a card is told from the page by its lighter fill
  /// and lifted by the pale slab under it. [outline] is kept as the theme's
  /// strong ink for the few things that use it as a colour (a muted glyph, a
  /// hairline at low alpha), never as a frame.
  ///
  /// The shadow is a *pale* slab, because a black one on a `#161616` ground is
  /// not a subtler shadow, it is no shadow. A solid mid grey rather than a
  /// light colour at low alpha, so the value does not change with whatever the
  /// shadow happens to fall across.
  factory AppSurface.dark() => const AppSurface(
        outline: Color(0xFFEDEAE3),
        shadow: Color(0xFF6E6B65),
        borderWidth: 0,
        radius: 0,
        offset: Offset(4, 4),
      );

  final Color outline;
  final Color shadow;

  /// Zero for no outline at all -- see [outlined].
  final double borderWidth;
  final double radius;

  /// Down and to the right, as in the reference.
  ///
  /// It falls only on what a screen is about -- a primary action, the stage,
  /// a dialog, a docked panel -- so the skew a diagonal gives a full-width
  /// card is rare, and on those few it reads as the point.
  final Offset offset;

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// How far a pressed or chosen surface sinks: half the shadow's drop. The
  /// full drop read as sinking too deep.
  double get pressDepth => offset.dy / 2;

  /// The hard shadow on its own, for something that draws its own shape --
  /// an action button.
  BoxShadow get hardShadow =>
      BoxShadow(color: shadow, offset: offset, blurRadius: 0);

  /// Whether this theme draws an outline at all.
  ///
  /// Checked rather than drawing a zero-width side: Flutter paints a
  /// `BorderSide` of width 0 as a one-pixel hairline, which on dark is exactly
  /// the thin white frame being removed.
  bool get outlined => borderWidth > 0;

  /// The outline as a side, for a shape: [BorderSide.none] without one.
  BorderSide get side => outlined
      ? BorderSide(color: outline, width: borderWidth)
      : BorderSide.none;

  /// The outline as a box border: null without one.
  Border? get border =>
      outlined ? Border.all(color: outline, width: borderWidth) : null;

  /// A bordered surface filled with [fill], **flat unless [raised]**.
  ///
  /// The shadow is for emphasis only -- the one or two things a screen is
  /// about -- which is how the reference keeps a box-heavy style calm.
  /// Everything else is a flat outlined box.
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
/// pressed band silently squared off every corner. A [CustomPainter] draws
/// both the recess and the surface as explicit rounded rects instead, which
/// are round regardless.
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

  /// Whether the surface draws its own outline -- when the theme has one
  /// ([AppSurface.outlined]). Off by default for a segment that already sits
  /// inside a bordered row — a border on every child too would read as boxes
  /// inside a box (see `_SegmentRow`).
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
        // Half the shadow's drop: a chosen item settles into the page
        // rather than sinking through it.
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

/// An action, lifted on the app's hard shadow: every button that *does*
/// something -- Export, Create project, a dialog's confirm -- stands off the
/// page, which is what tells it apart from a choice.
///
/// Wraps the button rather than theming it: Material's own elevation is a
/// blur, and this style's shadow is not.
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

/// Makes [child] give under the finger: it moves by [travel] while pressed
/// and springs back on release, the same feel as a pressed library row.
///
/// Listens alongside the button rather than replacing its tap handling, so
/// the button behaves exactly as before; this only moves it.
///
/// [travel] defaults to the app's press depth, straight down -- a flat
/// button sinking into the page. [AppRaised] passes the shadow's own offset,
/// so a raised button lands on its shadow.
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

/// A button set *into* something -- the search square at the end of its
/// field, a cell of the timeline's toolbar -- pushed down and to the right
/// when pressed, the same travel as an action button landing on its shadow.
///
/// **The edges it uncovers are ink.** Moving inside its own box, the face
/// opens a strip along its top and left; that strip is the theme's strong
/// line colour ([AppSurface.outline] -- near-black on paper, near-white on
/// dark), so the press reads as the face sinking into a recess rather than
/// sliding over the page. Clipped to its box, so the face never paints over
/// a neighbour or a rule. No highlight or ripple: the movement is the
/// feedback.
///
/// [face] is the button's fill, which moves with it -- it must be opaque for
/// the recess to stay hidden at rest.
class AppPushIn extends StatefulWidget {
  const AppPushIn({super.key, required this.face, required this.child});

  final Color face;
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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _down ? 1 : 0),
          // Quick going in, eased coming out -- no spring past rest, which
          // inside a clip would open the recess on the other two sides.
          duration: still
              ? Duration.zero
              : Duration(milliseconds: _down ? 90 : 160),
          curve: Curves.easeOut,
          child: ColoredBox(color: widget.face, child: widget.child),
          builder: (context, t, child) => ColoredBox(
            // Only while moving: at rest an ink box under an identical face
            // can still show as a hairline at a fractional edge.
            color: t > 0 ? surface.outline : Colors.transparent,
            child: Transform.translate(
              offset: surface.offset * t,
              child: child,
            ),
          ),
        ),
      ),
    );
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
