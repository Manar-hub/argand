import 'package:flutter/material.dart';

/// Colours that distinguish one speaker from another.
abstract final class SpeakerPalette {
  static const List<Color> _colors = [
    Color(0xFFFFD54F), // amber
    Color(0xFF4DD0E1), // cyan
    Color(0xFFAED581), // light green
    Color(0xFFF48FB1), // pink
    Color(0xFFFFB74D), // orange
    Color(0xFFB39DDB), // lavender
  ];

  /// How many speakers can be told apart before colours repeat.
  static int get length => _colors.length;

  /// Colour for [speaker], or [fallback] when the transcript was never
  /// diarized.
  static Color colorFor(int? speaker, {required Color fallback, int? custom}) {
    if (custom != null) return Color(custom);
    if (speaker == null) return fallback;
    return _colors[speaker.abs() % _colors.length];
  }

  /// The same six speakers, as colours that can be set in type on a light
  /// ground.
  static const List<Color> _inkOnLight = [
    Color(0xFF8E6A00), // amber      4.51:1
    Color(0xFF007A93), // cyan       4.52:1
    Color(0xFF1A8100), // green      4.54:1
    Color(0xFFDB005B), // pink       4.56:1
    Color(0xFFD23100), // orange     4.55:1
    Color(0xFF6A00FF), // lavender   6.22:1
  ];

  /// [speaker]'s colour, for drawing text on a page of [brightness].
  static Color textColorFor(
    int? speaker, {
    required Brightness brightness,
    required Color fallback,
    int? custom,
  }) {
    if (custom != null) {
      final color = Color(custom);
      if (brightness == Brightness.dark) return color;
      // On paper a pale colour is unreadable: darken it, keeping its hue.
      final hsl = HSLColor.fromColor(color);
      return hsl.lightness > 0.4 ? hsl.withLightness(0.4).toColor() : color;
    }
    if (speaker == null) return fallback;
    final index = speaker.abs() % _colors.length;
    return brightness == Brightness.dark ? _colors[index] : _inkOnLight[index];
  }

  /// Text colour that stays legible on top of [colorFor].
  static Color onColorFor(int? speaker, {required Color fallback, int? custom}) {
    if (speaker == null && custom == null) return fallback;
    final background = colorFor(speaker, fallback: fallback, custom: custom);
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }
}
