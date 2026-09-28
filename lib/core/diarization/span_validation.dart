/// Challenges short spans that segmentation may have invented.
library;

import 'speaker_span.dart';

/// Thresholds for [suspectSpans] and [applyValidations].
class SpanValidation {
  const SpanValidation({
    this.maxSuspectMs = 1200,
    this.minChallengerMs = 1500,
    this.minMargin = 0.10,
    this.minConfidentSimilarity = 0.45,
    this.minChallengerOverlapMs = 100,
    this.edgeTrimMs = 50,
    this.minRegionMs = 250,
    this.maxSuspects = 16,
  });

  /// Longest span worth challenging. A long span carries enough audio that
  /// segmentation is rarely wrong about it, and re-labelling one would move far
  /// more than the error it was aimed at.
  final int maxSuspectMs;

  /// How much of the surrounding audio the challenger must hold before its
  /// claim is worth testing. Stops a short span being challenged by another
  /// short span, where neither side has the evidence to be believed.
  final int minChallengerMs;

  /// How much better the challenger must sound than the incumbent. The
  /// incumbent is what segmentation decided, so a tie leaves it alone.
  final double minMargin;

  /// Below this, the region is treated as unable to answer rather than as
  /// evidence.
  final double minConfidentSimilarity;

  /// How much of the suspect the challenger must also claim before structure
  /// alone is allowed to decide it.
  final int minChallengerOverlapMs;

  /// Trimmed from each end before embedding. Span edges are where the
  /// neighbouring voice bleeds in.
  final int edgeTrimMs;

  /// Regions shorter than this after trimming are not embedded at all: CAM++
  /// needs some audio to characterise a voice, and a guess from too little is
  /// worse than no answer.
  final int minRegionMs;

  /// Ceiling on embeddings, so a pathological file cannot make this pass
  /// unbounded.
  final int maxSuspects;

  /// Disables the pass entirely, for A/B measurement.
  static const SpanValidation none = SpanValidation(maxSuspectMs: 0);

  bool get isEnabled => maxSuspectMs > 0;
}

/// A short span, and the speaker whose audio surrounds it.
class SuspectSpan {
  const SuspectSpan({
    required this.index,
    required this.incumbent,
    required this.challenger,
    required this.startMs,
    required this.endMs,
    required this.challengerOverlapMs,
  });

  /// Position in the span list handed to [suspectSpans], so a decision can be
  /// applied without matching on times.
  final int index;

  /// The speaker segmentation assigned.
  final int incumbent;

  /// The speaker holding the audio on both sides.
  final int challenger;

  final int startMs;
  final int endMs;

  /// How much of this span the challenger also claims. Non-zero means
  /// segmentation has two people speaking at once here.
  final int challengerOverlapMs;

  int get durationMs => endMs - startMs;

  /// The audio worth asking about, or null when trimming leaves too little.
  ({int startMs, int endMs})? embedRegion(SpanValidation config) {
    final from = startMs + config.edgeTrimMs;
    final to = endMs - config.edgeTrimMs;
    if (to - from < config.minRegionMs) return null;
    return (startMs: from, endMs: to);
  }

  @override
  String toString() =>
      'SuspectSpan($startMs-${endMs}ms, spk$incumbent vs spk$challenger)';
}

/// Short spans whose surroundings belong to a single other speaker.
List<SuspectSpan> suspectSpans(
  List<SpeakerSpan> spans, {
  SpanValidation config = const SpanValidation(),
}) {
  if (!config.isEnabled || spans.length < 3) return const [];

  final suspects = <SuspectSpan>[];

  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    if (span.durationMs > config.maxSuspectMs) continue;

    // Audio each other speaker holds strictly before, and strictly after.
    final before = <int, int>{};
    final after = <int, int>{};
    for (var j = 0; j < spans.length; j++) {
      if (j == i) continue;
      final other = spans[j];
      if (other.speaker == span.speaker) continue;

      final leading = other.overlapWith(other.startMs, span.startMs);
      if (leading > 0) {
        before[other.speaker] = (before[other.speaker] ?? 0) + leading;
      }
      final trailing = other.overlapWith(span.endMs, other.endMs);
      if (trailing > 0) {
        after[other.speaker] = (after[other.speaker] ?? 0) + trailing;
      }
    }

    int? challenger;
    var best = 0;
    before.forEach((speaker, leading) {
      final trailing = after[speaker] ?? 0;
      // Both sides must clear the bar independently. Summing them would let a
      // long run on one side carry a speaker that is absent on the other, which
      // is exactly a real turn boundary rather than an invented one.
      if (leading < config.minChallengerMs) return;
      if (trailing < config.minChallengerMs) return;
      final total = leading + trailing;
      if (total > best) {
        best = total;
        challenger = speaker;
      }
    });

    if (challenger == null) continue;

    var overlap = 0;
    for (var j = 0; j < spans.length; j++) {
      if (j == i) continue;
      if (spans[j].speaker != challenger) continue;
      overlap += spans[j].overlapWith(span.startMs, span.endMs);
    }

    suspects.add(SuspectSpan(
      index: i,
      incumbent: span.speaker,
      challenger: challenger!,
      startMs: span.startMs,
      endMs: span.endMs,
      challengerOverlapMs: overlap,
    ));
  }

  // Shortest first: the shortest spans are the likeliest artifacts, so a cap
  // spends its budget where the answer matters most.
  suspects.sort((a, b) => a.durationMs.compareTo(b.durationMs));
  if (suspects.length > config.maxSuspects) {
    return suspects.sublist(0, config.maxSuspects);
  }
  return suspects;
}

/// Whether the audio says a suspect belongs to its challenger.
bool challengerWins(
  SuspectSpan suspect,
  Map<int, double> similarities, {
  SpanValidation config = const SpanValidation(),
}) {
  final incumbent = similarities[suspect.incumbent];
  final challenger = similarities[suspect.challenger];
  if (incumbent == null || challenger == null) return false;

  // The audio answers clearly.
  if (challenger - incumbent >= config.minMargin) return true;

  // The audio cannot answer, and the geometry says this boundary was never
  // real: the challenger is already speaking inside this span.
  final confident = (incumbent > challenger ? incumbent : challenger) >=
      config.minConfidentSimilarity;
  if (!confident &&
      suspect.challengerOverlapMs >= config.minChallengerOverlapMs) {
    return true;
  }
  return false;
}

/// Re-labels every span the audio reassigned, leaving all boundaries intact.
List<SpeakerSpan> applyValidations(
  List<SpeakerSpan> spans,
  Iterable<SuspectSpan> reassigned,
) {
  if (reassigned.isEmpty) return spans;

  final newSpeakers = <int, int>{
    for (final suspect in reassigned) suspect.index: suspect.challenger,
  };

  return [
    for (var i = 0; i < spans.length; i++)
      if (newSpeakers.containsKey(i))
        SpeakerSpan(
          startMs: spans[i].startMs,
          endMs: spans[i].endMs,
          speaker: newSpeakers[i]!,
        )
      else
        spans[i],
  ];
}
