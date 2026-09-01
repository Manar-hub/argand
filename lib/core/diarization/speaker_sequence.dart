/// Assigns speakers to a whole transcript at once, using whisper's sentences.
///
/// **The problem with deciding one thing at a time.** Every attribution rule
/// this project has tried decides each item in isolation: `speakerForWord`
/// scores one word against the spans covering it, and refinement scores one
/// region against a couple of voice prints. Both can be locally reasonable and
/// jointly absurd — the clearest case being a sentence that comes out half on
/// one speaker and half on another, which no amount of per-word correctness
/// prevents because no per-word rule can see the sentence.
///
/// **The hint whisper is already giving us.** Speakers change between
/// sentences, not usually inside them. Whisper punctuates its output, so that
/// boundary information is free — it costs no model, no extra pass and no
/// audio. Encoding it means a speaker change at a sentence boundary should be
/// ordinary, and one *inside* a sentence should have to justify itself.
///
/// So: cut the transcript into sentence units; sub-divide a unit wherever
/// diarization claims a change inside it; then choose the speaker sequence that
/// maximises total evidence *minus* the cost of every change, with mid-sentence
/// changes costing far more than boundary ones. That is a Viterbi decode, it is
/// linear in the transcript, and it decides the sequence jointly rather than
/// one unit at a time.
///
/// **Why this is not the reverted IoU rule.** That one also worked per
/// sentence, and `44ff53e` concluded "span geometry alone does not resolve this
/// class" because its margin threshold was fitted to one model's word timings.
/// The difference here is not the unit but the *joint* decision: a unit whose
/// own evidence is weak or misleading is carried by its neighbours and by the
/// cost of switching, rather than being judged on its own geometry. Every
/// quantity below is relative — coverage fractions, and a cost expressed as a
/// multiple of the file's own median unit duration — so nothing is calibrated
/// to one model's timings.
library;

import 'dart:math' as math;

import '../text/sentence_units.dart';
import 'speaker_span.dart';

/// A contiguous run of words that is decided as one.
///
/// Usually a whole sentence. It is shorter only where diarization reports a
/// change inside the sentence, which is the case worth arguing about.
class SpeechUnit {
  const SpeechUnit({
    required this.startMs,
    required this.endMs,
    required this.first,
    required this.last,
    required this.startsSentence,
  });

  final int startMs;
  final int endMs;

  /// First word index, inclusive.
  final int first;

  /// Last word index, inclusive.
  final int last;

  /// Whether this unit opens a sentence, rather than continuing one after a cut
  /// diarization put in the middle. This is the whole basis of the cost
  /// asymmetry: changing speaker here is expected, mid-sentence it is not.
  final bool startsSentence;

  int get durationMs => endMs - startMs;
  int get wordCount => last - first + 1;

  @override
  String toString() => 'SpeechUnit($first-$last, $startMs-$endMs'
      '${startsSentence ? '' : ', mid-sentence'})';
}

/// Relative weights for the sequence decode.
///
/// No absolute millisecond or similarity constants: everything scales off the
/// file's own statistics, so the same numbers hold for a different whisper
/// model or a different clip. That is a hard requirement here — the previous
/// sentence-level rule was reverted precisely because its threshold was fitted
/// to one model's word timings and did not transfer.
class SequenceTuning {
  const SequenceTuning({
    this.boundarySwitchCost = 0.0,
    this.midSentenceSwitchCost = 0.6,
    this.acousticWeight = 0.0,
  });

  /// Cost of changing speaker at a sentence boundary, as a multiple of the
  /// median unit duration. Zero, because a change there is simply expected.
  final double boundarySwitchCost;

  /// Cost of changing speaker *inside* a sentence, in the same units.
  ///
  /// Set so a mid-sentence change must be backed by more evidence than half a
  /// typical unit carries. At 1.0 the cost equals the most a single unit can
  /// ever contribute, which makes the rule "never change speaker mid-sentence"
  /// — a different and wrong rule, since whisper does sometimes merge two
  /// speakers into one unpunctuated sentence.
  ///
  /// Provisional, in this project's usual sense: derived from the shape of the
  /// failures rather than swept, and expected to move once the gate has scored
  /// it on more than one clip.
  final double midSentenceSwitchCost;

