/// Assembles diarization spans into phrases and assigns each phrase a speaker.
///
/// **Why this exists.** sherpa's `process()` does segmentation, embedding and
/// clustering in one opaque call and hands back segments that already carry
/// speaker ids. Its clustering has a single threshold and no protection against
/// a contaminated embedding, so two failure modes get through:
///
///  * **mid-sentence cutoffs** — one speaker drops pitch or pauses briefly,
///    segmentation emits two spans, and clustering puts the halves on different
///    people;
///  * **cross-talk bundling** — a brief overlap produces an embedding that
///    belongs to neither speaker, which then pollutes whichever profile it lands
///    in and can collapse two people into one id for the rest of the file.
///
/// This module reassigns identity from the boundaries alone. sherpa's labels are
/// **discarded**; only its span geometry is kept. Phrases are bridged across
/// micro-silences before anything is embedded, identity is tracked with a
/// two-threshold state machine so staying is easier than switching, and only
/// clean phrases are allowed to move a centroid.
///
/// **It is also the fix for a measured model-dependence.** Speaker refinement
/// today builds its candidate regions from *sentence extents*, and sentences
/// come from whisper — so the same audio refines differently under different
/// transcription models. On `two_speakers.wav` both models emit 16 sentences but
/// place them differently (#8 at 16960-17960 on base against 17200-18560 on
/// `small-q5_1`), which is enough to flip two marginal cases. Phrases here are
/// built from span geometry, which whisper never touches, so attribution cannot
/// move when the transcription model changes.
///
/// Pure and host-testable throughout: no I/O, no FFI, no engine types. The
/// caller supplies embeddings; this file supplies the rules.
library;

import 'dart:typed_data';

import 'speaker_refinement.dart' show centroidOf, cosineSimilarity, unitVector;
import 'speaker_span.dart';

/// Every tunable, in one place.
///
/// Deliberately a config object rather than constants: these need sweeping
/// against labelled clips, and a value that must be edited in code is a value
/// nobody sweeps. **No numeric literal belongs in the logic below** — if a rule
/// needs a number, it needs a field here.
class TurnAssembly {
  const TurnAssembly({
    this.minSilenceBridgeMs = 250,
    this.keepSpeakerThreshold = 0.30,
    this.switchSpeakerThreshold = 0.50,
    this.newSpeakerThreshold = 0.20,
    this.minCleanProfileMs = 1500,
    this.maxProfileOverlapFraction = 0.10,
    this.maxSpeakers = 8,
    this.edgeTrimMs = 50,
    this.maxPhrasesEmbedded = 120,
  }) : assert(
          keepSpeakerThreshold < switchSpeakerThreshold,
          'hysteresis requires keeping to be easier than switching; equal '
          'thresholds collapse this back to a single static boundary',
        );

  /// Gap below which two adjacent spans join one phrase.
  ///
  /// This is the mid-sentence-cutoff fix. A speaker who pauses briefly or drops
  /// pitch gets split into two spans; bridging them yields one longer region to
  /// embed, which is both more accurate and cheaper. Overlapping spans are never
  /// bridged however small the gap, because simultaneous speech is evidence of
  /// two people rather than one pause.
  final int minSilenceBridgeMs;

  /// Similarity to the *current* speaker that is enough to stay with them.
  ///
  /// Deliberately lenient. Within one person's turn the voice moves — pitch
  /// falls at the end of a clause, volume drops on an aside — and a single
  /// static threshold reads that as a new person.
  final double keepSpeakerThreshold;

  /// Similarity to a *different* speaker required before switching to them.
  ///
  /// Deliberately strict, and the whole point of the pair: the asymmetry is what
  /// makes a handover need real evidence while a wobble does not.
  final double switchSpeakerThreshold;

  /// Below this against every known speaker, the phrase opens a new identity
  /// rather than being forced onto the least-bad match.
  final double newSpeakerThreshold;

  /// Shortest phrase permitted to update a speaker's centroid.
  ///
  /// The profile-updating vs inference-only split. A short interjection is
  /// exactly the material most likely to be contaminated by the speaker either
  /// side of it, and averaging it into a profile is how one bad region poisons
  /// every later decision.
  final int minCleanProfileMs;

  /// Fraction of a phrase that may be cross-talk before it becomes
  /// inference-only. Zero would be stricter than the data supports; segmentation
  /// routinely reports a few milliseconds of overlap at a clean handover.
  final double maxProfileOverlapFraction;

  /// Ceiling on distinct identities, so a pathological file cannot open a new
  /// speaker for every phrase.
  final int maxSpeakers;

  /// Trimmed from each end before embedding. Boundary drift puts the
  /// neighbouring speaker at the edges, which is the worst place to sample.
  final int edgeTrimMs;

  /// Import-cost ceiling on how many phrases get embedded.
  final int maxPhrasesEmbedded;

