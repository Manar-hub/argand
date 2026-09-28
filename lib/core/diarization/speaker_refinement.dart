import 'dart:math' as math;
import 'dart:typed_data';

import '../text/sentence_units.dart';
import 'speaker_assignment.dart';
import 'speaker_span.dart';

/// Deciding *who* is speaking in a region pyannote left unresolved, from the
/// audio rather than from the shape of its spans.

/// Guards for the refinement pass. Every field is a reason *not* to act: the
/// pass changes nothing when the evidence is weak.
class SpeakerRefinement {
  const SpeakerRefinement({
    this.minRegionMs = 400,
    this.minReferenceMs = 1500,
    this.maxReferences = 4,
    this.minSimilarity = 0.20,
    this.minMargin = 0.10,
    this.maxCandidates = 40,
    this.edgeTrimMs = 50,
    this.longSpanMedianMultiple = 1.5,
    this.maxBoundaryStraddle = 0.25,
    this.minReferenceCoherence = 0.5,
  });

  /// Shortest region worth embedding.
  final int minRegionMs;

  /// Shortest span usable as a voice-print reference. References carry more
  /// weight than candidates, so they are held to a longer minimum.
  final int minReferenceMs;

  /// How many reference spans to average per speaker. Longest first.
  final int maxReferences;

  /// The winner must sound like *someone*. Guards against acting on a region
  /// that matches nothing — noise, music, silence.
  final double minSimilarity;

  /// How far the winner must beat the runner-up.
  final double minMargin;

  /// Ceiling on embeddings per file, so a long recording cannot blow the
  /// import budget. Longest candidates first.
  final int maxCandidates;

  /// Shaved off each end of a candidate before embedding. whisper's word times
  /// drift, and the drift is at the edges — which is exactly where the
  /// neighbouring speaker is.
  final int edgeTrimMs;

  /// How much longer than this file's *median* span a span must be before the
  /// sentences inside it are re-examined.
  final double longSpanMedianMultiple;

  /// How much of a candidate may sit on the far side of a speaker change before
  /// the region is refused outright.
  final double maxBoundaryStraddle;

  /// How much a reference span's two halves must sound like each other before
  /// that span is trusted to represent one voice.
  final double minReferenceCoherence;

  /// Refinement off, for measuring what it contributes. Same shape as
  /// [SpeakerSmoothing.none].
  static const SpeakerRefinement none = SpeakerRefinement(maxCandidates: 0);

  bool get isEnabled => maxCandidates > 0;
}

/// A stretch of audio the pass wants an embedding for.
typedef EmbedRegion = ({int startMs, int endMs});

/// A sentence whose attribution is worth asking the audio about.
class RefinementCandidate {
  const RefinementCandidate({
    required this.startMs,
    required this.endMs,
    required this.currentSpeaker,
    required this.firstWord,
    required this.lastWord,
  });

  final int startMs;
  final int endMs;
  final int currentSpeaker;

  /// Inclusive word range, into the list handed to [planRefinement].
  final int firstWord;
  final int lastWord;

  int get durationMs => endMs - startMs;
}

/// Everything the isolate needs: plain data only, so it can be copied.
class RefinementPlan {
  const RefinementPlan({
    required this.references,
    required this.candidates,
  });

  /// Speaker to the regions their voice print should be built from.
  final Map<int, List<EmbedRegion>> references;

  final List<RefinementCandidate> candidates;

  /// Nothing to do unless there is something to ask about and at least two
  /// speakers to tell apart.
  bool get isEmpty => candidates.isEmpty || references.length < 2;

  int get embedCount =>
      candidates.length + references.values.fold(0, (n, r) => n + r.length);
}

/// Why a candidate did or did not move. Recorded for every candidate, because
/// the declines are as informative as the moves when tuning.
enum RefinementOutcome {
  moved,
  keptAlreadyBest,
  keptNoMargin,
  keptWeakMatch,
  skippedNoEmbedding,
}

class RefinementDecision {
  const RefinementDecision({
    required this.candidate,
    required this.similarities,
    required this.newSpeaker,
    required this.outcome,
  });

  final RefinementCandidate candidate;

  /// Speaker to cosine similarity. Empty when the region produced no
  /// embedding.
  final Map<int, double> similarities;

