/// Groups words into sentences, using the punctuation the engine already emits.
library;

import 'sentence_boundaries.dart';

/// A word as this file needs to see it: what it says and when.
typedef TimedWord = ({String text, int startMs, int endMs});

/// One sentence, as an extent in time and a range of word indices.
class SentenceUnit {
  const SentenceUnit({
    required this.startMs,
    required this.endMs,
    required this.first,
    required this.last,
  });

  final int startMs;
  final int endMs;

  /// Index of the first word, inclusive.
  final int first;

  /// Index of the last word, inclusive.
  final int last;

  int get wordCount => last - first + 1;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'SentenceUnit($first-$last, $startMs-$endMs)';
}

/// Cuts [words] into sentences after every sentence-ending punctuation mark.
List<SentenceUnit> sentenceUnitsOf(List<TimedWord> words) {
  final units = <SentenceUnit>[];
  var start = 0;

  for (var i = 0; i < words.length; i++) {
    final isLast = i == words.length - 1;
    if (!endsSentence(words[i].text) && !isLast) continue;

    units.add(SentenceUnit(
      startMs: words[start].startMs,
      endMs: words[i].endMs,
      first: start,
      last: i,
    ));
    start = i + 1;
  }

  return units;
}
