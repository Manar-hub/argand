/// How a transcript is translated and the translation put back in time.
library;

import 'dart:math' as math;

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
    // Cut only where a sentence ends, so no run starts mid-thought -- unless
    // a run has grown to twice the limit without one.
    final full = length + sentence.text.length > maxCharacters;
    final atEnd = current.isNotEmpty && endStrength(current.last.text) == 2;
    if (current.isNotEmpty &&
        full &&
        (atEnd || length > maxCharacters * 2)) {
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

/// Marks that end a sentence, and marks that end a clause, in the scripts
/// the translator writes.
const String _sentenceMarks = '.!?…؟۔।。！？';
const String _clauseMarks = ',;:،؛、，';
const String _closers = '"”’)]»」';

/// How [text] ends: 2 a sentence, 1 a clause, 0 neither.
int endStrength(String text) {
  var end = text.trimRight();
  while (end.isNotEmpty && _closers.contains(end[end.length - 1])) {
    end = end.substring(0, end.length - 1);
  }
  if (end.isEmpty) return 0;
  final last = end[end.length - 1];
  if (_sentenceMarks.contains(last)) return 2;
  if (_clauseMarks.contains(last)) return 1;
  return 0;
}

/// [translated] -- the translation of [sources], read as one text -- cut into
/// exactly one piece per source, in order.
List<String> alignToSegments({
  required List<String> sources,
  required String translated,
}) {
  final n = sources.length;
  final text = translated.trim();
  if (n == 0) return const [];
  if (text.isEmpty) return List.filled(n, '');
  if (n == 1) return [text];

  // A script written without spaces is cut between characters, punctuation
  // riding on the character before it.
  final spaces = RegExp(r'\s').allMatches(text).length;
  final byCharacter = spaces * 15 < text.length;
  final tokens = <String>[];
  if (byCharacter) {
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) continue;
      final attaches = _sentenceMarks.contains(char) ||
          _clauseMarks.contains(char) ||
          _closers.contains(char);
      if (attaches && tokens.isNotEmpty) {
        tokens[tokens.length - 1] += char;
      } else {
        tokens.add(char);
      }
    }
  } else {
    tokens.addAll(text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty));
  }
  final joiner = byCharacter ? '' : ' ';
  final t = tokens.length;

  final prefix = [0];
  for (final token in tokens) {
    prefix.add(prefix.last + token.length + joiner.length);
  }
  final sourceLengths = [for (final s in sources) s.trim().length + 1];
  final sourceTotal = sourceLengths.fold<int>(0, (a, b) => a + b);
  final expected = [
    for (final length in sourceLengths) length / sourceTotal * prefix.last,
  ];
  final sourceEnds = [for (final s in sources) endStrength(s)];
  final cutEnds = [for (final token in tokens) endStrength(token)];

  // Too few words to go round: each word to the source whose share of the
  // text it falls in.
  if (t < n) {
    final pieces = List.filled(n, '');
    var source = 0;
    var edge = expected[0];
    for (var j = 0; j < t; j++) {
      final middle = (prefix[j] + prefix[j + 1]) / 2;
      while (source < n - 1 && middle > edge) {
        source++;
        edge += expected[source];
      }
      pieces[source] = pieces[source].isEmpty
          ? tokens[j]
          : '${pieces[source]}$joiner${tokens[j]}';
    }
    return pieces;
  }

  // How well a cut after token [j - 1] ends source [i].
  double bonus(int i, int j) {
    if (j >= t) return 0;
    final cut = cutEnds[j - 1];
    final source = sourceEnds[i];
    if (cut == 2) return source == 2 ? 0.9 : (source == 1 ? 0.4 : 0.15);
    if (cut == 1) return source >= 1 ? 0.4 : 0.1;
    return 0;
  }

  double cost(int i, int from, int to) {
    final length = prefix[to] - prefix[from];
    final off = (length - expected[i]) / math.max(expected[i], 6);
    return off * off;
  }

  // best[i][j]: the least cost of sources 0..i covering tokens 0..j-1, the
  // last piece ending at token j.
  const inf = double.infinity;
  final best = List.generate(n, (_) => List.filled(t + 1, inf));
  final from = List.generate(n, (_) => List.filled(t + 1, 0));
  for (var j = 1; j <= t - (n - 1); j++) {
    best[0][j] = cost(0, 0, j) - bonus(0, j);
  }
  for (var i = 1; i < n; i++) {
    final last = i == n - 1;
    for (var j = i + 1; j <= t - (n - 1 - i); j++) {
      if (last && j != t) continue;
      var least = inf;
      var at = i;
      for (var k = i; k < j; k++) {
        final before = best[i - 1][k];
        if (before == inf) continue;
        final total = before + cost(i, k, j);
        if (total < least) {
          least = total;
          at = k;
        }
      }
      best[i][j] = least - bonus(i, j);
      from[i][j] = at;
    }
  }

  final pieces = List.filled(n, '');
  var end = t;
  for (var i = n - 1; i >= 0; i--) {
    final start = i == 0 ? 0 : from[i][end];
    pieces[i] = tokens.sublist(start, end).join(joiner);
    end = start;
  }
  return pieces;
}

/// [translated] -- the translation of [source] as one text -- laid over
/// [source] one piece each (see [alignToSegments]), each piece taking its
/// source's time and words exactly. A source left without words gets no line.
List<TranslatedSentence> alignTranslation({
  required List<TranslatableSentence> source,
  required String translated,
}) {
  final pieces = alignToSegments(
    sources: [for (final s in source) s.text],
    translated: translated,
  );
  return [
    for (final (i, piece) in pieces.indexed)
      if (piece.isNotEmpty)
        (
          text: piece,
          startMs: source[i].startMs,
          endMs: source[i].endMs,
          firstWord: source[i].firstWord,
          lastWord: source[i].lastWord,
        ),
  ];
}
