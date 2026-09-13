import 'package:argand/core/captions/caption_grouper.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/text/transcript_diff.dart';
import 'package:argand/core/transcript/sentence_edit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Why a retyped line splits where it does.
///
/// Reported from `syria.mp4`: the caption read *"This is a good visit also
/// yeah"*, was retyped as *"look at this. This is also shia-"*, and came back as
/// two captions broken at a plausible time. The question was whether that was
/// chance.
///
/// Two separate mechanisms produce that outcome and they are worth keeping
/// apart:
///
///  - **That it splits at all** is the full stop. `groupIntoCues` breaks after
///    any word `endsSentence` accepts. Deterministic, and nothing to do with
///    timing.
///  - **Where in time it splits** is `planSentenceEdit`, and depends entirely on
///    how `alignWords` paired the old words against the new ones. That is what
///    this file pins down.
///
/// The timings below are evenly spaced and are **not** `syria.mp4`'s real ones —
/// that clip has no ground truth (open debt 8). They show the mechanism and the
/// proportion, not the millisecond error on that clip.
void main() {
  const oldText = 'This is a good visit also yeah';
  const newText = 'look at this. This is also shia-';

  void log(String message) => debugPrint('SYRIA $message');

  /// Seven words, 400ms each, starting at 10s — an ordinary stretch of speech.
  List<EditableWord> originalWords() {
    final tokens = oldText.split(' ');
    return [
      for (final (index, token) in tokens.indexed)
        (
          id: 'w$index',
          text: token,
          startMs: 10000 + index * 400,
          endMs: 10000 + (index + 1) * 400,
        ),
    ];
  }

  test('the alignment decides which words keep real timings', () {
    final before = oldText.split(' ');
    final after = newText.split(' ');

    final steps = alignWords(before, after);

    log('--- alignment ---');
    for (final step in steps) {
      final from = step.reference == null ? '—' : before[step.reference!];
      final to = step.candidate == null ? '—' : after[step.candidate!];
      final kind = step.matched
          ? 'MATCH'
          : step.reference == null
              ? 'insert'
              : step.candidate == null
                  ? 'delete'
                  : 'sub';
      log('  ${kind.padRight(6)} ${from.padRight(8)} -> $to');
    }

    final matched = [
      for (final step in steps)
        if (step.matched) before[step.reference!],
    ];
    log('matched words: $matched');

    // Whatever the pairing turns out to be, a matched word is the only kind
    // that can carry a real measured timestamp through the edit.
    expect(steps.where((s) => s.matched), isNotEmpty,
        reason: 'if nothing matched, every timing in the line is an estimate');
  });

  test('matched words keep their exact timings, the rest are divided', () {
    final original = originalWords();
    final plan = planSentenceEdit(original: original, text: newText)!;

    expect(plan.changed, isTrue);

    log('--- resulting words ---');
    final sentenceStart = original.first.startMs;
    final sentenceEnd = original.last.endMs;
    final span = sentenceEnd - sentenceStart;

    for (final word in plan.words) {
      final at = ((word.startMs - sentenceStart) / span * 100).round();
      log('  ${word.text.padRight(8)} '
          '${word.startMs}..${word.endMs}  '
          '(${word.endMs - word.startMs}ms, starts $at% in)'
          '${word.id == null ? '  [new row]' : ''}');
    }

    // The invariant the whole feature rests on: the line still occupies exactly
    // the time it did.
    expect(plan.words.first.startMs, sentenceStart);
    expect(plan.words.last.endMs, sentenceEnd);

    // Any word that matched exactly carries its original span through
    // untouched. This is the part that is *not* an estimate.
    final byText = {for (final word in original) word.text: word};
    for (final word in plan.words) {
      final source = byText[word.text];
      if (source == null) continue;
      if (word.id != source.id) continue;
      expect(word.startMs, source.startMs,
          reason: '"${word.text}" matched, so it must keep its real start');
      expect(word.endMs, source.endMs,
          reason: '"${word.text}" matched, so it must keep its real end');
    }

    // Timings never run backwards, however the middle was divided.
    var previous = sentenceStart - 1;
    for (final word in plan.words) {
      expect(word.startMs, greaterThanOrEqualTo(previous));
      expect(word.endMs, greaterThanOrEqualTo(word.startMs));
      previous = word.startMs;
    }
  });

  test('the caption break comes from the full stop, not from the timing', () {
    final original = originalWords();
    final plan = planSentenceEdit(original: original, text: newText)!;

    final now = DateTime(2026);
    final words = [
      for (final (index, word) in plan.words.indexed)
        Word(
          id: word.id ?? 'new$index',
          createdAt: now,
          updatedAt: now,
          transcriptId: 't1',
          position: index,
          word: word.text,
          startMs: word.startMs,
          endMs: word.endMs,
          speakerId: '1',
        ),
    ];

    final cues = groupIntoCues(words);

    log('--- cues ---');
    for (final cue in cues) {
      log('  ${cue.startMs}..${cue.endMs}  "${cue.text}"');
    }

    // Two captions, broken after the word carrying the period. Nothing about
    // the split depends on where the timings landed -- `groupIntoCues` breaks
    // on `endsSentence`, which reads the last character and no clock.
    expect(cues, hasLength(2));
    expect(cues.first.text, 'look at this.');
    expect(cues.last.text, 'This is also shia-');

    // The two cues meet where the first one ends: the caption boundary *is* the
    // `endMs` of "this.", which is what makes the estimate visible on screen.
    expect(cues.first.endMs, lessThanOrEqualTo(cues.last.startMs));
  });

  group('a pure insertion at the start of a line', () {
    test('does not collapse to zero width', () {
      // `_retime` gives an insertion with no original words of its own a
      // fallback range of "end of the previous kept word" to "start of the next
      // kept word". At the very start of a sentence those can be the same
      // number, which would leave the inserted words with no duration at all.
      final original = <EditableWord>[
        (id: 'w0', text: 'visit', startMs: 1000, endMs: 1400),
        (id: 'w1', text: 'also', startMs: 1400, endMs: 1800),
      ];

      final plan = planSentenceEdit(
        original: original,
        text: 'look at visit also',
      )!;

      log('--- leading insertion ---');
      for (final word in plan.words) {
        log('  ${word.text.padRight(6)} ${word.startMs}..${word.endMs}  '
            '(${word.endMs - word.startMs}ms)');
      }

      expect(plan.words.map((w) => w.text), ['look', 'at', 'visit', 'also']);
      // The line still starts and ends where it did.
      expect(plan.words.first.startMs, 1000);
      expect(plan.words.last.endMs, 1800);

      // A caption renderer skips a cue with no duration, and an exported
      // subtitle with a zero-length line is rejected outright by some players.
      for (final word in plan.words) {
        expect(word.endMs, greaterThan(word.startMs),
            reason: '"${word.text}" has no duration');
      }

      // Exactly one kept word gave up its timing to make room -- the one the
      // insertion sits against. The other is untouched.
      expect((plan.words[3].startMs, plan.words[3].endMs), (1400, 1800));
    });

    test('the same holds at the end of a line, where there is nothing ahead',
        () {
      // The mirror case: nothing follows to borrow from, so the planner has to
      // reach backwards into the word already emitted.
      final original = <EditableWord>[
        (id: 'w0', text: 'visit', startMs: 1000, endMs: 1400),
        (id: 'w1', text: 'also', startMs: 1400, endMs: 1800),
      ];

      final plan = planSentenceEdit(
        original: original,
        text: 'visit also here now',
      )!;

      log('--- trailing insertion ---');
      for (final word in plan.words) {
        log('  ${word.text.padRight(6)} ${word.startMs}..${word.endMs}  '
            '(${word.endMs - word.startMs}ms)');
      }

      expect(plan.words.map((w) => w.text), ['visit', 'also', 'here', 'now']);
      expect(plan.words.first.startMs, 1000);
      expect(plan.words.last.endMs, 1800);

      for (final word in plan.words) {
        expect(word.endMs, greaterThan(word.startMs),
            reason: '"${word.text}" has no duration');
      }

      // "visit" is far enough from the insertion to be left alone.
      expect((plan.words[0].startMs, plan.words[0].endMs), (1000, 1400));
    });

    test('a real gap is used as-is, without disturbing either neighbour', () {
      // The borrowing only fires when there is no room. Where the engine left
      // a silence, the inserted word belongs in it and nothing else moves.
      final original = <EditableWord>[
        (id: 'w0', text: 'One', startMs: 0, endMs: 400),
        (id: 'w1', text: 'three', startMs: 900, endMs: 1200),
      ];

      final plan = planSentenceEdit(original: original, text: 'One two three')!;

      expect((plan.words[0].startMs, plan.words[0].endMs), (0, 400));
      expect((plan.words[2].startMs, plan.words[2].endMs), (900, 1200));
      expect(plan.words[1].startMs, greaterThanOrEqualTo(400));
      expect(plan.words[1].endMs, lessThanOrEqualTo(900));
    });
  });
}
