/// Challenges short spans that segmentation may have invented.
///
/// **Why this layer exists.** Every attribution rule in this pipeline reads
/// diarization's spans as given and argues about how to map words onto them.
/// That cannot fix a span which should not be there. On a two-speaker interview
/// the segmenter reports a brief handover in the middle of one speaker's
/// sentence, flanked on both sides by that same speaker — and once that edge
/// exists, whether a word lands left or right of it decides its speaker. Two
/// whisper models placing the same word a few hundred milliseconds apart then
/// disagree about who said it, which is how a *more accurate* transcription
/// model ends up with *worse* speaker labels.
///
/// **Why it is the right layer.** Spans come from audio alone; whisper never
/// touches them. A correction made here is therefore identical for every
/// transcription model by construction, rather than by tuning. Nothing
/// downstream needs to know: the output is the same `SpeakerSpan` list the rest
/// of the pipeline already consumes.
///
/// **What it does not do.** It never invents a boundary, never moves one, and
/// never deletes audio. It only re-labels a short span to the speaker
/// surrounding it, and only when the audio agrees on a clear margin. A short
/// span that genuinely holds a different voice — a one-word interjection, which
/// this material is full of — sounds like that voice and survives untouched.
library;

import 'speaker_span.dart';

/// Thresholds for [suspectSpans] and [applyValidations].
///
/// Every duration is absolute rather than a fraction of the file: a spurious
/// handover is short in seconds, not short relative to how long the recording
/// happens to run.
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
  ///
  /// A clean stretch of one voice scores 0.7-0.9 against its own print. A short
  /// span sitting in the pause between two utterances is mostly breath and room
  /// tone, and scores far lower against *everyone* — at which point whichever
  /// speaker edges ahead is noise, not a finding. Measured: a genuine
  /// interjection scored 0.569 for its own speaker, while a span the labels say
  /// never happened scored 0.359 and 0.273, both far under any clean region on
  /// the same clip.
  final double minConfidentSimilarity;

  /// How much of the suspect the challenger must also claim before structure
  /// alone is allowed to decide it.
  ///
  /// A challenger *overlapping* the suspect means segmentation has both people
  /// talking at once here — and a real handover does not work that way: the
  /// next speaker does not start before the current one's span ends. Combined
  /// with audio too weak to answer, that is the signature of an inserted
  /// boundary rather than a turn.
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
///
/// "Surrounded" is measured by coverage rather than by list adjacency, because
/// diarization emits overlapping spans and the span before this one in the list
/// is not reliably the span before it in the audio. A challenger must hold
/// audio on **both** sides: a short span at a genuine turn boundary has the
/// other speaker on one side only, and re-labelling it would erase a real turn.
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
///
/// [similarities] maps speaker to cosine similarity for the suspect's region.
/// An empty map means the region could not be embedded, which is not evidence
/// against the incumbent — it is no evidence at all, so nothing moves.
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
  // real: the challenger is already speaking inside this span. Deciding on
  // structure here rather than on a noise-level difference is the whole point
  // of the confidence floor -- without it, whichever speaker happens to edge
  // ahead in a stretch of breath and room tone gets to keep the span.
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
