import 'package:argand/core/transcript/sentence_edit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the word list a sentence editor would be handed.
List<EditableWord> words(List<(String, int, int)> spec) => [
      for (final (index, entry) in spec.indexed)
        (id: 'w$index', text: entry.$1, startMs: entry.$2, endMs: entry.$3),
    ];

/// The one invariant every plan must satisfy, checked separately from whatever
/// each test is actually about.
void expectSpanPreserved(SentenceEditPlan plan, List<EditableWord> original) {
  final start = original.first.startMs;
  final end = original.map((w) => w.endMs).reduce((a, b) => a > b ? a : b);

  expect(plan.words.first.startMs, start,
      reason: 'the sentence must still begin where it began');
  expect(plan.words.last.endMs, end,
      reason: 'the sentence must still end where it ended');

  var previous = start - 1;
  for (final word in plan.words) {
    expect(word.startMs, greaterThanOrEqualTo(previous),
        reason: 'timings must not run backwards');
    expect(word.endMs, greaterThanOrEqualTo(word.startMs));
    previous = word.startMs;
  }
}

void main() {
  group('the reported case: one word heard as two', () {
    // "brainbeats" transcribed where the speaker said "praying beads".
    final original = words([('brainbeats', 1000, 2200)]);

    test('splits the one span between the two new words', () {
      final plan = planSentenceEdit(original: original, text: 'praying beads')!;

      expect(plan.changed, isTrue);
      expect(plan.words.map((w) => w.text), ['praying', 'beads']);
      expectSpanPreserved(plan, original);

      // Proportional to length: "praying" is 7 of the 12 characters, so it
      // takes 7/12 of the 1200ms span.
      expect(plan.words.first.startMs, 1000);
      expect(plan.words.first.endMs, 1700);
      expect(plan.words.last.startMs, 1700);
      expect(plan.words.last.endMs, 2200);
    });

    test('amends the existing row rather than replacing it', () {
      final plan = planSentenceEdit(original: original, text: 'praying beads')!;

      // The first keeps the row it came from, so an older undo event that
      // addresses that word by id still resolves. The second is genuinely new.
      expect(plan.words.first.id, 'w0');
      expect(plan.words.last.id, isNull);
    });
  });

  group('untouched words keep their exact timings', () {
    final original = words([
      ('It', 0, 300),
      ('was', 300, 700),
      ('brainbeats', 700, 1900),
      ('again', 1900, 2400),
    ]);

    test('only the corrected word is retimed', () {
      final plan = planSentenceEdit(
        original: original,
        text: 'It was praying beads again',
      )!;

      expect(plan.words.map((w) => w.text),
          ['It', 'was', 'praying', 'beads', 'again']);
      expectSpanPreserved(plan, original);

      // The three words the user did not touch are byte-identical. A naive
      // re-spread over the sentence would have nudged every one of them.
      expect((plan.words[0].startMs, plan.words[0].endMs), (0, 300));
      expect((plan.words[1].startMs, plan.words[1].endMs), (300, 700));
      expect((plan.words[4].startMs, plan.words[4].endMs), (1900, 2400));

      // And the replacement stays inside the span it replaced.
      expect(plan.words[2].startMs, 700);
      expect(plan.words[3].endMs, 1900);
    });

    test('their row ids survive', () {
      final plan = planSentenceEdit(
        original: original,
        text: 'It was praying beads again',
      )!;

      expect(plan.words[0].id, 'w0');
      expect(plan.words[1].id, 'w1');
      expect(plan.words[4].id, 'w3');
    });
  });

  group('other shapes of edit', () {
    final original = words([
      ('One', 0, 400),
      ('two', 400, 800),
      ('three', 800, 1200),
    ]);

    test('a plain substitution keeps the word count and the span', () {
      final plan = planSentenceEdit(original: original, text: 'One two four')!;

      expect(plan.words.map((w) => w.text), ['One', 'two', 'four']);
      expect((plan.words[2].startMs, plan.words[2].endMs), (800, 1200));
      expectSpanPreserved(plan, original);
    });

    test('three words collapsing to one takes the whole span', () {
      final plan = planSentenceEdit(original: original, text: 'Onetwothree')!;

      expect(plan.words, hasLength(1));
      expect(plan.words.single.startMs, 0);
      expect(plan.words.single.endMs, 1200);
    });

    test('a word inserted between two kept words takes the gap', () {
      final spaced = words([('One', 0, 400), ('three', 900, 1200)]);
      final plan = planSentenceEdit(original: spaced, text: 'One two three')!;

      expect(plan.words.map((w) => w.text), ['One', 'two', 'three']);
      // The kept words are untouched and the newcomer occupies the silence
      // between them, rather than pushing either aside.
      expect((plan.words[0].startMs, plan.words[0].endMs), (0, 400));
      expect((plan.words[2].startMs, plan.words[2].endMs), (900, 1200));
      expect(plan.words[1].startMs, greaterThanOrEqualTo(400));
      expect(plan.words[1].endMs, lessThanOrEqualTo(900));
      expectSpanPreserved(plan, spaced);
    });

    test('a deleted word leaves the rest where they were', () {
      final plan = planSentenceEdit(original: original, text: 'One three')!;

      expect(plan.words.map((w) => w.text), ['One', 'three']);
      expectSpanPreserved(plan, original);
    });

    test('replacing the whole sentence still fills exactly its span', () {
      final plan = planSentenceEdit(
        original: original,
        text: 'Something else entirely now',
      )!;

      expect(plan.words, hasLength(4));
      expectSpanPreserved(plan, original);
    });

    test('adding punctuation is an edit, and keeps the timing', () {
      final plan = planSentenceEdit(original: original, text: 'One two three.')!;

      expect(plan.changed, isTrue);
      expect(plan.words.last.text, 'three.');
      expect((plan.words[2].startMs, plan.words[2].endMs), (800, 1200));
    });
  });

  group('refusals and no-ops', () {
    final original = words([('One', 0, 400), ('two', 400, 800)]);

    test('retyping the same text reports no change', () {
      final plan = planSentenceEdit(original: original, text: 'One two')!;

      expect(plan.changed, isFalse);
      expect(plan.words, original);
    });

    test('surrounding and repeated whitespace is not an edit', () {
      final plan = planSentenceEdit(original: original, text: '  One   two  ')!;
      expect(plan.changed, isFalse);
    });

    test('emptying the box is refused rather than deleting the speech', () {
      // Cutting content is the media editor's job. An empty sentence would
      // leave a hole in the timeline nothing else in the app expects.
      expect(planSentenceEdit(original: original, text: ''), isNull);
      expect(planSentenceEdit(original: original, text: '   '), isNull);
    });

    test('an empty original is refused', () {
      expect(planSentenceEdit(original: const [], text: 'anything'), isNull);
    });

    test('a newline typed into the box is just a word separator', () {
      final plan = planSentenceEdit(original: original, text: 'One\ntwo')!;
      expect(plan.changed, isFalse);
    });
  });

  group('degenerate timings survive', () {
    test('a zero-length sentence still produces ordered words', () {
      final flat = words([('Blip', 5000, 5000)]);
      final plan = planSentenceEdit(original: flat, text: 'Blip blop')!;

      expectSpanPreserved(plan, flat);
      for (final word in plan.words) {
        expect(word.startMs, 5000);
        expect(word.endMs, 5000);
      }
    });

    test('an inverted word end does not produce a backwards sentence', () {
      // The drift `CaptionCue` guards against: a later word ending earlier.
      final inverted = words([('One', 0, 900), ('two', 400, 600)]);
      final plan = planSentenceEdit(original: inverted, text: 'One two three')!;

      // The span end is the maximum, not the last word's end.
      expect(plan.words.last.endMs, 900);
      expectSpanPreserved(plan, inverted);
    });
  });

  test('sentenceTextOf round-trips through an unchanged edit', () {
    final original = words([('One', 0, 400), ('two.', 400, 800)]);
    final text = sentenceTextOf(original);

    expect(text, 'One two.');
    expect(planSentenceEdit(original: original, text: text)!.changed, isFalse);
  });
}
