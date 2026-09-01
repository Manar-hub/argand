import 'package:argand/core/diarization/speaker_sequence.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/text/sentence_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Builds evenly spaced words from `text|durationMs` style input.
  List<TimedWord> wordsFrom(List<(String, int, int)> spec) => [
        for (final (text, startMs, endMs) in spec)
          (text: text, startMs: startMs, endMs: endMs),
      ];

  SpeakerSpan span(int startMs, int endMs, int speaker) =>
      SpeakerSpan(startMs: startMs, endMs: endMs, speaker: speaker);

  group('speechUnitsOf', () {
    test('a sentence with no internal cut is one unit', () {
      final words = wordsFrom(const [
        ('Hello', 0, 500),
        ('there.', 500, 1000),
      ]);
      final units = speechUnitsOf(words, [span(0, 1000, 0)]);
      expect(units, hasLength(1));
      expect(units.single.startsSentence, isTrue);
    });

    test('a span edge inside a sentence splits it', () {
      final words = wordsFrom(const [
        ('That\'s', 0, 500),
        ('right.', 500, 1000),
      ]);
      final units = speechUnitsOf(words, [
        span(0, 500, 0),
        span(500, 1000, 1),
      ]);
      expect(units, hasLength(2));
      expect(units[0].startsSentence, isTrue);
      // The second half continues a sentence, which is what makes changing
      // speaker there expensive rather than routine.
      expect(units[1].startsSentence, isFalse);
    });

    test('a cut that would leave a side wordless is ignored', () {
      // A unit holding no words carries no evidence and cannot be assigned, so
      // the cut is simply not taken.
      final words = wordsFrom(const [
        ('One', 0, 500),
        ('two.', 500, 1000),
      ]);
      final units = speechUnitsOf(words, [span(0, 10, 0), span(10, 1000, 1)]);
      expect(units, hasLength(1));
    });

    test('every word lands in exactly one unit', () {
      final words = wordsFrom(const [
        ('a', 0, 300),
        ('b', 300, 600),
        ('c.', 600, 900),
        ('d', 900, 1200),
        ('e.', 1200, 1500),
      ]);
      final units = speechUnitsOf(words, [
        span(0, 400, 0),
        span(400, 1500, 1),
      ]);
      final covered = <int>[];
      for (final unit in units) {
        for (var i = unit.first; i <= unit.last; i++) {
          covered.add(i);
        }
      }
      expect(covered, [0, 1, 2, 3, 4]);
    });
  });

  group('assignSpeakersBySequence', () {
    test('a clean two-speaker exchange is unchanged', () {
      final words = wordsFrom(const [
        ('Yes.', 0, 1000),
        ('No.', 1000, 2000),
      ]);
      final assigned = assignSpeakersBySequence(words, [
        span(0, 1000, 0),
        span(1000, 2000, 1),
      ]);
      expect(assigned, [0, 1]);
    });

    test('a spurious mid-sentence handover is overruled', () {
      // The shape of `two_speakers.wav` #8: a sentence that is one speaker in
      // truth, which diarization splits with a short span it should not have
      // reported. Per-word geometry has no way to refuse — the short span
      // genuinely covers those words — so the sentence comes out half and half.
      // Deciding the sequence lets the cost of a mid-sentence change outweigh a
      // brief span's local evidence.
      final words = wordsFrom(const [
        ('I', 0, 4000),
        ('was', 4000, 8000),
        ('there.', 8000, 12000),
        ('That\'s', 12000, 13000),
        ('right.', 13000, 14000),
        ('It', 14000, 18000),
        ('was.', 18000, 22000),
      ]);
      final spans = [
        span(0, 13200, 1),
        span(13200, 13900, 0),
        span(13900, 22000, 1),
      ];

      final sequence = assignSpeakersBySequence(words, spans);
      expect(sequence, everyElement(1));

      // And the control: with no sequence pressure the same inputs split the
      // sentence, which is what the shipped per-unit view of this data does.
      final unconstrained = assignSpeakersBySequence(
        words,
        spans,
        tuning: SequenceTuning.none,
      );
      expect(unconstrained, isNot(everyElement(1)));
    });

    test('a genuine mid-sentence handover survives', () {
      // The guard on the rule above. When both sides of the change carry real
      // duration, the evidence outweighs the switch cost and the split stands —
      // otherwise this would simply be "never change speaker mid-sentence",
      // which is a different and wrong rule.
      final words = wordsFrom(const [
        ('I', 0, 5000),
        ('think', 5000, 10000),
        ('actually', 10000, 15000),
        ('no.', 15000, 20000),
      ]);
      final assigned = assignSpeakersBySequence(words, [
        span(0, 10000, 0),
        span(10000, 20000, 1),
      ]);
      expect(assigned, [0, 0, 1, 1]);
    });

    test('changing speaker at a sentence boundary stays free', () {
      final words = wordsFrom(const [
        ('Yes.', 0, 1000),
        ('Well.', 1000, 2000),
        ('Fine.', 2000, 3000),
      ]);
      final assigned = assignSpeakersBySequence(words, [
        span(0, 1000, 0),
        span(1000, 2000, 1),
        span(2000, 3000, 0),
      ]);
      expect(assigned, [0, 1, 0]);
    });

    test('a short fragment inside a sentence is carried by its neighbours', () {
      // A brief sliver surrounded by one voice takes that voice rather than
      // whatever 250ms of span happens to say, because evidence is weighted by
      // duration and the change would be mid-sentence.
      final words = wordsFrom(const [
        ('Long', 0, 6000),
        ('opening', 6000, 12000),
        ('hm', 12000, 12250),
        ('long', 12250, 18000),
        ('close.', 18000, 24000),
      ]);
      final assigned = assignSpeakersBySequence(words, [
        span(0, 12000, 0),
        span(12000, 12250, 1),
        span(12250, 24000, 0),
      ]);
      expect(assigned, everyElement(0));
    });

    test('a short whole sentence is NOT protected, and that is deliberate', () {
      // The limit of this rule, pinned so it is not mistaken for a bug.
      //
      // `two_speakers.wav` #14 "It was the first one." is a short sentence
      // between two stretches of the other speaker, and it is labelled as the
      // *other* voice — so a rule that pulled short sentences toward their
      // neighbours would get it wrong in the opposite direction, and one that
      // pulled it the truthful way would have to know the answer already.
      //
      // A sentence boundary is where speakers are expected to change, so
      // switching across one stays free. This rule therefore cannot reach #14,
      // whose own acoustic evidence sits in the band the notes describe as "the
      // region cannot answer" (0.222 against 0.100, wrong winner, unmoved
      // across seven window widths). Fixing it needs evidence this rule does
      // not have, not a bigger penalty.
      final words = wordsFrom(const [
        ('Long', 0, 6000),
        ('opening.', 6000, 12000),
        ('Hm.', 12000, 12250),
        ('Long', 12250, 18000),
        ('close.', 18000, 24000),
      ]);
      final assigned = assignSpeakersBySequence(words, [
        span(0, 12000, 0),
        span(12000, 12250, 1),
        span(12250, 24000, 0),
      ]);
      expect(assigned[2], 1);
    });

    test('acoustic evidence is off unless asked for', () {
      final words = wordsFrom(const [
        ('One.', 0, 1000),
        ('Two.', 1000, 2000),
      ]);
      final spans = [span(0, 2000, 0), span(1000, 2000, 1)];
      final similarities = {
        1: {0: 0.1, 1: 0.9},
      };

      final without = assignSpeakersBySequence(
        words,
        spans,
        similarities: similarities,
      );
      final with_ = assignSpeakersBySequence(
        words,
        spans,
        similarities: similarities,
        tuning: const SequenceTuning(acousticWeight: 4),
      );
      expect(without, isNot(equals(with_)));
    });

    test('no spans leaves every word unassigned', () {
      final words = wordsFrom(const [('Hi.', 0, 500)]);
      expect(assignSpeakersBySequence(words, const []), [null]);
    });

    test('an empty transcript is handled', () {
      expect(assignSpeakersBySequence(const [], [span(0, 1, 0)]), isEmpty);
    });

    test('one speaker everywhere yields one speaker everywhere', () {
      final words = wordsFrom(const [
        ('A.', 0, 1000),
        ('B.', 1000, 2000),
      ]);
      expect(assignSpeakersBySequence(words, [span(0, 2000, 3)]), [3, 3]);
    });
  });
}