  /// Assembly off, for measuring what it contributes — same shape as
  /// [SpeakerRefinement.none].
  static const TurnAssembly none = TurnAssembly(maxPhrasesEmbedded: 0);

  bool get isEnabled => maxPhrasesEmbedded > 0;
}

/// A continuous run of speech, built from span geometry with labels discarded.
class Phrase {
  const Phrase({
    required this.startMs,
    required this.endMs,
    required this.crossTalkMs,
    required this.spanCount,
  });

  final int startMs;
  final int endMs;

  /// Milliseconds inside this phrase where two spans overlapped — simultaneous
  /// speech, and therefore an embedding that belongs to neither speaker.
  final int crossTalkMs;

  /// How many spans were bridged into this phrase. More than one means a
  /// micro-silence was closed.
  final int spanCount;

  int get durationMs => endMs - startMs;

  double get crossTalkFraction =>
      durationMs <= 0 ? 0.0 : crossTalkMs / durationMs;

  /// Whether this phrase is clean enough to move a centroid.
  bool profileEligible(TurnAssembly config) =>
      durationMs >= config.minCleanProfileMs &&
      crossTalkFraction <= config.maxProfileOverlapFraction;

  /// The region actually worth embedding, with drift-prone edges removed.
  /// Null when trimming would leave nothing.
  ({int startMs, int endMs})? embedRegion(TurnAssembly config) {
    final from = startMs + config.edgeTrimMs;
    final to = endMs - config.edgeTrimMs;
    return to > from ? (startMs: from, endMs: to) : null;
  }

  @override
  String toString() => 'Phrase($startMs-${endMs}ms, spans $spanCount'
      '${crossTalkMs > 0 ? ", crossTalk ${crossTalkMs}ms" : ""})';
}

/// Groups [spans] into phrases, discarding their speaker labels.
///
/// Two spans join one phrase when the gap between them is under
/// [TurnAssembly.minSilenceBridgeMs] **and** they do not overlap. The overlap
/// exception is load-bearing: overlapping spans have a gap of zero and would
/// otherwise always bridge, merging exactly the simultaneous speech this design
/// exists to isolate.
List<Phrase> buildPhrases(
  List<SpeakerSpan> spans, {
  TurnAssembly config = const TurnAssembly(),
}) {
  if (spans.isEmpty) return const [];

  final ordered = [...spans]..sort((a, b) {
      final byStart = a.startMs.compareTo(b.startMs);
      return byStart != 0 ? byStart : a.endMs.compareTo(b.endMs);
    });

  final phrases = <Phrase>[];
  var startMs = ordered.first.startMs;
  var endMs = ordered.first.endMs;
  var spanCount = 1;
  var crossTalkMs = 0;

  void flush() => phrases.add(Phrase(
        startMs: startMs,
        endMs: endMs,
        crossTalkMs: crossTalkMs,
        spanCount: spanCount,
      ));

  for (final span in ordered.skip(1)) {
    final overlap = span.overlapWith(startMs, endMs);
    final gap = span.gapTo(startMs, endMs);

    if (overlap > 0) {
      // Simultaneous speech. Record it and close the phrase here — merging
      // would produce the blended embedding this design refuses to trust.
      crossTalkMs += overlap;
      flush();
      startMs = span.startMs;
      endMs = span.endMs;
      spanCount = 1;
      crossTalkMs = 0;
      continue;
    }

    if (gap < config.minSilenceBridgeMs) {
      if (span.endMs > endMs) endMs = span.endMs;
      spanCount++;
      continue;
    }

    flush();
    startMs = span.startMs;
    endMs = span.endMs;
    spanCount = 1;
    crossTalkMs = 0;
  }
  flush();

  return phrases;
}

/// What the state machine did with one phrase.
enum TurnOutcome {
  /// Held the current speaker despite a dip — the hysteresis working.
  kept,

  /// Crossed [TurnAssembly.switchSpeakerThreshold] to a different speaker.
  switched,

  /// Matched nobody well enough; a new identity was opened.
  opened,

  /// First phrase of the file, or the first with a usable embedding.
  seeded,

  /// No embedding, or the speaker ceiling was reached with no match.
  unassigned,
}

/// One phrase's decision, kept so a probe can explain a result.
class TurnDecision {
  const TurnDecision({
    required this.phraseIndex,
    required this.outcome,
    required this.speaker,
    required this.similarities,
    required this.updatedProfile,
  });

  final int phraseIndex;
  final TurnOutcome outcome;
  final int? speaker;

  /// Speaker id to cosine similarity. Empty when nothing was embedded.
  final Map<int, double> similarities;

  /// Whether this phrase was allowed to move its speaker's centroid.
  final bool updatedProfile;

  @override
  String toString() => '#$phraseIndex ${outcome.name} -> '
      '${speaker ?? "none"}${updatedProfile ? " (profile)" : ""}';
}

