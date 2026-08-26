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

/// Two coverage scores this close are treated as equal, so a rounding
/// difference of a millisecond cannot decide which speaker a word belongs to.
const double _coverageEpsilon = 0.001;

/// Speaker label for the word occupying [startMs, endMs), or null if there is
/// nothing to attribute it to.
///
/// **Most-covered wins, and ties go to the more specific span.** A word
/// straddling a speaker change belongs to whoever was talking for more of it.
/// When two spans cover it equally — which happens constantly, because
/// diarization emits *overlapping* spans and a short turn is frequently nested
/// inside a longer one — the shorter span is the better answer.
///
/// That tie-break is not a refinement, it is the fix for a real reported bug.
/// Scoring by raw overlap milliseconds let a long span win purely for being
/// long, so a nested reply was swallowed by the speaker talking around it:
/// measured spans `spk0:35452-41965` with `spk1:37088-39772` inside it put all
/// of speaker 1's words on speaker 0. Segmentation had found the turn
/// correctly; only this reconciliation step threw it away.
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

    _smoothSentence(assigned, sentenceStart, i, smoothing);
    sentenceStart = i + 1;
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
///
/// A plain decimal string. The column is text because a later phase will point
/// it at a real `Speakers` row with a UUID, a display name and a colour; until
/// that exists there is nothing to reference, and inventing a scheme now would
/// only have to be migrated. Kept in one function so the format has a single
/// definition rather than being spelled out at each call site.
String speakerIdFor(int speaker) => '$speaker';
