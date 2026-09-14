import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_surface.dart';

/// The app's light and dark themes, built together.
///
/// **Together, not light-then-dark.** The style leans on a dark outline and a
/// hard offset shadow over a light ground; on a near-black ground the shadow
/// disappears and the outline has to invert. Adding dark afterwards means
/// rebuilding it, so both are defined here side by side and every value that
/// differs is visible as a pair.
///
/// Direction and constraints → `docs/design-direction.md`.
abstract final class AppTheme {
  /// Warm paper. Pure white beside a 2px black outline glares, and every
  /// reference sits on a paper tone; cards are a shade lighter again so the
  /// list does not read as one flat wall.
  static const _lightGround = Color(0xFFFFF1E8);
  static const _lightCard = Color(0xFFFFFAF5);
  static const _lightInk = Color(0xFF141414);

  static const _darkGround = Color(0xFF161616);
  static const _darkCard = Color(0xFF1F1F1F);
  static const _darkInk = Color(0xFFF2F0EA);

  /// Two colours, and the themes trade them.
  ///
  /// Yellow is the call to action on paper and the blue is the call to action
  /// on near-black — the same yellow over a dark ground is a floodlight. What
  /// each theme does *not* spend on its import panel, it spends on selection,
  /// so the two roles are always told apart by hue and never compete.
  ///
  /// The blue takes white ink at 5.0:1 and would only manage 4.2:1 with black,
  /// which is why [inkOn] measures rather than assuming a single ink.
  static const _yellow = Color(0xFFFFD93D);
  static const _blue = Color(0xFF116DD6);

  /// A soft highlight, used where something is emphasised but not chosen:
  /// the word under the playhead, a pending range.
  static const highlight = Color(0xFFEB99DD);

  /// Text and icons on a filled accent, chosen from the fill rather than fixed.
  ///
  /// A single constant does not survive these fills, and the test is what said
  /// so: black reads 15:1 on the yellow but only 4.2:1 on the blue, where white
  /// reaches 5.0:1.
  ///
  /// Deliberately **not** `ThemeData.estimateBrightnessForColor`. Its threshold
  /// sits at a relative luminance of about 0.34, so a mid-tone fill gets called
  /// "dark" and handed light ink that is *worse* than the black it rejected.
  /// Measuring both and taking the winner cannot make that mistake, and stays
  /// right if a fill is ever retuned.
  static Color inkOn(Color fill) {
    const dark = Color(0xFF141414);
    const light = Color(0xFFF7F5F0);
    return _contrast(fill, dark) >= _contrast(fill, light) ? dark : light;
  }

  /// WCAG relative-contrast ratio.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05;
    final lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }

  /// The light theme's call-to-action fill, for anything that needs the value
  /// without a `BuildContext`.
  static const accent = _yellow;

  /// Reserved for genuine destruction — deleting a project. Also outside the
  /// speaker set, so it cannot be mistaken for an attribution.
  static const danger = Color(0xFFE03131);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        ground: _lightGround,
        card: _lightCard,
        ink: _lightInk,
        accent: _yellow,
        selected: _blue,
        surface: AppSurface.light(),
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        ground: _darkGround,
        card: _darkCard,
        ink: _darkInk,
        accent: _blue,
        selected: _yellow,
        surface: AppSurface.dark(),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color ground,
    required Color card,
    required Color ink,
    required Color accent,
    required Color selected,
    required AppSurface surface,
  }) {
    // Written out rather than generated from a seed. `ColorScheme.fromSeed`
    // produces tonal, slightly-tinted surfaces, which is the opposite of a flat
    // ground with a hard outline — every value here is a decision.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: inkOn(accent),
      // The playhead highlight and other soft emphasis.
      primaryContainer: highlight.withValues(alpha: 0.35),
      onPrimaryContainer: ink,
      // Selection, everywhere it appears.
      secondary: selected,
      onSecondary: inkOn(selected),
      error: danger,
      onError: Colors.white,
      surface: ground,
      onSurface: ink,
      surfaceContainerHighest: card,
      outline: surface.outline,
      outlineVariant: surface.outline.withValues(alpha: 0.35),
    );

    final text = _typography(ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      textTheme: text,
      extensions: [surface],

      // Flat, outlined, and part of the page rather than floating above it.
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),

      // Elevation is expressed by the offset shadow, never by a blur, so every
      // Material default that would add one is turned off.
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: surface.borderRadius,
          side: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: surface.borderRadius,
          side: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(surface.radius),
          ),
          side: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: ground),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: surface.borderRadius),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        iconColor: ink,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: selected,
        checkmarkColor: ink,
        labelStyle: text.labelLarge,
        side: BorderSide(color: surface.outline, width: surface.borderWidth),
        shape: RoundedRectangleBorder(borderRadius: surface.borderRadius),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStatePropertyAll(
            BorderSide(color: surface.outline, width: surface.borderWidth),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: surface.borderRadius),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? selected : card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? inkOn(selected) : ink,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: inkOn(accent),
          elevation: 0,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: surface.borderRadius,
            side: BorderSide(color: surface.outline, width: surface.borderWidth),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: surface.borderRadius),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: inkOn(accent),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: surface.borderRadius,
          side: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? ground : _darkGround,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: surface.borderRadius,
          borderSide: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: surface.borderRadius,
          borderSide: BorderSide(color: surface.outline, width: surface.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: surface.borderRadius,
          borderSide: BorderSide(color: accent, width: surface.borderWidth),
        ),
      ),

      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(surface.outline),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surface.outline.withValues(alpha: 0.15),
      ),

      dividerTheme: DividerThemeData(
        color: surface.outline,
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// Heavy display against plain body.
  ///
  /// The weight contrast is what carries the style — it does the job colour
  /// usually would, which is exactly what lets the palette stay quiet enough
  /// for `SpeakerPalette` to remain the loudest thing on screen.
  ///
  /// The platform font, for now. Bundling a grotesk is an app-size and
  /// licensing decision, it is purely additive, and it is better made once the
  /// structure is agreed.
  static TextTheme _typography(Color ink) {
    return TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        height: 1.05,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      // The transcript. The most-read surface in the app, so it is set for
      // reading rather than for style: generous line height, normal weight.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: ink.withValues(alpha: 0.75),
      ),
      // Uppercase-adjacent tracking on labels, which is where the style shows
      // without costing legibility in running text.
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
        color: ink,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: ink,
      ),
    );
  }
}