/// The result of walking every phrase.
class TurnAssignment {
  const TurnAssignment({required this.speakers, required this.decisions});

  /// One speaker id per phrase, aligned with the input list. Null where nothing
  /// could be decided.
  final List<int?> speakers;

  final List<TurnDecision> decisions;

  int get speakerCount => {for (final s in speakers) ?s}.length;

  /// Re-emits the assignment as spans, which is what the rest of the pipeline
  /// already consumes.
  List<SpeakerSpan> toSpans(List<Phrase> phrases) => [
        for (final (i, phrase) in phrases.indexed)
          if (speakers[i] case final int speaker)
            SpeakerSpan(
              startMs: phrase.startMs,
              endMs: phrase.endMs,
              speaker: speaker,
            ),
      ];
}

/// Walks [phrases] in time order, assigning each one a speaker.
///
/// [embeddings] is one vector per phrase, null where the phrase was not
/// embedded. Taking vectors rather than doing the extraction keeps every rule
/// here pure and testable against hand-built vectors.
///
/// **The hysteresis.** Staying with the current speaker needs only
/// [TurnAssembly.keepSpeakerThreshold]; moving to another needs
/// [TurnAssembly.switchSpeakerThreshold]. That asymmetry is the whole mechanism
/// — a pitch drop mid-turn dips the similarity but rarely below the lenient
/// bound, while a real handover clears the strict one.
///
/// **The pollution guard.** A phrase updates its speaker's centroid only when
/// [Phrase.profileEligible]. Short or overlap-heavy phrases are still assigned —
/// they are inference-only, never profile-updating.
TurnAssignment assignTurns({
  required List<Phrase> phrases,
  required List<Float32List?> embeddings,
  TurnAssembly config = const TurnAssembly(),
}) {
  assert(
    phrases.length == embeddings.length,
    'every phrase needs an embedding slot, even if it is null',
  );

  final speakers = <int?>[];
  final decisions = <TurnDecision>[];

  // Unit vectors per speaker, averaged into a centroid on demand. Kept as a
  // list rather than a running mean so a later phrase cannot outweigh the
  // evidence that established the identity.
  final profiles = <int, List<Float32List>>{};
  int? current;

  Float32List? centroid(int speaker) {
    final vectors = profiles[speaker];
    if (vectors == null || vectors.isEmpty) return null;
    return centroidOf(vectors);
  }

  for (final (index, phrase) in phrases.indexed) {
    final embedding = unitVector(embeddings[index]);
    if (embedding == null) {
      speakers.add(current);
      decisions.add(TurnDecision(
        phraseIndex: index,
        outcome: TurnOutcome.unassigned,
        speaker: current,
        similarities: const {},
        updatedProfile: false,
      ));
      continue;
    }

    final similarities = <int, double>{};
    for (final speaker in profiles.keys) {
      final c = centroid(speaker);
      if (c != null) similarities[speaker] = cosineSimilarity(embedding, c);
    }

    int? chosen;
    TurnOutcome outcome;

    if (similarities.isEmpty) {
      chosen = 0;
      outcome = TurnOutcome.seeded;
    } else {
      final currentScore = current == null ? null : similarities[current];
      if (currentScore != null && currentScore >= config.keepSpeakerThreshold) {
        chosen = current;
        outcome = TurnOutcome.kept;
      } else {
        var bestSpeaker = -1;
        var bestScore = -2.0;
        similarities.forEach((speaker, score) {
          if (speaker != current && score > bestScore) {
            bestScore = score;
            bestSpeaker = speaker;
          }
        });

        if (bestSpeaker >= 0 && bestScore >= config.switchSpeakerThreshold) {
          chosen = bestSpeaker;
          outcome = TurnOutcome.switched;
        } else if (bestScore < config.newSpeakerThreshold &&
            profiles.length < config.maxSpeakers) {
          chosen = profiles.keys.fold(-1, (m, s) => s > m ? s : m) + 1;
          outcome = TurnOutcome.opened;
        } else if (current != null) {
          // Not similar enough to switch, not different enough to be new.
          // Holding is the conservative answer and keeps a wobble from
          // fragmenting one person into several.
          chosen = current;
          outcome = TurnOutcome.kept;
        } else {
          chosen = bestSpeaker >= 0 ? bestSpeaker : 0;
          outcome = TurnOutcome.seeded;
        }
      }
    }

    final eligible = phrase.profileEligible(config);
    if (eligible && chosen != null) {
      (profiles[chosen] ??= <Float32List>[]).add(embedding);
    }

    current = chosen;
    speakers.add(chosen);
    decisions.add(TurnDecision(
      phraseIndex: index,
      outcome: outcome,
      speaker: chosen,
      similarities: similarities,
      updatedProfile: eligible && chosen != null,
    ));
  }

  return TurnAssignment(speakers: speakers, decisions: decisions);
}
