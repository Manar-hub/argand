import 'dart:math' as math;
import 'dart:typed_data';

import '../text/sentence_boundaries.dart';
import 'speaker_assignment.dart';
import 'speaker_span.dart';

/// Deciding *who* is speaking in a region pyannote left unresolved, from the
/// audio rather than from the shape of its spans.
///
/// **Why this exists.** Reconciliation can only move a word onto a speaker
/// segmentation actually reported. On real material it sometimes reports none:
/// on the development clip the employee's reply "Tokens cost money."
/// (7920-9400) sits inside one unbroken span attributed to the boss, with no
/// second-speaker activity anywhere between 7861 and 12468. Every parameter the
/// library exposes was swept against it and the spans did not move. No rule
/// over those spans can recover the turn, because the evidence is not in them.
///
/// It is in the audio. Measured with CAM++ against voice prints built from
/// unambiguous stretches of the same clip, that region scores 0.571 for the
/// employee against 0.266 for the boss. Ten regions were checked this way,
/// including four already-correct controls, and all ten matched the right
/// speaker.
///
/// This file holds the parts of that with no I/O and no FFI — which sub-regions
/// are worth asking about, how references are chosen, and how a similarity
/// score becomes a decision — so the rules are testable on the host VM. Only
/// [SpeakerRefiner] touches the model.

/// Guards for the refinement pass. Every field is a reason *not* to act: the
/// pass changes nothing when the evidence is weak.
///
/// **These numbers are measured, on one clip.** Treat them as a starting point
/// that more material should move, not as tuned constants.
class SpeakerRefinement {
  const SpeakerRefinement({
    this.minRegionMs = 400,
    this.minReferenceMs = 1500,
    this.maxReferences = 4,
    this.minSimilarity = 0.20,
    this.minMargin = 0.15,
    this.maxCandidates = 40,
    this.edgeTrimMs = 50,
    this.longSpanMedianMultiple = 1.5,
    this.maxBoundaryStraddle = 0.25,
    this.minReferenceCoherence = 0.5,
  });

  /// Shortest region worth embedding.
  ///
  /// Measured rather than assumed: general guidance for CAM++ suggests about a
  /// second, but on the development clip a 390ms region ("Appie?") separated
  /// correctly with a 0.273 margin, and the 750ms "What do you mean?" did too.
  /// 400ms is the shortest length actually verified here.
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
  ///
  /// This is the real guard. What matters is not how well the winner fits but
  /// how much better it fits than anyone else, because a lone candidate is
  /// always "best". Lowest correct margin measured was 0.170; the lowest among
  /// already-correct controls was 0.206.
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
  ///
  /// **Relative, not absolute, and that is the point.** An unusually long span
  /// is where an unreported turn can hide, but "unusually long" means nothing
  /// in milliseconds: a rapid exchange and a lecture have completely different
  /// span distributions. Measuring against the file's own median self-calibrates
  /// to the material, and — unlike counting sentences — never consults whisper,
  /// so the trigger cannot shift when the transcription model changes.
  final double longSpanMedianMultiple;

  /// How much of a candidate may sit on the far side of a speaker change
  /// before the region is refused outright.
  ///
  /// **A region containing a known handover cannot be asked about**, because
  /// its embedding is a blend of two voices and the model answers honestly
  /// about the blend — which is neither speaker. Both wrong moves measured on
  /// the reference clip were exactly this shape, on both whisper models:
  ///
  /// | region | split across the boundary | outcome |
  /// |---|---|---|
  /// | "Tokens cost money." | no boundary inside it | correct |
  /// | "What do you mean?" | 99 / 1 | correct |
  /// | "I like that one." | 57 / 43 | **wrong** |
  /// | "No, of course… that makes sense." | 61 / 39 | **wrong** |
  ///
  /// The good moves are clean or almost clean; the bad ones are genuinely
  /// mixed. 0.25 sits between the two groups with room on either side, and is
  /// a statement about acoustics rather than a value fitted to a score.
  final double maxBoundaryStraddle;