  /// How much acoustic similarity counts relative to span coverage.
  ///
  /// Zero by default. Geometry alone is the first thing to measure, and adding
  /// an embedding term before knowing whether it is needed is how earlier
  /// refinement reworks came to be behaviour-neutral: "do not confuse tidying a
  /// rule with improving a result". Raise it only against a measured gain.
  final double acousticWeight;

  /// No sequence pressure at all, so every unit takes its own argmax. The
  /// control condition for measuring what the decode itself contributes.
  static const SequenceTuning none = SequenceTuning(
    midSentenceSwitchCost: 0,
    boundarySwitchCost: 0,
  );
}

/// Splits [words] into the units the decode runs over.
///
/// Sentence units first, then a cut wherever a span edge lands strictly inside
/// one — but only where both sides still hold at least one word, since a unit
/// with no words carries no evidence and cannot be assigned.
List<SpeechUnit> speechUnitsOf(
  List<TimedWord> words,
  List<SpeakerSpan> spans,
) {
  final units = <SpeechUnit>[];

  for (final sentence in sentenceUnitsOf(words)) {
    // Every span edge falling strictly inside this sentence is a place
    // diarization claims the speaker changed.
    final cuts = <int>{};
    for (final span in spans) {
      for (final edge in [span.startMs, span.endMs]) {
        if (edge > sentence.startMs && edge < sentence.endMs) cuts.add(edge);
      }
    }

    if (cuts.isEmpty) {
      units.add(SpeechUnit(
        startMs: sentence.startMs,
        endMs: sentence.endMs,
        first: sentence.first,
        last: sentence.last,
        startsSentence: true,
      ));
      continue;
    }

    final ordered = cuts.toList()..sort();
    var first = sentence.first;
    var startsSentence = true;

    for (final cut in ordered) {
      // A word belongs to the side its midpoint falls on, so a word straddling
      // the cut is not torn in half.
      var last = first - 1;
      for (var i = first; i <= sentence.last; i++) {
        final mid = words[i].startMs + (words[i].endMs - words[i].startMs) ~/ 2;
        if (mid >= cut) break;
        last = i;
      }
      if (last < first || last >= sentence.last) continue;

      units.add(SpeechUnit(
        startMs: words[first].startMs,
        endMs: words[last].endMs,
        first: first,
        last: last,
        startsSentence: startsSentence,
      ));
      first = last + 1;
      startsSentence = false;
    }

    units.add(SpeechUnit(
      startMs: words[first].startMs,
      endMs: words[sentence.last].endMs,
      first: first,
      last: sentence.last,
      startsSentence: startsSentence,
    ));
  }

  return units;
}

/// How much of [unit] each speaker's spans cover, as a fraction of the unit.
///
/// A fraction rather than raw milliseconds, for the reason `speakerForWord`
/// uses one: raw overlap lets a long span win merely for being long, which is
/// backwards whenever a brief turn sits inside a longer one.
Map<int, double> coverageOf(SpeechUnit unit, List<SpeakerSpan> spans) {
  final coverage = <int, double>{};
  final duration = unit.durationMs;
  for (final span in spans) {
    final overlap = span.overlapWith(unit.startMs, unit.endMs);
    if (overlap <= 0) continue;
    final fraction = duration > 0 ? overlap / duration : 1.0;
    coverage[span.speaker] = math.max(coverage[span.speaker] ?? 0.0, fraction);
  }
  return coverage;
}

