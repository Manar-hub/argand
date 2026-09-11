import 'package:argand/core/database/database.dart';
import 'package:argand/core/transcript/speaker_turns.dart';
import 'package:flutter_test/flutter_test.dart';

final _epoch = DateTime.utc(2026);
var _seq = 0;

/// Builds a word with only the fields turn grouping cares about.
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

void main() {
  group('groupIntoSpeakerTurns', () {
    test('an empty transcript yields no turns', () {
      expect(groupIntoSpeakerTurns(const []), isEmpty);
    });

    test('a transcript with no diarization yields one unlabelled turn', () {
      // The property the rendering path depends on: undiarized transcripts go
      // through the same code as diarized ones rather than branching.
      final turns = groupIntoSpeakerTurns([
        w('No', 0, 200),
        w('speakers', 200, 500),
        w('here.', 500, 900),
      ]);

      expect(turns, hasLength(1));
      expect(turns.single.speaker, isNull);
      expect(turns.single.wordCount, 3);
    });

    test('consecutive words with one speaker stay in one turn', () {
      final turns = groupIntoSpeakerTurns([
        w('All', 0, 200, speaker: '0'),
        w('mine.', 200, 500, speaker: '0'),
      ]);

      expect(turns, hasLength(1));
      expect(turns.single.speaker, 0);
    });

    test('splits wherever the speaker changes, and back again', () {
      final turns = groupIntoSpeakerTurns([
        w('Hello', 0, 400, speaker: '0'),
        w('there.', 400, 800, speaker: '0'),
        w('Hi.', 900, 1200, speaker: '1'),
        w('Again.', 1300, 1700, speaker: '0'),
      ]);

      expect(turns.map((t) => t.speaker), [0, 1, 0]);
      expect(turns.map((t) => t.wordCount), [2, 1, 1]);
    });

    test('startIndex tracks the flat word list across turns', () {
      // This is what keeps the playback highlight correct: the index is into
      // the whole transcript, not into the turn.
      final turns = groupIntoSpeakerTurns([
        w('a', 0, 100, speaker: '0'),
        w('b', 100, 200, speaker: '0'),
        w('c', 200, 300, speaker: '1'),
        w('d', 300, 400, speaker: '1'),
        w('e', 400, 500, speaker: '0'),
      ]);

      expect(turns.map((t) => t.startIndex), [0, 2, 4]);
    });

    test('an unparseable speaker id separates turns instead of merging', () {
      // int.tryParse returns null for both a missing id and a malformed one.
      // Grouping compares the raw string, so a malformed id cannot silently
      // join a neighbouring undiarized run.
      final turns = groupIntoSpeakerTurns([
        w('one', 0, 100, speaker: '0'),
        w('two', 100, 200, speaker: 'oops'),
        w('three', 200, 300),
      ]);

      expect(turns, hasLength(3));
      expect(turns.map((t) => t.speaker), [0, null, null]);
    });

    test('endMs is the maximum, not the last word, when timestamps invert', () {
      // DTW occasionally places one word's end before an earlier word's.
      // Taking words.last.endMs would report a turn that ends before it starts.
      final turns = groupIntoSpeakerTurns([
        w('long', 0, 5000, speaker: '0'),
        w('short', 100, 300, speaker: '0'),
      ]);

      expect(turns.single.endMs, 5000);
      expect(turns.single.durationMs, 5000);
    });

    test('durationMs never goes negative', () {
      final turns = groupIntoSpeakerTurns([
        w('backwards', 900, 400, speaker: '0'),
      ]);

      expect(turns.single.durationMs, 0);
    });

    test('the word list is unmodifiable', () {
      // The private _Turn this replaces exposed a growable list that the
      // grouper itself appended to. A shared derived value must not be
      // mutable by its consumers.
      final turns = groupIntoSpeakerTurns([w('only', 0, 100, speaker: '0')]);

      expect(
        () => turns.single.words.add(w('sneaky', 100, 200)),
        throwsUnsupportedError,
      );
    });
  });
}
