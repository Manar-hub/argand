/// The spacing scale.
///
/// Every gap and inset in the app comes from here. Before this existed the
/// codebase carried literal values at a dozen call sites — `16, 4, 16, 24`,
/// `8`, `3, 2` — which is why nothing lined up between screens and why nothing
/// could be adjusted without hunting.
///
/// A 4pt base, doubling then stepping: small enough to describe the tight gaps
/// inside a chip, coarse enough that there is one obvious choice at each size
/// rather than three near-identical ones.
abstract final class AppSpacing {
  /// Inside a chip or between an icon and its label.
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;

  /// The default gap between related elements.
  static const double md = 12;

  /// Screen margin, and the gap between unrelated blocks.
  static const double lg = 16;
  static const double xl = 24;

  /// Between major sections, where the gap should read as a break.
  static const double xxl = 32;

  /// Clearance under a floating action button so the last list row is never
  /// trapped behind it.
  static const double fabClearance = 96;
}
