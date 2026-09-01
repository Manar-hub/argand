/// Groups words into sentences, using the punctuation the engine already emits.
///
/// **Why this is shared rather than written twice.** Two parts of diarization
/// cut the same sentences for different reasons — `speaker_assignment.dart`
/// smooths attribution inside a sentence, `speaker_refinement.dart` uses a
/// sentence as the region it asks the audio about — and each had its own copy
/// of the loop. Two copies of a boundary rule is one copy too many: if they
/// ever drifted, refinement would move a region that assignment had cut
/// somewhere else, and the decision would land on the wrong words.
///
/// **Why sentences are the right unit at all.** A speaker change almost always
/// happens between sentences, not inside one. Whisper punctuates its output, so
/// that structure is free — no parser, no model, no extra pass. Treating the
/// sentence as the unit is what lets a rule say "this whole utterance is one
/// voice" rather than deciding each word on its own and letting a sentence
/// fracture down the middle.
///
/// Pure, with no dependency on the diarization or caption layers, so both can
/// use it without either depending on the other.
library;

import 'sentence_boundaries.dart';

/// A word as this file needs to see it: what it says and when.
///
/// Structurally identical to `WordTiming` in `speaker_assignment.dart`, so the
/// two are interchangeable without either library importing the other.
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
///
/// The final run is always closed even when it carries no terminator, because
/// speech that trails off unpunctuated is still a sentence for every purpose
/// here — dropping it would silently exclude the end of every transcript from
/// smoothing and refinement alike.
///
/// Note this deliberately does *not* break on clause punctuation. A comma is a
/// weaker boundary that caption grouping may choose to break on for line
/// length; a speaker handover at a comma is rare enough that treating clauses
/// as units would fragment the evidence a speaker decision rests on.
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
