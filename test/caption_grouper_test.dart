import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/caption_grouper.dart';
import 'package:argand/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

final _epoch = DateTime.utc(2026);
var _seq = 0;

/// Builds a word with only the fields grouping cares about.
Word w(String text, int startMs, int endMs, {String? speaker}) {
  return Word(
    id: 'w${_seq++}',
    createdAt: _epoch,
    updatedAt: _epoch,
    transcriptId: 't',
    position: _seq,
    word: text,
    startMs: startMs,
    endMs: endMs,
    speakerId: speaker,
  );
}

/// Lays words out end to end, [gapMs] apart, so tests state timing once.
List<Word> run(List<String> texts, {int startMs = 0, int each = 300, int gapMs = 0, String? speaker}) {
  final words = <Word>[];
  var t = startMs;
  for (final text in texts) {
    words.add(w(text, t, t + each, speaker: speaker));
    t += each + gapMs;
  }
  return words;
}

void main() {
  group('groupIntoCues', () {
    test('an empty transcript produces no cues', () {
      expect(groupIntoCues(const []), isEmpty);
    });

    test('a short sentence stays one cue', () {
      final cues = groupIntoCues(run(['Hello', 'there', 'world.']));

      expect(cues, hasLength(1));
      expect(cues.single.text, 'Hello there world.');
      expect(cues.single.startMs, 0);
      expect(cues.single.endMs, 900);
    });

    test('breaks after a sentence ends', () {
      final cues = groupIntoCues(run(['One.', 'Two.', 'Three.']));

      expect(cues.map((c) => c.text), ['One.', 'Two.', 'Three.']);
    });

    test('recognises sentence ends behind a closing quote', () {
      final cues = groupIntoCues(run(['He', 'said."', 'Then', 'left.']));

      expect(cues.map((c) => c.text), ['He said."', 'Then left.']);
    });

    test('a speaker change always breaks, mid-sentence included', () {
      final cues = groupIntoCues([
        ...run(['I', 'was'], speaker: '0'),
        ...run(['going', 'to'], startMs: 600, speaker: '1'),
      ]);

      expect(cues, hasLength(2));
      expect(cues[0].speaker, 0);
      expect(cues[0].text, 'I was');
      expect(cues[1].speaker, 1);
      expect(cues[1].text, 'going to');
    });

    test('a comma does not break a cue that is still too short', () {
      // "Yeah," on its own would flicker past unreadably.
      final cues = groupIntoCues(run(['Yeah,', 'and', 'then', 'we', 'left.']));

      expect(cues, hasLength(1));
      expect(cues.single.text, 'Yeah, and then we left.');
    });

    test('a comma does break once the cue can stand alone', () {
      final cues = groupIntoCues(
        run(['Something', 'reasonably', 'long', 'happening', 'here,', 'then', 'more.']),
      );

      expect(cues, hasLength(2));
      expect(cues[0].text, 'Something reasonably long happening here,');
      expect(cues[1].text, 'then more.');
    });

    test('a long silence breaks the cue', () {
      final cues = groupIntoCues([
        ...run(['before', 'the', 'pause']),
        ...run(['after', 'it'], startMs: 900 + 1200),
      ]);

      expect(cues, hasLength(2));
      expect(cues[0].text, 'before the pause');
      expect(cues[1].text, 'after it');
    });

    test('a short pause does not break the cue', () {
      final cues = groupIntoCues(run(['a', 'b', 'c'], gapMs: 100));

      expect(cues, hasLength(1));
    });

    test('length is the backstop when punctuation never arrives', () {
      // Unpunctuated speech still has to be split or it becomes one unreadable
      // caption spanning the whole file.
      final cues = groupIntoCues(run(List.filled(60, 'word')));

      expect(cues.length, greaterThan(1));
      for (final cue in cues) {
        expect(cue.text.length, lessThanOrEqualTo(84));
      }
    });

    test('duration is a backstop independent of length', () {
      // Few characters, but drawn out well past the limit.
      final cues = groupIntoCues(run(['a', 'b', 'c', 'd'], each: 2500));

      expect(cues.length, greaterThan(1));
      for (final cue in cues) {
        expect(cue.durationMs, lessThanOrEqualTo(6000));
      }
    });

    test('a single word longer than the limit still becomes a cue', () {
      final cues = groupIntoCues([w('x' * 200, 0, 500)]);

      expect(cues, hasLength(1));
      expect(cues.single.text.length, 200);
    });

    test('every word ends up in exactly one cue, in order', () {
      final words = run(
        ['One.', 'Then', 'a', 'longer', 'stretch,', 'and', 'more', 'after', 'it.'],
      );

      final cues = groupIntoCues(words);
      final regrouped = [for (final cue in cues) ...cue.words.map((x) => x.id)];

      expect(regrouped, words.map((x) => x.id).toList());
    });

    test('cue timing spans its words even when one end time runs backwards', () {
      // DTW timestamps occasionally place a word's end before an earlier one's.
      final cues = groupIntoCues([
        w('a', 0, 900),
        w('b', 300, 600),
      ]);

      expect(cues.single.startMs, 0);
      expect(cues.single.endMs, 900, reason: 'A cue must not end before it starts');
      expect(cues.single.durationMs, greaterThan(0));
    });

    test('speaker is null when the transcript was never diarized', () {
      expect(groupIntoCues(run(['a', 'b'])).single.speaker, isNull);
    });
  });

  group('cueAt', () {
    final cues = groupIntoCues([
      ...run(['One.']),
      ...run(['Two.'], startMs: 1000),
    ]);

    test('finds the cue covering a position', () {
      expect(cueAt(cues, 100)?.text, 'One.');
      expect(cueAt(cues, 1100)?.text, 'Two.');
    });

    test('returns null in the gap between cues and before the first', () {
      expect(cueAt(cues, 500), isNull);
      expect(cueAt(cues, 900), isNull);
    });

    test('is exclusive at the end so adjacent cues cannot both match', () {
      expect(cueAt(cues, 300), isNull);
      expect(cueAt(cues, 299)?.text, 'One.');
    });

    test('returns null past the last cue', () {
      expect(cueAt(cues, 99999), isNull);
    });

    test('an empty cue list is not an error', () {
      expect(cueAt(const <CaptionCue>[], 0), isNull);
    });
  });
}
