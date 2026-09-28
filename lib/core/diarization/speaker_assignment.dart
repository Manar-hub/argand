import '../text/sentence_units.dart';
import 'speaker_span.dart';

/// Maps transcribed words onto diarized speaker spans.

/// Two coverage scores this close are treated as equal, so a rounding
/// difference of a millisecond cannot decide which speaker a word belongs to.
const double _coverageEpsilon = 0.001;

/// Speaker label for the word occupying [startMs, endMs), or null if there is
/// nothing to attribute it to.
int? speakerForWord({
  required int startMs,
  required int endMs,
  required List<SpeakerSpan> spans,
}) {
  if (spans.isEmpty) return null;

  SpeakerSpan? best;
  var bestCoverage = 0.0;
  final wordMs = endMs - startMs;

  for (final span in spans) {
    final overlap = span.overlapWith(startMs, endMs);
    if (overlap <= 0) continue;

    // Scored as a *fraction of the word*, not raw milliseconds. Raw overlap
    // makes a long span beat a short one simply for being long, which is
    // backwards whenever a brief turn is nested inside a longer one.
    final coverage = wordMs > 0 ? overlap / wordMs : 1.0;

    if (best == null) {
      best = span;
      bestCoverage = coverage;
      continue;
    }

    final improves = coverage > bestCoverage + _coverageEpsilon;
    final ties = (coverage - bestCoverage).abs() <= _coverageEpsilon;

    // The tie-break is the whole fix: when two spans both cover the word
    // completely, the shorter one is the more specific claim and wins.
    if (improves || (ties && span.durationMs < best.durationMs)) {
      best = span;
      bestCoverage = coverage;
    }
  }
  if (best != null) return best.speaker;

  // No overlap anywhere: fall back to the closest span. Ties resolve to the
  // earlier one, so the result does not depend on list order.
  SpeakerSpan? nearest;
  var nearestGap = -1;
  for (final span in spans) {
    final gap = span.gapTo(startMs, endMs);
    if (nearestGap < 0 || gap < nearestGap) {
      nearestGap = gap;
      nearest = span;
    }
  }
  return nearest?.speaker;
}

/// A word as this file needs to see it: what it says and when.
typedef WordTiming = ({String text, int startMs, int endMs});

/// How far a turn boundary may be nudged to line up with a sentence.
class SpeakerSmoothing {
  const SpeakerSmoothing({
    this.maxEdgeRunWords = 2,
    this.minSentenceWords = 3,
  });

  /// Longest run of a minority speaker that may be absorbed. Deliberately
  /// tiny: observed errors are one word, occasionally two. Raising it would
  /// start flattening turn changes that genuinely fall mid-sentence.
  final int maxEdgeRunWords;

  /// Sentences shorter than this are left alone. In a two-word sentence a
  /// one-word "minority" is half the evidence, which is not a majority worth
  /// acting on.
  final int minSentenceWords;

  /// Smoothing off entirely, for measuring what it contributes.
  static const SpeakerSmoothing none =
      SpeakerSmoothing(maxEdgeRunWords: 0, minSentenceWords: 1 << 30);
}

/// Assigns a speaker to every word, then tidies the turn boundaries.
List<int?> assignSpeakers(
  List<WordTiming> words,
  List<SpeakerSpan> spans, {
  SpeakerSmoothing smoothing = const SpeakerSmoothing(),
}) {
  final assigned = [
    for (final word in words)
      speakerForWord(
        startMs: word.startMs,
        endMs: word.endMs,
        spans: spans,
      ),
  ];

  if (spans.isEmpty) return assigned;

  // Sentences come from the shared cut in `sentence_units.dart`, the same one
  // refinement uses, so both stages always mean the same thing by "sentence".
  for (final sentence in sentenceUnitsOf(words)) {
    _smoothSentence(assigned, sentence.first, sentence.last, smoothing);
  }

  return assigned;
}

/// Absorbs short minority runs at the edges of the sentence spanning
/// [start, end] inclusive.
void _smoothSentence(
  List<int?> assigned,
  int start,
  int end,
  SpeakerSmoothing smoothing,
) {
  final length = end - start + 1;
  if (length < smoothing.minSentenceWords) return;

  final counts = <int?, int>{};
  for (var i = start; i <= end; i++) {
    counts[assigned[i]] = (counts[assigned[i]] ?? 0) + 1;
  }
  if (counts.length < 2) return;

  int? majority;
  var best = 0;
  var tied = false;
  counts.forEach((speaker, count) {
    if (count > best) {
      best = count;
      majority = speaker;
      tied = false;
    } else if (count == best) {
      tied = true;
    }
  });
  // No strict majority means no evidence either way, so nothing moves.
  if (tied || majority == null) return;

  // Leading run.
  var i = start;
  while (i <= end && assigned[i] != majority) {
    i++;
  }
  final leadingRun = i - start;
  if (leadingRun > 0 && leadingRun <= smoothing.maxEdgeRunWords) {
    for (var j = start; j < i; j++) {
      assigned[j] = majority;
    }
  }

  // Trailing run.
  var k = end;
  while (k >= start && assigned[k] != majority) {
    k--;
  }
  final trailingRun = end - k;
  if (trailingRun > 0 && trailingRun <= smoothing.maxEdgeRunWords) {
    for (var j = k + 1; j <= end; j++) {
      assigned[j] = majority;
    }
  }
}

/// How a speaker index is stored in `Words.speakerId`.
String speakerIdFor(int speaker) => '$speaker';
