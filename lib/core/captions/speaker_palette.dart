import 'package:flutter/material.dart';

/// Colours that distinguish one speaker from another.
///
/// **Deterministic, not stored.** A speaker's colour is a function of the
/// diarization index, so it is stable across launches without a database row
/// and identical in the transcript and in the captions — which is the point:
/// the colour is how a viewer ties a caption line to a person, so the two
/// surfaces disagreeing would defeat it. When a later feature lets a user
/// rename or recolour a speaker there will be state worth persisting, and that
/// is when a speakers table earns its place; until then it would be a schema
/// nothing reads.
///
/// The hues follow broadcast captioning practice, where a small set of
/// high-contrast colours has long been used for exactly this job. They are
/// chosen to work in two places at once: as caption text over a dark scrim on
/// video, and as a chip behind dark text in the transcript. That rules out
/// pure white — conventional for a single speaker, invisible as a chip on a
/// light theme — and anything dark enough to disappear against video.
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
  ///
  /// Beyond this the cycle wraps and two people share a colour. Six is well
  /// past what this app's target media contains, and adding more hues costs
  /// distinguishability rather than gaining it.
  static int get length => _colors.length;

  /// Colour for [speaker], or [fallback] when the transcript was never
  /// diarized.
  static Color colorFor(int? speaker, {required Color fallback}) {
    if (speaker == null) return fallback;
    return _colors[speaker.abs() % _colors.length];
  }

  /// Text colour that stays legible on top of [colorFor].
  ///
  /// Computed from luminance rather than hardcoded, so adding a darker hue to
  /// the list above cannot silently produce unreadable text.
  static Color onColorFor(int? speaker, {required Color fallback}) {
    if (speaker == null) return fallback;
    final background = colorFor(speaker, fallback: fallback);
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
  }
}
