import 'package:flutter/material.dart';

import 'app_controls.dart';
import 'app_spacing.dart';
import 'app_surface.dart';

/// The app's light and dark themes, built together.
abstract final class AppTheme {
  /// Warm off-white paper, cards the same tone: on paper the outline is what
  /// draws a card's edge, as in the reference.
  static const _lightGround = Color(0xFFF8F4EF);
  static const _lightCard = Color(0xFFF8F4EF);
  static const _lightInk = Color(0xFF141414);

  /// Near-black with a card one clear step lighter: dark draws no outline, so
  /// the tone is the edge.
  static const _darkGround = Color(0xFF111111);
  static const _darkCard = Color(0xFF1E1E1E);
  static const _darkInk = Color(0xFFF2F0EA);

  /// The action colour until the user picks one -- and always, without Pro.
  static const defaultAccent = Color(0xFF116DD6);

  /// A soft highlight, used where something is emphasised but not chosen:
  /// the word under the playhead, a pending range.
  static const highlight = Color(0xFFEB99DD);

  /// The UI's two families (pubspec.yaml): Roboto Flex for headlines and
  /// anything meant to hit hard, Plus Jakarta Sans for everything read.
  static const displayFamily = 'ArgandDisplay';
  static const textFamily = 'ArgandText';

  /// Text and icons on a filled accent, chosen from the fill rather than fixed.
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

  /// Pro's own colour, a vivid "cyber gold": every Get Pro button takes it,
  /// whatever the user's action colour, so the offer looks the same
  /// wherever it appears.
  static const proGold = Color(0xFFFFC300);

  /// Reserved for genuine destruction — deleting a project. Also outside the
  /// speaker set, so it cannot be mistaken for an attribution.
  static const danger = Color(0xFFE03131);

  static ThemeData light({Color accent = defaultAccent}) => _build(
        brightness: Brightness.light,
        ground: _lightGround,
        card: _lightCard,
        ink: _lightInk,
        accent: accent,
        surface: AppSurface.light(),
      );

  static ThemeData dark({Color accent = defaultAccent}) => _build(
        brightness: Brightness.dark,
        ground: _darkGround,
        card: _darkCard,
        ink: _darkInk,
        accent: accent,
        surface: AppSurface.dark(),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color ground,
    required Color card,
    required Color ink,
    required Color accent,
    required AppSurface surface,
  }) {
    const square = BorderRadius.zero;

    // Written out rather than generated from a seed: every value here is a
    // decision.
    final scheme = ColorScheme(
      brightness: brightness,
      // Every call to action: the user's colour.
      primary: accent,
      onPrimary: inkOn(accent),
      // The playhead highlight and other soft emphasis.
      primaryContainer: highlight.withValues(alpha: 0.35),
      onPrimaryContainer: ink,
      // Selection, everywhere it appears -- a chosen tool, font, segment or
      // word: a solid block of the action colour, the same as the buttons
      // (the user's call, 2026-09-27; it was a block of ink).
      secondary: accent,
      onSecondary: inkOn(accent),
      error: danger,
      onError: Colors.white,
      surface: ground,
      onSurface: ink,
      surfaceContainerHighest: card,
      outline: surface.outline,
      outlineVariant: surface.outline.withValues(alpha: 0.35),
    );

    final text = _typography(ink);
    final shape = RoundedRectangleBorder(
      borderRadius: square,
      side: surface.side,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      // Not `ThemeData.fontFamily`: that re-applies one family over the whole
      // text theme and would erase the display face on the headlines. Every
      // style names its own family instead.
      textTheme: text,
      primaryTextTheme: text.apply(bodyColor: ink, displayColor: ink),
      extensions: [surface],

      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),

      // Material's own elevation is off everywhere: depth is the hard offset
      // shadow, drawn by `AppSurface.decoration`, never a blur.
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape,
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape,
        textStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: ground),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: square),
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
        selectedColor: accent,
        checkmarkColor: inkOn(accent),
        labelStyle: text.labelLarge,
        side: surface.side,
        shape: const RoundedRectangleBorder(borderRadius: square),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStatePropertyAll(surface.side),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: square),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? inkOn(accent) : ink,
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
          shape: shape,
          // The box is the button, with no invisible touch margin round it,
          // so `AppRaised`'s shadow falls from the button's own edge.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // The button moving under the finger is the feedback
          // (`AppPressDown`); a ripple on top would be a second kind.
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: text.labelLarge,
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: square),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: square),
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
        shape: shape,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? ground : _darkGround,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: square,
          borderSide: surface.side,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: square,
          borderSide: surface.side,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: square,
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: square),
        side: BorderSide(color: ink, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(inkOn(accent)),
      ),

      // Square thumb on a straight track, the thumb standing on the app's
      // hard shadow.
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        trackShape: const RectangularSliderTrackShape(),
        activeTrackColor: ink,
        inactiveTrackColor: ink.withValues(alpha: 0.18),
        thumbColor: accent,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: AppSquareThumb(
          outline: surface.outlined ? surface.outline : null,
          shadow: surface.shadow,
          offset: surface.offset / 2,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surface.outline.withValues(alpha: 0.15),
      ),

      // Without an outline (dark) a divider in full ink would be the one
      // white line left on the page, so it drops to the hairline.
      dividerTheme: DividerThemeData(
        color: surface.outlined
            ? surface.outline
            : surface.outline.withValues(alpha: 0.18),
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// Heavy display against plain body.
  static TextTheme _typography(Color ink) {
    TextStyle display(double size, FontWeight weight, double tracking,
            double height) =>
        TextStyle(
          fontFamily: displayFamily,
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: tracking,
          color: ink,
        );
    TextStyle body(double size, FontWeight weight, double height,
            {double tracking = 0, Color? color}) =>
        TextStyle(
          fontFamily: textFamily,
          fontSize: size,
          height: height,
          fontWeight: weight,
          letterSpacing: tracking,
          color: color ?? ink,
        );

    return TextTheme(
      displayLarge: display(57, FontWeight.w900, -1.5, 1.0),
      displayMedium: display(45, FontWeight.w900, -1.2, 1.0),
      displaySmall: display(36, FontWeight.w900, -1.0, 1.05),
      headlineLarge: display(32, FontWeight.w900, -1.0, 1.05),
      headlineMedium: display(28, FontWeight.w900, -0.8, 1.1),
      headlineSmall: display(24, FontWeight.w800, -0.6, 1.1),
      titleLarge: display(22, FontWeight.w900, -0.5, 1.15),
      titleMedium: display(17, FontWeight.w800, -0.2, 1.25),
      titleSmall: display(15, FontWeight.w700, -0.1, 1.3),
      // The transcript. The most-read surface in the app, so it is set for
      // reading rather than for style: generous line height, normal weight.
      bodyLarge: body(16, FontWeight.w400, 1.5),
      bodyMedium: body(14, FontWeight.w400, 1.45),
      bodySmall: body(12.5, FontWeight.w400, 1.4,
          color: ink.withValues(alpha: 0.7)),
      labelLarge: body(13, FontWeight.w700, 1.2, tracking: 0.2),
      labelMedium: body(12, FontWeight.w600, 1.2, tracking: 0.2),
      labelSmall: body(11, FontWeight.w600, 1.2, tracking: 0.2),
    );
  }
}
