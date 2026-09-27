/// How a transcript is translated and the translation put back in time.
///
/// **The whole text at once, then timed.** Translating sentence by sentence
/// kept each line's timing trivially but stripped every sentence of the ones
/// around it -- pronouns, ellipses and half-finished thoughts came back
/// wrong. So the transcript goes to the translator as running text (in long
/// runs, see [translationBatches]), and the translation is cut into its *own*
/// sentences afterwards and laid along the speech by how far through the
/// text each one falls ([alignTranslation]). The words need not line up one
/// for one; the sentences only need to arrive while their meaning is said.
library;

import '../text/sentence_units.dart';

/// A word as the translation needs it.
typedef TranslatableWord = ({
  String text,
  int startMs,
  int endMs,
  int position,
});

/// One sentence to translate.
typedef TranslatableSentence = ({
  String text,
  int startMs,
  int endMs,

  /// Positions of its first and last word in the transcript.
  int firstWord,
  int lastWord,
});

/// [words], in order, as sentences -- the same cut captions and the
/// timeline's sentences use (`sentenceUnitsOf`).
List<TranslatableSentence> translatableSentencesOf(
  List<TranslatableWord> words,
) {
  final units = sentenceUnitsOf([
    for (final word in words)
      (text: word.text, startMs: word.startMs, endMs: word.endMs),
  ]);
  return [
    for (final unit in units)
      (
        text: [
          for (var i = unit.first; i <= unit.last; i++) words[i].text,
        ].join(' '),
        startMs: unit.startMs,
        endMs: unit.endMs,
        firstWord: words[unit.first].position,
        lastWord: words[unit.last].position,
      ),
  ];
}

/// One translated sentence, placed on the speech.
typedef TranslatedSentence = ({
  String text,
  int startMs,
  int endMs,

  /// The source words it sits over, first and last, by position.
  int firstWord,
  int lastWord,
});

/// [sentences] in consecutive runs of at most [maxCharacters], cut only at
/// sentence ends: each run is translated as one text. Long enough to carry
/// the context; bounded so a long recording is not one enormous request.
List<List<TranslatableSentence>> translationBatches(
  List<TranslatableSentence> sentences, {
  int maxCharacters = 2000,
}) {
  final batches = <List<TranslatableSentence>>[];
  var current = <TranslatableSentence>[];
  var length = 0;
  for (final sentence in sentences) {
    if (current.isNotEmpty && length + sentence.text.length > maxCharacters) {
      batches.add(current);
      current = [];
      length = 0;
    }
    current.add(sentence);
    length += sentence.text.length + 1;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// [text] cut after every sentence-ending mark -- Latin, Arabic, CJK and
/// Devanagari ones -- or line break.
List<String> splitTranslatedSentences(String text) {
  final pieces = <String>[];
  // Full-width CJK marks end a sentence with no space after them; the rest
  // need a space or the end, so "3.5" and "U.S.A" stay whole.
  final end = RegExp(
    r'[.!?\u2026\u061F\u06D4\u0964]+["\u201D\u2019)\]]*(\s+|$)'
    r'|[\u3002\uFF01\uFF1F]+["\u201D\u300D)]*\s*'
    r'|\n+',
  );
  var from = 0;
  for (final match in end.allMatches(text)) {
    final piece = text.substring(from, match.end).trim();
    if (piece.isNotEmpty) pieces.add(piece);
    from = match.end;
  }
  final rest = text.substring(from).trim();
  if (rest.isNotEmpty) pieces.add(rest);
  return pieces;
}

/// [translated] -- the translation of [source] as one text -- cut into its
/// own sentences and laid along the time [source] was said.
///
/// When the translation has as many sentences as the source, each takes its
/// source sentence's place exactly. Otherwise each is placed by how far
/// through the translation it falls: that share of the source's characters,
/// read off the source sentences' times, so a pause between sentences stays a
/// pause and a long sentence gets the time a long sentence took.
List<TranslatedSentence> alignTranslation({
  required List<TranslatableSentence> source,
  required String translated,
}) {
  final pieces = splitTranslatedSentences(translated);
  if (source.isEmpty || pieces.isEmpty) return const [];

  if (pieces.length == source.length) {
    return [
      for (final (i, piece) in pieces.indexed)
        (
          text: piece,
          startMs: source[i].startMs,
          endMs: source[i].endMs,
          firstWord: source[i].firstWord,
          lastWord: source[i].lastWord,
        ),
    ];
  }

  // Where each source sentence starts, as a share of all their characters.
  final lengths = [for (final s in source) s.text.length + 1];
  final total = lengths.fold<int>(0, (a, b) => a + b);
  final starts = <double>[];
  var run = 0;
  for (final length in lengths) {
    starts.add(run / total);
    run += length;
  }

  int sentenceAt(double share) {
    var index = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= share) index = i;
    }
    return index;
  }

  int timeAt(double share) {
    final i = sentenceAt(share);
    final within = ((share - starts[i]) * total / lengths[i]).clamp(0.0, 1.0);
    final s = source[i];
    return s.startMs + ((s.endMs - s.startMs) * within).round();
  }

  final pieceLengths = [for (final p in pieces) p.length + 1];
  final pieceTotal = pieceLengths.fold<int>(0, (a, b) => a + b);
  final result = <TranslatedSentence>[];
  var before = 0;
  for (final (i, piece) in pieces.indexed) {
    final from = before / pieceTotal;
    before += pieceLengths[i];
    final to = before / pieceTotal;
    // The last piece ends where the speech does, not a rounding short of it.
    final last = i == pieces.length - 1;
    final startMs = timeAt(from);
    final endMs = last ? source.last.endMs : timeAt(to);
    result.add((
      text: piece,
      startMs: startMs,
      endMs: endMs > startMs ? endMs : startMs + 1,
      firstWord: source[sentenceAt(from)].firstWord,
      lastWord: last
          ? source.last.lastWord
          : source[sentenceAt(to - 1e-9)].lastWord,
    ));
  }
  return result;
}