  /// How much a reference span's two halves must sound like each other before
  /// that span is trusted to represent one voice.
  ///
  /// **This replaces a proxy with the actual property.** A reference is unsafe
  /// when it contains someone else's voice, which happens either because
  /// segmentation declares an overlap or because the span conceals a turn
  /// nobody reported. The second case was previously guessed at from span
  /// length and sentence count — model-dependent, and fitted to one clip.
  /// Splitting the span and asking whether its halves match tests the thing
  /// directly: one speaker talking is internally consistent, two speakers are
  /// not.
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
    this.cutMs,
  });

  final int startMs;
  final int endMs;
  final int currentSpeaker;

  /// Inclusive word range, into the list handed to [planRefinement].
  final int firstWord;
  final int lastWord;

  /// A span boundary landing inside this region and splitting it substantially,
  /// or null when nothing cuts it.
  ///
  /// **A cut is a question, not a verdict.** Such a region *may* be a blend of
  /// two voices, in which case it cannot be interpreted — that is why alberta's
  /// two wrong moves had to be refused. But diarization also invents turns:
  /// "That's right." on `two_speakers.wav` is one speaker across a reported
  /// handover at 17817, flanked by two suspiciously short spans. Refusing on
  /// sight would trust segmentation about exactly the thing it got wrong.
  ///
  /// So the position is carried through to [SpeakerRefiner], which listens to
  /// each side and decides whether the boundary is real.
  final int? cutMs;

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

  /// A speaker change really does run through this region, so its audio is a
  /// blend of two voices and cannot be interpreted. Distinct from
  /// [skippedNoEmbedding]: the model worked, the region was the problem.
  skippedRealBoundary,
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
///
/// **Candidates are sentences whose geometric answer is doubtful**, not every
/// sentence. Two shapes qualify, and between them they cover both failures
/// measured on the development clip:
///
///  - **more than one speaker overlaps the sentence** — the spans disagree, so
///    there is a real question ("What do you mean?", "Of course, yeah, that
///    makes sense.");
///  - **the sentence sits inside one span that also covers other sentences** —
///    a stretch long enough to hide a turn that was never reported ("Tokens
///    cost money.").
///
/// A sentence wholly inside a span covering nothing else is left alone: the
/// segmentation is unambiguous there and embedding it would only add cost and
/// risk.
///
/// **References must not contain the voices under test.** A speaker's
/// reference spans are those overlapping no other speaker's span *and* no
/// candidate region. The span enclosing "Tokens cost money." is itself
/// mixed-speaker, so building the boss's voice print from it would fold the
/// employee's voice into the very reference the employee is compared against,
/// and the comparison would quietly mean nothing.
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
  final sentences = <({int startMs, int endMs, int first, int last})>[];
  var start = 0;
  for (var i = 0; i < words.length; i++) {
    final isLast = i == words.length - 1;
    if (!endsSentence(words[i].text) && !isLast) continue;
    sentences.add((
      startMs: words[start].startMs,
      endMs: words[i].endMs,
      first: start,
      last: i,
    ));
    start = i + 1;
  }

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
    // turn nobody reported can hide. Judged against the file's own median span
    // rather than a fixed duration or a sentence count, so the trigger depends
    // only on diarization — which never sees the transcription model.
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
    // about the blend — which is neither of them. Measured: every wrong move
    // on the reference clip was a region split roughly 60/40 across a
    // boundary, while every correct one was clean or split 99/1.
    //
    // A *cut* is a span edge landing strictly inside the region, which is what
    // splits the audio in two. Two overlapping spans that both cover the whole
    // region are a different thing entirely — that is the ambiguity this pass
    // exists to resolve, and it must still be asked about.
    //
    // Only the position matters: a cut 9ms from the edge leaves the region
    // essentially pure, while one near the middle makes it a blend. Measured on
    // the reference clip, correct moves were cut at 1% and wrong ones at 39-43%.
    // Recorded rather than acted on: whether the cut is real is decided by
    // listening to it, not by trusting segmentation. The most central cut is
    // kept, since that is the one splitting the region most evenly and so the
    // one most likely to make its audio uninterpretable.
    final regionMs = to - from;
    int? cutMs;
    var worstBalance = 0.0;
    for (final span in spans) {
      for (final cut in [span.startMs, span.endMs]) {
        if (cut <= from || cut >= to) continue;
        final balance = math.min(cut - from, to - cut) / regionMs;
        if (balance > config.maxBoundaryStraddle && balance > worstBalance) {
          worstBalance = balance;
          cutMs = cut;
        }
      }
    }

    candidates.add(RefinementCandidate(
      startMs: from,
      endMs: to,
      currentSpeaker: current,
      firstWord: sentence.first,
      lastWord: sentence.last,
      cutMs: cutMs,
    ));
  }

  if (candidates.isEmpty) {
    return const RefinementPlan(references: {}, candidates: []);
  }

  candidates.sort((a, b) => b.durationMs.compareTo(a.durationMs));
  final capped = candidates.take(config.maxCandidates).toList();

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
      // another voice into this speaker's reference. That is checked
      // acoustically by [SpeakerRefiner], which splits each proposed reference
      // and requires its halves to match. Guessing at it here from span length
      // and sentence count was model-dependent and fitted to one clip.
      clean.add(span);
    }
    if (clean.isEmpty) continue;
    clean.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    references[speaker] = [
      for (final span in clean.take(config.maxReferences))
        (startMs: span.startMs, endMs: span.endMs),
    ];
  }

  return RefinementPlan(references: references, candidates: capped);
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
///
/// **Inserting a span is not enough, and getting this wrong makes the whole
/// pass a silent no-op.** [speakerForWord] takes the longest overlap and breaks
/// ties toward the *longer* span, so a freshly inserted 1.5s span sitting
/// inside a 5.3s span of the previous speaker loses every word it was created
/// to claim — indistinguishable from the pass finding nothing.
///
/// So the region is first carved out of every span belonging to anyone else: a
/// span straddling it is split into the part before and the part after, and
/// pieces that collapse to nothing are dropped. Only then is the new span
/// inserted.
///
/// Everything outside moved regions is left exactly as segmentation reported
/// it, which is what keeps this a refinement rather than a replacement. With no
/// moves the output equals the input.
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

  // The carve-out deliberately leaves the winning speaker's own spans alone,
  // so applying the same move twice would insert the region a second time
  // alongside the first. Harmless to attribution, but duplicate spans are
  // wrong output and would double-count in anything that sums span time, so
  // exact repeats are dropped and the pass stays idempotent.
  final seen = <String>{};
  return [
    for (final s in working)
      if (seen.add('${s.speaker}:${s.startMs}-${s.endMs}')) s,
  ];
}
