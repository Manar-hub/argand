/// How a caption or text looks: its font, its colour, and -- for captions --
/// how its words appear as they are spoken.
library;

import 'dart:convert';
import 'dart:math' as math;

/// The fonts a caption or text can use.
enum LookFont {
  standard(null, null, 'Default'),
  poppins('ArgandPoppins', 'assets/fonts/Poppins-Bold.ttf', 'Poppins'),
  anton('ArgandAnton', 'assets/fonts/Anton-Regular.ttf', 'Anton'),
  bebasNeue('ArgandBebasNeue', 'assets/fonts/BebasNeue-Regular.ttf', 'Bebas'),
  archivoBlack(
    'ArgandArchivoBlack',
    'assets/fonts/ArchivoBlack-Regular.ttf',
    'Archivo',
  ),
  bangers('ArgandBangers', 'assets/fonts/Bangers-Regular.ttf', 'Bangers'),
  permanentMarker(
    'ArgandPermanentMarker',
    'assets/fonts/PermanentMarker-Regular.ttf',
    'Marker',
  ),
  pacifico('ArgandPacifico', 'assets/fonts/Pacifico-Regular.ttf', 'Pacifico'),
  lobster('ArgandLobster', 'assets/fonts/Lobster-Regular.ttf', 'Lobster');

  const LookFont(this.family, this.asset, this.label);

  /// The Flutter font family, or null for the platform's own.
  final String? family;

  /// The file the render loads, or null for the platform's own face.
  final String? asset;

  /// The font's name as shown in the picker. A proper name, so not
  /// localised.
  final String label;

  /// The family to draw with.
  String get drawFamily => family ?? 'Roboto';
}

/// How a caption's words appear as they are spoken.
enum CaptionMode {
  /// The whole line at once, as captions have always been.
  standard,

  /// The whole line, each word taking the highlight colour once it has been
  /// said.
  karaoke,

  /// Only the word being said.
  wordByWord,

  /// The whole line, the word being said picked out in the highlight colour.
  highlight,
}

/// Font, colours, shadow and caption mode for one caption layer, sentence or
/// text.
class ItemLook {
  const ItemLook({
    this.font = LookFont.standard,
    this.colorArgb,
    this.backgroundArgb,
    this.shadow = defaultShadow,
    this.mode = CaptionMode.standard,
    this.highlightArgb = defaultHighlight,
    this.highlightBox = true,
  });

  static const ItemLook defaults = ItemLook();

  /// Plain words with a soft shadow under them: enough to hold them off
  /// bright footage without the dark plate captions used to sit on.
  static const double defaultShadow = 0.4;

  /// White: every speaker colour is a mid-bright hue, and white stands apart
  /// from all of them. A yellow default vanished against the first speaker's
  /// amber, so karaoke over that speaker looked like nothing happening.
  static const int defaultHighlight = 0xFFFFFFFF;

  final LookFont font;

  /// The words' colour, or null for the default: a caption's speaker colour,
  /// a text's white.
  final int? colorArgb;

  /// A colour behind the words, or null for none (the default). Words on a
  /// background cast no shadow; see [captionShadowFor].
  final int? backgroundArgb;

  /// How strong the words' drop shadow is, from 0 (none) to 1.
  final double shadow;

  final CaptionMode mode;

  /// The colour the spoken word takes in [CaptionMode.karaoke] and
  /// [CaptionMode.highlight].
  final int highlightArgb;

  /// In [CaptionMode.highlight], whether the colour goes **behind** the word
  /// (a box) or on its letters.
  final bool highlightBox;

  /// Whether the highlight colour means anything in this look.
  bool get usesHighlight =>
      mode == CaptionMode.karaoke || mode == CaptionMode.highlight;

