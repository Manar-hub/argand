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

  /// The same six speakers, as colours that can be **set in type** on a light
  /// ground.
  ///
  /// [_colors] are fills. They are bright by design — they sit behind caption
  /// text over video, and they read at 7.5:1 to 12.8:1 against a near-black
  /// page. Used as *text* on the warm off-white ground they collapse: amber
  /// measures 1.28:1, cyan 1.66:1. So the light theme needs its own set, and
  /// this is it.
  ///
  /// Every entry is **full saturation at the lightest tone that still clears
  /// 4.5:1**, the WCAG AA bar for body text. Lightest matters as much as the
  /// bar does: an earlier attempt blended each hue toward black until it
  /// passed, which desaturates, and it came out muddy. Darkening in HSL while
  /// pinning saturation keeps the colour vivid.
  ///
  /// Five keep their own hue. **Orange moves, and has to.** The amber fill sits
  /// at 46° and the orange fill at 36° — ten degrees apart. Bright and pale
  /// they are easy to tell apart; darkened they converge on the same brown and
  /// the two speakers become one colour. Orange is pushed to 14° (vermilion) so
  /// six hues stay distinct, the smallest pair now separated by 125 of a
  /// possible 765.
  ///
  /// **Amber is the known weak point, and it is a fact about yellow rather
  /// than a tuning failure.** Yellow reaches maximum chroma at high lightness,
  /// so *every* dark yellow is an olive-gold. `#8E6A00` is the most vivid
  /// yellow that clears the bar; there is no brighter one.
  static const List<Color> _inkOnLight = [
    Color(0xFF8E6A00), // amber      4.51:1
    Color(0xFF007A93), // cyan       4.52:1
    Color(0xFF1A8100), // green      4.54:1
    Color(0xFFDB005B), // pink       4.56:1
    Color(0xFFD23100), // orange     4.55:1
    Color(0xFF6A00FF), // lavender   6.22:1
  ];

  /// [speaker]'s colour, for drawing text on a page of [brightness].
  ///
  /// Dark returns the fill unchanged, which already reads at 7.5:1 or better
  /// on the near-black ground and is the same colour the captions use. Light
  /// returns the tuned ink above.
  ///
  /// The two are the same hue, not the same value, which is what keeps a
  /// speaker recognisable: a reader only ever sees one theme at a time, and
  /// within that theme the stamp and the caption chip agree.
  static Color textColorFor(
    int? speaker, {
    required Brightness brightness,
    required Color fallback,
  }) {
    if (speaker == null) return fallback;
    final index = speaker.abs() % _colors.length;
    return brightness == Brightness.dark ? _colors[index] : _inkOnLight[index];
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
