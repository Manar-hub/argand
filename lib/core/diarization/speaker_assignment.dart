import '../text/sentence_boundaries.dart';
import 'speaker_span.dart';

/// Maps transcribed words onto diarized speaker spans.
///
/// Diarization and transcription are two independent passes over the same
/// audio, so their boundaries never line up exactly: whisper's word timings are
/// DTW-derived and known to drift, and diarization emits spans that start and
/// end on its own segmentation windows. This file is where those two views are
/// reconciled, and it is deliberately pure — no I/O, no FFI, no engine types —
/// so the reconciliation rules are testable on the host VM.

/// Speaker label for the word occupying [startMs, endMs), or null if there is
/// nothing to attribute it to.
///
/// **Most overlap wins, and ties go to the longer span.** A word straddling a
/// speaker change belongs to whoever was talking for more of it. Ties are
/// common, because diarization emits *overlapping* spans and a word sitting
/// wholly inside two of them is covered completely by both.
///
/// Breaking ties toward the longer span biases attribution to whoever dominates
/// a region. That is deliberate: short nested spans are frequently spurious, and
/// letting them win lets each one steal individual words, which reads as the
/// transcript flapping between speakers mid-sentence.
///
/// **The known cost**, accepted: a genuinely nested short reply is absorbed by
/// the speaker talking around it. That is a rarer and smaller error than
/// flapping, which is why the rule leans this way.
///
/// **A word touching no span falls back to the nearest one.** Returning null
/// there would be more literal but worse: word timings drift by tens of
/// milliseconds, so a word can sit just outside the span it obviously belongs
/// to, and scattering unattributed words through an otherwise-labelled
/// transcript reads as a bug rather than as honesty. Nearest-span is chosen
/// without a distance limit, because [spans] only covers regions diarization
/// already judged to be speech and the word came from that same speech.
///
/// Null is returned only when [spans] is empty — diarization did not run, was
/// skipped for length, or found nothing.
int? speakerForWord({
  required int startMs,
  required int endMs,
  required List<SpeakerSpan> spans,
}) {
  if (spans.isEmpty) return null;

  SpeakerSpan? best;
  var bestOverlap = 0;
  for (final span in spans) {
    final overlap = span.overlapWith(startMs, endMs);
    if (overlap <= 0) continue;

    // Breaking the tie explicitly, rather than letting the first span seen
    // win, keeps the result independent of the order spans arrive in instead
    // of silently depending on the sort diarize() happens to apply.
    if (best == null ||
        overlap > bestOverlap ||
        (overlap == bestOverlap && span.durationMs > best.durationMs)) {
      bestOverlap = overlap;
      best = span;
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

/// The sentence-level rules: how a whole sentence is attributed, and how far a
/// turn boundary may be nudged to line up with one.
class SpeakerSmoothing {
  const SpeakerSmoothing({
    this.maxEdgeRunWords = 2,
    this.minSentenceWords = 3,
    this.minSentenceIouMargin = 0.15,
  });

  /// Longest run of a minority speaker that may be absorbed. Deliberately
  /// tiny: observed errors are one word, occasionally two. Raising it would
  /// start flattening turn changes that genuinely fall mid-sentence.
  final int maxEdgeRunWords;

  /// Sentences shorter than this are left alone. In a two-word sentence a
  /// one-word "minority" is half the evidence, which is not a majority worth
  /// acting on.
  final int minSentenceWords;

  /// How far the best sentence score must beat the runner-up before the whole
  /// sentence is reattributed. See [_attributeSentence] for what the score is
  /// and why a margin, rather than an absolute floor, is the guard.
  ///
  /// **Measured, not chosen.** Swept against the spans and sentence extents of
  /// three real clips: below 0.12 it starts moving sentences that were already
  /// right, and above 0.20 it stops rescuing ones that are wrong. 0.15 sits in
  /// the middle of that band rather than at either edge.
  final double minSentenceIouMargin;

  /// Both sentence-level rules off, for measuring what they contribute. The
  /// per-word geometry in [speakerForWord] still runs.
  static const SpeakerSmoothing none = SpeakerSmoothing(
    maxEdgeRunWords: 0,
    minSentenceWords: 1 << 30,
    // Above 1.0, which no margin between two ratios can ever reach.
    minSentenceIouMargin: 2,
  );
}

/// Assigns a speaker to every word, then tidies the turn boundaries.
///
/// Two passes, because the second needs context the first cannot have:
///
///  1. [speakerForWord] per word, which is purely geometric.
///  2. **Sentence-edge smoothing.** Diarization boundaries and whisper's word
///     timings are derived independently, so a turn change lands a word or two
///     off — reliably at a sentence edge, because that is where speakers
///     actually swap. A sentence that is mostly one speaker, with a short run
///     of another clinging to its start or end, is that error and not a real
///     mid-sentence handover.
///
/// Measured on a real clip: "AI is expensive." arrived with "AI" on the
/// previous speaker and the rest on the next, splitting one sentence across two
/// voices. Smoothing puts the whole sentence on the speaker who says most of
/// it. The run-length bound is what keeps this honest — a sentence genuinely
/// shared between two people has a long minority run and is left alone.
///
/// Returns one entry per word in [words], in the same order.
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

  var sentenceStart = 0;
  for (var i = 0; i < words.length; i++) {
    final isLast = i == words.length - 1;
    if (!endsSentence(words[i].text) && !isLast) continue;

    _attributeSentence(assigned, words, spans, sentenceStart, i, smoothing);
    _smoothSentence(assigned, sentenceStart, i, smoothing);
    sentenceStart = i + 1;
  }

  return assigned;
}

/// Attributes the whole sentence spanning [start, end] inclusive to one
/// speaker, when the evidence for one is clearly better than for any other.
///
/// **The score is intersection-over-union** between the sentence's time extent
/// and the merged union of one speaker's spans that touch it:
///
/// ```
/// score = |sentence ∩ spans| / |sentence ∪ spans|
/// ```
///
/// Raw overlap cannot answer this question, and that is the whole reason this
/// pass exists. Diarization emits *overlapping* spans, so a word — or a whole
/// sentence — sitting inside two of them is covered completely by both, and
/// overlap saturates at "all of it" for each. The comparison then collapses
/// into a tie broken on span length, which is a coin flip dressed up as a rule:
/// preferring the longer span loses a genuine nested reply, and preferring the
/// shorter one lets stray activations steal words.
///
/// IoU does not saturate, because the denominator charges a span for the time
/// it spends *outside* the sentence. That is exactly the signal that separates
/// the two cases, measured on real spans:
///
/// - a real nested reply — its span is about the size of the sentence, so it
///   scores ~0.89, while the multi-second span enclosing it scores ~0.26;
/// - a spurious activation — a 253ms blip inside a 4s sentence scores ~0.06,
///   while the speaker actually holding the region scores ~0.99.
///
/// **The guard is a margin, not a floor.** What matters is not how well the
/// winner fits but how much better it fits than anyone else, because a lone
/// speaker with a mediocre score is still the only candidate. Requiring a clear
/// gap is also what preserves a genuine mid-sentence handover: when two
/// speakers each hold about half a sentence their scores are close, the margin
/// is not met, and the per-word assignment is left to stand.
///
/// A sentence with only one speaker overlapping it is left alone: there is
/// nothing to arbitrate, and [speakerForWord] has already handled it.
void _attributeSentence(
  List<int?> assigned,
  List<WordTiming> words,
  List<SpeakerSpan> spans,
  int start,
  int end,
  SpeakerSmoothing smoothing,
) {
  final startMs = words[start].startMs;
  final endMs = words[end].endMs;
  if (endMs <= startMs) return;

  final bySpeaker = <int, List<SpeakerSpan>>{};
  for (final span in spans) {
    if (span.overlapWith(startMs, endMs) <= 0) continue;
    bySpeaker.putIfAbsent(span.speaker, () => []).add(span);
  }
  if (bySpeaker.length < 2) return;

  int? best;
  var bestScore = 0.0;
  var runnerUp = 0.0;
  bySpeaker.forEach((speaker, spansForSpeaker) {
    final score = _sentenceIou(spansForSpeaker, startMs, endMs);
    if (score > bestScore) {
      runnerUp = bestScore;
      bestScore = score;
      best = speaker;
    } else if (score > runnerUp) {
      runnerUp = score;
    }
  });

  final winner = best;
  if (winner == null) return;
  if (bestScore - runnerUp < smoothing.minSentenceIouMargin) return;

  for (var i = start; i <= end; i++) {
    assigned[i] = winner;
  }
}

/// Intersection-over-union between the window [startMs, endMs) and the union of
/// [spans].
///
/// The spans are merged first because one speaker's own spans can overlap each
/// other — diarization reports activity per speaker per frame, not a partition
/// — and double-counting that shared time would inflate the union and depress
/// the score of whoever is genuinely talking.
double _sentenceIou(List<SpeakerSpan> spans, int startMs, int endMs) {
  if (spans.isEmpty) return 0;

  final ordered = [...spans]..sort((a, b) => a.startMs.compareTo(b.startMs));

  // Merge into disjoint ranges first, then measure.
  final merged = <List<int>>[];
  for (final span in ordered) {
    if (merged.isNotEmpty && span.startMs <= merged.last[1]) {
      if (span.endMs > merged.last[1]) merged.last[1] = span.endMs;
    } else {
      merged.add([span.startMs, span.endMs]);
    }
  }

  var unionMs = 0;
  var intersectionMs = 0;
  for (final range in merged) {
    unionMs += range[1] - range[0];
    final from = range[0] > startMs ? range[0] : startMs;
    final to = range[1] < endMs ? range[1] : endMs;
    if (to > from) intersectionMs += to - from;
  }

  final union = (endMs - startMs) + unionMs - intersectionMs;
  return union > 0 ? intersectionMs / union : 0;
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
///
/// A plain decimal string. The column is text because a later phase will point
/// it at a real `Speakers` row with a UUID, a display name and a colour; until
/// that exists there is nothing to reference, and inventing a scheme now would
/// only have to be migrated. Kept in one function so the format has a single
/// definition rather than being spelled out at each call site.
String speakerIdFor(int speaker) => '$speaker';