  /// Null when nothing changed.
  final int? newSpeaker;

  final RefinementOutcome outcome;
}

/// Chooses which sentences to ask about, and which spans to learn voices from.
RefinementPlan planRefinement({
  required List<SpeakerSpan> spans,
  required List<WordTiming> words,
  required List<int?> assigned,
  SpeakerRefinement config = const SpeakerRefinement(),
}) {
  if (!config.isEnabled || spans.isEmpty || words.isEmpty) {
    return const RefinementPlan(references: {}, candidates: []);
  }

  // Sentence extents, and which speaker currently holds each.
  final sentences = sentenceUnitsOf(words);

  // Median rather than mean: diarization emits a few very long spans and many
  // short ones, and a mean would be dragged upward by exactly the spans this
  // is meant to flag.
  final durations = spans.map((s) => s.durationMs).toList()..sort();
  final median = durations.length.isOdd
      ? durations[durations.length ~/ 2]
      : (durations[durations.length ~/ 2 - 1] +
              durations[durations.length ~/ 2]) /
          2;
  final longSpanThresholdMs = median * config.longSpanMedianMultiple;

  final candidates = <RefinementCandidate>[];
  for (final sentence in sentences) {
    final holders = <int>{};
    for (final span in spans) {
      if (span.overlapWith(sentence.startMs, sentence.endMs) > 0) {
        holders.add(span.speaker);
      }
    }
    if (holders.isEmpty) continue;

    final ambiguous = holders.length > 1;

    // Is it buried in a span unusually long *for this file*? That is where a
    // turn nobody reported can hide.
    var insideLongSpan = false;
    if (!ambiguous) {
      for (final span in spans) {
        if (span.overlapWith(sentence.startMs, sentence.endMs) <= 0) continue;
        if (span.durationMs > longSpanThresholdMs) {
          insideLongSpan = true;
          break;
        }
      }
    }
    if (!ambiguous && !insideLongSpan) continue;

    // Whoever currently holds most of the sentence's words.
    final counts = <int, int>{};
    for (var i = sentence.first; i <= sentence.last; i++) {
      final speaker = assigned[i];
      if (speaker != null) counts[speaker] = (counts[speaker] ?? 0) + 1;
    }
    if (counts.isEmpty) continue;
    var current = counts.keys.first;
    var best = 0;
    counts.forEach((speaker, n) {
      if (n > best) {
        best = n;
        current = speaker;
      }
    });

    final from = sentence.startMs + config.edgeTrimMs;
    final to = sentence.endMs - config.edgeTrimMs;
    if (to - from < config.minRegionMs) continue;

    // Refuse a region that already contains a speaker change. Its embedding
    // would be a blend of two voices, and the model would answer accurately
    // about the blend — which is neither of them.
    final regionMs = to - from;
    var straddled = false;
    for (final span in spans) {
      for (final cut in [span.startMs, span.endMs]) {
        if (cut <= from || cut >= to) continue;
        final minority = math.min(cut - from, to - cut);
        if (minority / regionMs > config.maxBoundaryStraddle) {
          straddled = true;
          break;
        }
      }
      if (straddled) break;
    }
    if (straddled) continue;

    candidates.add(RefinementCandidate(
      startMs: from,
      endMs: to,
      currentSpeaker: current,
      firstWord: sentence.first,
      lastWord: sentence.last,
    ));
  }

  if (candidates.isEmpty) {
    return const RefinementPlan(references: {}, candidates: []);
  }

  candidates.sort((a, b) => b.durationMs.compareTo(a.durationMs));
  final capped = candidates.take(config.maxCandidates).toList();

  return RefinementPlan(
    references: referenceRegionsOf(spans, config: config),
    candidates: capped,
  );
}

/// Stretches of audio to learn each speaker's voice from.
Map<int, List<EmbedRegion>> referenceRegionsOf(
  List<SpeakerSpan> spans, {
  SpeakerRefinement config = const SpeakerRefinement(),
}) {
  final references = <int, List<EmbedRegion>>{};
  for (final speaker in spans.map((s) => s.speaker).toSet()) {
    final clean = <SpeakerSpan>[];
    for (final span in spans.where((s) => s.speaker == speaker)) {
      if (span.durationMs < config.minReferenceMs) continue;
      // Segmentation itself says another speaker is active here.
      final sharedWithOther = spans.any((other) =>
          other.speaker != speaker &&
          other.overlapWith(span.startMs, span.endMs) > 0);
      if (sharedWithOther) continue;

      // A span may still conceal a turn nobody reported, which would fold
      // another voice into this speaker's reference.
      clean.add(span);
    }
    if (clean.isEmpty) continue;
    clean.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    references[speaker] = [
      for (final span in clean.take(config.maxReferences))
        (startMs: span.startMs, endMs: span.endMs),
    ];
  }
  return references;
}

