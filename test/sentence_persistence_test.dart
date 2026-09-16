import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Sentence editing against a real database.
///
/// The word count changes here, which puts `position` contiguity and the undo
/// log under pressure in a way the pure planner tests cannot reach.
void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  Future<String> seed(
    List<String> texts, {
    List<SpeakerSpan> spans = const [],
  }) async {
    final projectId = repository.newId();
    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: 'clip',
      mediaPath: '/tmp/clip.wav',
      duration: null,
      language: TranscriptionLanguage.english,
      speakerSpans: spans,
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: texts.join(' '),
        segments: [
          for (final (index, text) in texts.indexed)
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: index * 400),
              toTs: Duration(milliseconds: (index + 1) * 400),
              text: ' $text',
            ),
        ],
      ),
    );
    return (await repository.transcriptsForClip(clipId)).first.id;
  }

  Future<List<Word>> wordsOf(String id) => repository.watchWords(id).first;

  /// Positions must be a contiguous 0..n-1 run at all times: caption grouping,
  /// speaker reassignment and the undo log all address words by position.
  Future<void> expectContiguous(String transcriptId) async {
    final live = await wordsOf(transcriptId);
    expect(
      live.map((w) => w.position),
      List.generate(live.length, (i) => i),
      reason: 'positions must stay a contiguous run after a splice',
    );
  }

  group('one word becomes two', () {
    test('splices in the extra word and keeps the sentence span', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);
      final before = await wordsOf(id);

      final applied = await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'It was praying beads.',
      );
      expect(applied, isTrue);

      final after = await wordsOf(id);
      expect(after.map((w) => w.word), ['It', 'was', 'praying', 'beads.']);
      await expectContiguous(id);

      // The sentence occupies exactly the time it did before.
      expect(after.first.startMs, before.first.startMs);
      expect(after.last.endMs, before.last.endMs);
      // And the two words nobody touched are untouched, ids included.
      expect(after[0].id, before[0].id);
      expect(after[1].id, before[1].id);
      expect(after[1].endMs, before[1].endMs);
    });

    test('undo restores the original words and count', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);
      final before = await wordsOf(id);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'It was praying beads.',
      );
      await repository.undo(id);

      final restored = await wordsOf(id);
      expect(restored.map((w) => w.word), ['It', 'was', 'brainbeats.']);
      expect(restored.map((w) => w.id), before.map((w) => w.id));
      expect(restored.map((w) => w.startMs), before.map((w) => w.startMs));
      expect(restored.map((w) => w.endMs), before.map((w) => w.endMs));
      await expectContiguous(id);
    });

    test('redo re-applies it without stranding duplicate rows', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'It was praying beads.',
      );
      final firstPass = await wordsOf(id);

      await repository.undo(id);
      await repository.redo(id);

      final secondPass = await wordsOf(id);
      expect(secondPass.map((w) => w.word), ['It', 'was', 'praying', 'beads.']);
      // Same rows, not fresh ones: the event records the id each new word was
      // given, so a redo revives it rather than inserting a twin.
      expect(secondPass.map((w) => w.id), firstPass.map((w) => w.id));
      await expectContiguous(id);

      final everyRow = await database.select(database.words).get();
      expect(everyRow, hasLength(4),
          reason: 'a redo must not leave an orphaned soft-deleted duplicate');
    });
  });

  group('word scope: the range is one word', () {
    // What the editor's Word mode does -- `replaceSentence` with
    // `fromPosition == toPosition`. No special case in the code; the point of
    // these tests is that none is needed, and that the containment is real.

    test('one word becomes two inside that word\'s own span', () async {
      final id = await seed(['It', 'was', 'brainbeats', 'again.']);
      final before = await wordsOf(id);
      final target = before[2];

      final applied = await repository.replaceSentence(
        transcriptId: id,
        fromPosition: target.position,
        toPosition: target.position,
        text: 'praying beads',
      );
      expect(applied, isTrue);

      final after = await wordsOf(id);
      expect(after.map((w) => w.word),
          ['It', 'was', 'praying', 'beads', 'again.']);
      await expectContiguous(id);

      // The pair occupies exactly the box the single word had, and nothing
      // outside it moved by a millisecond.
      expect(after[2].startMs, target.startMs);
      expect(after[3].endMs, target.endMs);
    });

    test('every neighbouring word keeps its exact timing', () async {
      final id = await seed(['It', 'was', 'brainbeats', 'again.']);
      final before = await wordsOf(id);
      final target = before[2];

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: target.position,
        toPosition: target.position,
        text: 'praying beads',
      );

      final after = await wordsOf(id);
      // Words before the edit.
      expect((after[0].startMs, after[0].endMs),
          (before[0].startMs, before[0].endMs));
      expect((after[1].startMs, after[1].endMs),
          (before[1].startMs, before[1].endMs));
      // And after it -- the one that shifted position but not time.
      expect((after[4].startMs, after[4].endMs),
          (before[3].startMs, before[3].endMs));
      expect(after[4].id, before[3].id);
    });

    test('the split lands strictly inside the word, never on its edges',
        () async {
      final id = await seed(['brainbeats']);
      final target = (await wordsOf(id)).single;

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: target.position,
        toPosition: target.position,
        text: 'praying beads',
      );

      final after = await wordsOf(id);
      expect(after, hasLength(2));
      // A boundary at either edge would leave one of the two with no duration,
      // which a caption renderer would skip.
      expect(after.first.endMs, greaterThan(target.startMs));
      expect(after.first.endMs, lessThan(target.endMs));
      expect(after.first.endMs, after.last.startMs);
    });

    test('undo returns the single word with its original span', () async {
      final id = await seed(['It', 'was', 'brainbeats', 'again.']);
      final before = await wordsOf(id);
      final target = before[2];

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: target.position,
        toPosition: target.position,
        text: 'praying beads',
      );
      await repository.undo(id);

      final restored = await wordsOf(id);
      expect(restored.map((w) => w.word), before.map((w) => w.word));
      expect(restored.map((w) => w.id), before.map((w) => w.id));
      expect(restored[2].startMs, target.startMs);
      expect(restored[2].endMs, target.endMs);
      await expectContiguous(id);
    });

    test('one changed word gives the same result in either scope', () async {
      // Worth pinning, because it is not obvious and it is the common case.
      // `planSentenceEdit` aligns before retiming, so a line edit that changes
      // exactly one word produces a changed run of exactly one word -- the same
      // run word scope would have forced. The two scopes only diverge when the
      // alignment cannot match, i.e. when several words are rewritten at once.
      final texts = ['It', 'was', 'brainbeats', 'again', 'today.'];

      final byWordId = await seed(texts);
      final byLineId = await seed(texts);

      await repository.replaceSentence(
        transcriptId: byWordId,
        fromPosition: 2,
        toPosition: 2,
        text: 'praying beads',
      );
      await repository.replaceSentence(
        transcriptId: byLineId,
        fromPosition: 0,
        toPosition: 4,
        text: 'It was praying beads again today.',
      );

      final byWord = await wordsOf(byWordId);
      final byLine = await wordsOf(byLineId);

      expect(byWord.map((w) => w.word), byLine.map((w) => w.word));
      expect(byWord.map((w) => w.startMs), byLine.map((w) => w.startMs));
      expect(byWord.map((w) => w.endMs), byLine.map((w) => w.endMs));
    });

    test('word scope bounds a rewrite that line scope would spread', () async {
      // Where the choice earns its place: the user rewrites enough that the
      // alignment matches nothing. Line scope then re-divides the whole line;
      // word scope cannot touch more than the one word, whatever is typed.
      final texts = ['It', 'was', 'brainbeats', 'again', 'today.'];

      final byWordId = await seed(texts);
      final byLineId = await seed(texts);
      final original = await wordsOf(byWordId);

      await repository.replaceSentence(
        transcriptId: byWordId,
        fromPosition: 2,
        toPosition: 2,
        text: 'utterly different words here',
      );
      await repository.replaceSentence(
        transcriptId: byLineId,
        fromPosition: 0,
        toPosition: 4,
        text: 'Completely rewritten from scratch entirely.',
      );

      final byWord = await wordsOf(byWordId);
      final byLine = await wordsOf(byLineId);

      // Word scope: everything outside the one word is byte-identical.
      expect(byWord[0].startMs, original[0].startMs);
      expect(byWord[0].endMs, original[0].endMs);
      expect(byWord[1].endMs, original[1].endMs);
      expect(byWord.last.startMs, original.last.startMs);
      // And the replacement is confined to the box it replaced.
      final inserted = byWord.where((w) => w.word == 'utterly').single;
      expect(inserted.startMs, original[2].startMs);

      // Line scope: only the outer span of the line is preserved. Every
      // internal boundary has been re-derived.
      expect(byLine.first.startMs, original.first.startMs);
      expect(byLine.last.endMs, original.last.endMs);
      expect(byLine[0].endMs, isNot(original[0].endMs));
    });
  });

  group('the rest of the transcript moves with it', () {
    test('words after the edited sentence keep their order and timings',
        () async {
      final id = await seed(['One.', 'brainbeats.', 'Three.', 'Four.']);
      final before = await wordsOf(id);
      final tailIds = before.sublist(2).map((w) => w.id).toList();

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 1,
        text: 'praying beads.',
      );

      final after = await wordsOf(id);
      expect(after.map((w) => w.word),
          ['One.', 'praying', 'beads.', 'Three.', 'Four.']);
      await expectContiguous(id);

      // The tail shifted position but is otherwise identical.
      expect(after.sublist(3).map((w) => w.id), tailIds);
      expect(after[3].startMs, before[2].startMs);
      expect(after[4].endMs, before[3].endMs);
    });

    test('a shrinking edit closes the gap it leaves', () async {
      final id = await seed(['One.', 'two', 'three', 'four.', 'Five.']);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 3,
        text: 'twothreefour.',
      );

      final after = await wordsOf(id);
      expect(after.map((w) => w.word), ['One.', 'twothreefour.', 'Five.']);
      await expectContiguous(id);
    });

    test('undoing a shrink puts the positions back', () async {
      final id = await seed(['One.', 'two', 'three', 'four.', 'Five.']);
      final before = await wordsOf(id);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 3,
        text: 'twothreefour.',
      );
      await repository.undo(id);

      final restored = await wordsOf(id);
      expect(restored.map((w) => w.word), before.map((w) => w.word));
      expect(restored.map((w) => w.id), before.map((w) => w.id));
      await expectContiguous(id);
    });
  });

  group('speakers and history', () {
    test('new words inherit the speaker of the run they joined', () async {
      final id = await seed(
        ['That', 'is', 'brainbeats.'],
        spans: const [SpeakerSpan(startMs: 0, endMs: 1200, speaker: 1)],
      );
      final before = await wordsOf(id);
      expect(before.first.speakerId, isNotNull);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'That is praying beads.',
      );

      final after = await wordsOf(id);
      expect(after.map((w) => w.speakerId).toSet(), {before.first.speakerId});
    });

    test('a sentence edit and a word edit undo in the right order', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);

      await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'It was praying beads.',
      );
      // Then correct one of the words the sentence edit created.
      final created = (await wordsOf(id)).last;
      await repository.updateWordText(created.id, 'beads!');
      expect((await wordsOf(id)).last.word, 'beads!');

      await repository.undo(id);
      expect((await wordsOf(id)).last.word, 'beads.');

      await repository.undo(id);
      expect(
        (await wordsOf(id)).map((w) => w.word),
        ['It', 'was', 'brainbeats.'],
      );
      await expectContiguous(id);
    });

    test('retyping the same text records nothing', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);

      final applied = await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: 'It was brainbeats.',
      );

      expect(applied, isFalse);
      expect(await repository.watchEditHistory(id).first,
          (canUndo: false, canRedo: false));
    });

    test('emptying the box changes nothing', () async {
      final id = await seed(['It', 'was', 'brainbeats.']);

      final applied = await repository.replaceSentence(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 2,
        text: '   ',
      );

      expect(applied, isFalse);
      expect(await wordsOf(id), hasLength(3));
    });
  });
}