  ItemLook copyWith({
    LookFont? font,
    int? Function()? colorArgb,
    int? Function()? backgroundArgb,
    double? shadow,
    CaptionMode? mode,
    int? highlightArgb,
    bool? highlightBox,
  }) {
    return ItemLook(
      font: font ?? this.font,
      colorArgb: colorArgb != null ? colorArgb() : this.colorArgb,
      backgroundArgb:
          backgroundArgb != null ? backgroundArgb() : this.backgroundArgb,
      shadow: shadow ?? this.shadow,
      mode: mode ?? this.mode,
      highlightArgb: highlightArgb ?? this.highlightArgb,
      highlightBox: highlightBox ?? this.highlightBox,
    );
  }

  /// Stored by name, so reordering an enum cannot restyle saved captions.
  String encode() => jsonEncode({
        'font': font.name,
        'color': colorArgb,
        'background': backgroundArgb,
        'shadow': shadow,
        'mode': mode.name,
        'highlight': highlightArgb,
        'highlightBox': highlightBox,
      });

  /// Reads a stored look. Null for null (the item has no look of its own);
  /// unknown values fall back field by field rather than failing.
  static ItemLook? decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return defaults;
      return ItemLook(
        font: LookFont.values.asNameMap()[map['font']] ?? LookFont.standard,
        colorArgb: map['color'] is int ? map['color'] as int : null,
        backgroundArgb:
            map['background'] is int ? map['background'] as int : null,
        // Looks saved before the shadow existed get the default one: the
        // plate they were drawn on is gone, and plain words need it.
        shadow: map['shadow'] is num
            ? (map['shadow'] as num).toDouble().clamp(0.0, 1.0)
            : defaultShadow,
        mode: CaptionMode.values.asNameMap()[map['mode']] ??
            CaptionMode.standard,
        highlightArgb:
            map['highlight'] is int ? map['highlight'] as int : defaultHighlight,
        highlightBox: map['highlightBox'] != false,
      );
    } on FormatException {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ItemLook &&
      other.font == font &&
      other.colorArgb == colorArgb &&
      other.backgroundArgb == backgroundArgb &&
      other.shadow == shadow &&
      other.mode == mode &&
      other.highlightArgb == highlightArgb &&
      other.highlightBox == highlightBox;

  @override
  int get hashCode => Object.hash(
        font,
        colorArgb,
        backgroundArgb,
        shadow,
        mode,
        highlightArgb,
        highlightBox,
      );
}

/// A drop shadow under words: its colour, blur radius and downward offset.
typedef WordShadow = ({int argb, double blur, double dy});

/// The shadow under words set at [fontSize] pixels with a dial of [strength],
/// or null for none.
WordShadow? captionShadowFor(double strength, double fontSize) {
  if (strength <= 0) return null;
  final s = math.min(strength, 1.0);
  final alpha = (0.25 + 0.75 * s) * 255;
  return (
    argb: alpha.round() << 24,
    blur: fontSize * (0.12 + 0.18 * s),
    dy: fontSize * 0.06,
  );
}

/// A word as the caption modes need it.
typedef TimedText = ({String text, int startMs, int endMs});

/// One stretch of a caption to draw: its words, and whether they are marked.
typedef CaptionRun = ({String text, bool marked});

/// What a caption shows at [atMs], in [mode]: the runs to draw, in order, with
/// the marked ones taking the highlight.
List<CaptionRun> captionRunsAt(
  List<TimedText> words,
  int atMs,
  CaptionMode mode,
) {
  if (words.isEmpty) return const [];

  switch (mode) {
    case CaptionMode.standard:
      return [(text: words.map((w) => w.text).join(' '), marked: false)];
    case CaptionMode.karaoke:
      return [
        for (final word in words) (text: word.text, marked: word.startMs <= atMs),
      ];
    case CaptionMode.highlight:
      return [
        for (final word in words)
          (
            text: word.text,
            marked: word.startMs <= atMs && atMs < word.endMs,
          ),
      ];
    case CaptionMode.wordByWord:
      var current = words.first;
      for (final word in words) {
        if (word.startMs <= atMs) current = word;
      }
      return [(text: current.text, marked: false)];
  }
}