/// Unit-length copy of [embedding], or null if it has no direction.
Float32List? unitVector(Float32List? embedding) {
  if (embedding == null || embedding.isEmpty) return null;
  var sum = 0.0;
  for (final value in embedding) {
    sum += value * value;
  }
  if (sum <= 0) return null;
  final scale = 1.0 / math.sqrt(sum);
  final out = Float32List(embedding.length);
  for (var i = 0; i < embedding.length; i++) {
    out[i] = embedding[i] * scale;
  }
  return out;
}

/// Cosine similarity of two **unit** vectors, which is just their dot product.
double cosineSimilarity(Float32List a, Float32List b) {
  final n = a.length < b.length ? a.length : b.length;
  var dot = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// Mean of [unitVectors], re-normalised. Null if there is nothing to average.
Float32List? centroidOf(List<Float32List> unitVectors) {
  if (unitVectors.isEmpty) return null;
  final mean = Float32List(unitVectors.first.length);
  for (final vector in unitVectors) {
    for (var i = 0; i < mean.length; i++) {
      mean[i] += vector[i];
    }
  }
  return unitVector(mean);
}

/// The decision rule, over *numbers* rather than vectors — so thresholds can be
/// swept on the host against recorded similarities, with no model involved.
RefinementOutcome decideOne({
  required Map<int, double> similarities,
  required int currentSpeaker,
  required SpeakerRefinement config,
}) {
  if (similarities.isEmpty) return RefinementOutcome.skippedNoEmbedding;

  final ranked = similarities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final best = ranked.first;
  if (best.value < config.minSimilarity) return RefinementOutcome.keptWeakMatch;

  final runnerUp = ranked.length > 1 ? ranked[1].value : double.negativeInfinity;
  if (best.value - runnerUp < config.minMargin) {
    return RefinementOutcome.keptNoMargin;
  }

  if (best.key == currentSpeaker) return RefinementOutcome.keptAlreadyBest;
  return RefinementOutcome.moved;
}

/// Rewrites [spans] so a moved region is actually attributed to its new
/// speaker.
List<SpeakerSpan> applyRefinements(
  List<SpeakerSpan> spans,
  List<RefinementDecision> decisions,
) {
  final moves = decisions
      .where((d) => d.outcome == RefinementOutcome.moved && d.newSpeaker != null)
      .toList();
  if (moves.isEmpty) return spans;

  var working = [...spans];

  for (final move in moves) {
    final from = move.candidate.startMs;
    final to = move.candidate.endMs;
    final speaker = move.newSpeaker!;

    final rebuilt = <SpeakerSpan>[];
    for (final span in working) {
      if (span.speaker == speaker || span.overlapWith(from, to) <= 0) {
        rebuilt.add(span);
        continue;
      }
      if (span.startMs < from) {
        rebuilt.add(SpeakerSpan(
          startMs: span.startMs,
          endMs: math.min(span.endMs, from),
          speaker: span.speaker,
        ));
      }
      if (span.endMs > to) {
        rebuilt.add(SpeakerSpan(
          startMs: math.max(span.startMs, to),
          endMs: span.endMs,
          speaker: span.speaker,
        ));
      }
    }
    rebuilt.add(SpeakerSpan(startMs: from, endMs: to, speaker: speaker));
    working = rebuilt.where((s) => s.endMs > s.startMs).toList();
  }

  working.sort((a, b) => a.startMs.compareTo(b.startMs));

  // The carve-out deliberately leaves the winning speaker's own spans alone, so
  // applying the same move twice would insert the region a second time
  // alongside the first.
  final seen = <String>{};
  return [
    for (final s in working)
      if (seen.add('${s.speaker}:${s.startMs}-${s.endMs}')) s,
  ];
}