/// One speaker per unit, chosen jointly.
///
/// [similarities] is optional acoustic evidence, keyed unit index then speaker.
/// Absent entries simply contribute nothing, so a unit too short to embed is
/// carried by geometry and by its neighbours rather than by a bad guess — which
/// is the failure mode of asking a 480ms fragment to identify itself.
List<int?> decodeUnitSpeakers({
  required List<SpeechUnit> units,
  required List<SpeakerSpan> spans,
  Map<int, Map<int, double>> similarities = const {},
  SequenceTuning tuning = const SequenceTuning(),
}) {
  if (units.isEmpty) return const [];

  final speakers = {for (final span in spans) span.speaker}.toList()..sort();
  if (speakers.isEmpty) return List<int?>.filled(units.length, null);

  // The evidence scale is the file's own median unit duration, so a switch cost
  // means "worth about one typical unit" on any clip, at any speaking rate,
  // from any model. An absolute millisecond figure would not transfer, and that
  // non-transfer is exactly what sank the previous sentence-level rule.
  final durations = [for (final unit in units) unit.durationMs]..sort();
  final median = durations.length.isOdd
      ? durations[durations.length ~/ 2].toDouble()
      : (durations[durations.length ~/ 2 - 1] +
              durations[durations.length ~/ 2]) /
          2.0;
  final scale = median <= 0 ? 1.0 : median;

  double emission(int unitIndex, int speaker) {
    final unit = units[unitIndex];
    var score = coverageOf(unit, spans)[speaker] ?? 0.0;
    if (tuning.acousticWeight > 0) {
      final similarity = similarities[unitIndex]?[speaker];
      if (similarity != null) score += tuning.acousticWeight * similarity;
    }
    // Weighted by duration: a long unit is more evidence than a short one, and
    // this is what stops a 250ms fragment outvoting the sentence around it.
    return score * unit.durationMs;
  }

  final best = List.generate(
    units.length,
    (_) => List<double>.filled(speakers.length, double.negativeInfinity),
    growable: false,
  );
  final from = List.generate(
    units.length,
    (_) => List<int>.filled(speakers.length, -1),
    growable: false,
  );

  for (var s = 0; s < speakers.length; s++) {
    best[0][s] = emission(0, speakers[s]);
  }

  for (var u = 1; u < units.length; u++) {
    final switchCost = scale *
        (units[u].startsSentence
            ? tuning.boundarySwitchCost
            : tuning.midSentenceSwitchCost);

    for (var s = 0; s < speakers.length; s++) {
      final e = emission(u, speakers[s]);
      for (var p = 0; p < speakers.length; p++) {
        final previous = best[u - 1][p];
        if (previous == double.negativeInfinity) continue;
        final candidate = previous + e - (p == s ? 0.0 : switchCost);
        if (candidate > best[u][s]) {
          best[u][s] = candidate;
          from[u][s] = p;
        }
      }
    }
  }

  var tail = 0;
  for (var s = 1; s < speakers.length; s++) {
    if (best[units.length - 1][s] > best[units.length - 1][tail]) tail = s;
  }

  final chosen = List<int?>.filled(units.length, null);
  for (var u = units.length - 1; u >= 0; u--) {
    chosen[u] = speakers[tail];
    if (u > 0) {
      final previous = from[u][tail];
      if (previous >= 0) tail = previous;
    }
  }
  return chosen;
}

/// Per-word speakers, decided as a sequence over sentence-led units.
///
/// A drop-in alternative to `assignSpeakers`, kept beside it rather than
/// replacing it so both can be run over the same audio and compared. Nothing
/// here ships until that comparison says it should.
List<int?> assignSpeakersBySequence(
  List<TimedWord> words,
  List<SpeakerSpan> spans, {
  Map<int, Map<int, double>> similarities = const {},
  SequenceTuning tuning = const SequenceTuning(),
}) {
  final assigned = List<int?>.filled(words.length, null);
  if (words.isEmpty || spans.isEmpty) return assigned;

  final units = speechUnitsOf(words, spans);
  final chosen = decodeUnitSpeakers(
    units: units,
    spans: spans,
    similarities: similarities,
    tuning: tuning,
  );

  for (var u = 0; u < units.length; u++) {
    for (var i = units[u].first; i <= units[u].last; i++) {
      assigned[i] = chosen[u];
    }
  }
  return assigned;
}
