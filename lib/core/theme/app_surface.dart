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
