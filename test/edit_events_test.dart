import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/transcript/edit_event.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  /// Imports [texts] as one word per segment, 400ms apart, and returns the
  /// transcript id. Mirrors what the engine actually hands `saveImport`.
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

  Future<List<Word>> wordsOf(String transcriptId) =>
      repository.watchWords(transcriptId).first;

  Future<int> liveEventCount(String transcriptId) async {
    final rows = await (database.select(database.editEvents)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) & t.deletedAt.isNull()))
        .get();
    return rows.length;
  }

  group('payload codec', () {
    test('a word edit round-trips through storage', () {
      const original =
          WordTextEdit(wordId: 'w1', before: 'Appie', after: 'API');
      final restored = EditEventPayload.decode(
        original.kind.code,
        original.encode(),
      );

      expect(restored, isA<WordTextEdit>());
      final decoded = restored! as WordTextEdit;
      expect(decoded.wordId, 'w1');
      expect(decoded.before, 'Appie');
      expect(decoded.after, 'API');
    });

    test('a speaker edit round-trips its nulls', () {
      // The case a scalar `before` would silently flatten: an undiarized word
      // genuinely has no speaker, and undo has to restore that absence rather
      // than substituting some default.
      const original = SpeakerEdit(
        fromPosition: 0,
        toPosition: 1,
        after: '1',
        before: {0: null, 1: '0'},
      );
      final decoded = EditEventPayload.decode(
        original.kind.code,
        original.encode(),
      )! as SpeakerEdit;

      expect(decoded.before, {0: null, 1: '0'});
      expect(decoded.after, '1');
    });

    test('an unreadable payload decodes to null rather than throwing', () {
      // Each of these is a row a future build, or a corruption, could leave
      // behind. None of them may be allowed to crash the editor.
      expect(EditEventPayload.decode('wordText', 'not json'), isNull);
      expect(EditEventPayload.decode('clipTrimmed', '{}'), isNull);
      expect(EditEventPayload.decode('wordText', '{"wordId":1}'), isNull);
      expect(EditEventPayload.decode('speaker', '{"from":0,"to":1}'), isNull);
    });
  });

  group('undo and redo', () {
    test('undo restores the previous text, redo puts the correction back',
        () async {
      final transcriptId = await seed(['Appie']);
      final word = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(word.id, 'API');
      expect((await wordsOf(transcriptId)).single.word, 'API');

      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'Appie');

      await repository.redo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'API');
    });

    test('undo never moves a timestamp', () async {
      final transcriptId = await seed(['Appie']);
      final before = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(before.id, 'API');
      await repository.undo(transcriptId);

      final after = (await wordsOf(transcriptId)).single;
      // The same guarantee the forward edit makes. Restoring a timestamp that
      // was never changed would desynchronise tap-to-seek and every caption
      // boundary from the audio.
      expect(after.startMs, before.startMs);
      expect(after.endMs, before.endMs);
      expect(after.position, before.position);
    });

    test('several undos unwind in reverse, then redos retrace forward',
        () async {
      final transcriptId = await seed(['one']);
      final word = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(word.id, 'two');
      await repository.updateWordText(word.id, 'three');

      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'two');
      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'one');

      await repository.redo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'two');
      await repository.redo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'three');
    });

    test('undoing a speaker reassignment restores each word, nulls included',
        () async {
      // No spans, so every word imports with a null speaker.
      final transcriptId = await seed(['That', 'is', 'right']);

      await repository.reassignSpeaker(
        transcriptId: transcriptId,
        fromPosition: 0,
        toPosition: 2,
        speaker: 1,
      );
      expect(
        (await wordsOf(transcriptId)).map((w) => w.speakerId),
        ['1', '1', '1'],
      );

      await repository.undo(transcriptId);
      expect(
        (await wordsOf(transcriptId)).map((w) => w.speakerId),
        [null, null, null],
      );
    });

    test('undoing a reassignment over a split turn restores both speakers',
        () async {
      // The real correction this feature exists for: one sentence rendered
      // across two speakers, put onto one, then undone.
      final transcriptId = await seed(
        ['That', 'is', 'right', 'and', 'so', 'it', 'was'],
        spans: const [
          SpeakerSpan(startMs: 0, endMs: 1200, speaker: 0),
          SpeakerSpan(startMs: 1200, endMs: 2800, speaker: 1),
        ],
      );
      final before = (await wordsOf(transcriptId)).map((w) => w.speakerId);
      expect(before.toSet().length, greaterThan(1),
          reason: 'the fixture must actually be split to test the restore');

      await repository.reassignSpeaker(
        transcriptId: transcriptId,
        fromPosition: 0,
        toPosition: 6,
        speaker: 0,
      );
      await repository.undo(transcriptId);

      expect((await wordsOf(transcriptId)).map((w) => w.speakerId), before);
    });

    test('editing after an undo discards the redo branch', () async {
      final transcriptId = await seed(['one']);
      final word = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(word.id, 'two');
      await repository.undo(transcriptId);
      expect(await repository.watchEditHistory(transcriptId).first,
          (canUndo: false, canRedo: true));

      await repository.updateWordText(word.id, 'three');

      // Linear undo: the abandoned branch is gone rather than reachable behind
      // the new edit, which is what every editor does and what keeps the log
      // a list instead of a tree.
      expect(await repository.watchEditHistory(transcriptId).first,
          (canUndo: true, canRedo: false));

      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'one');
    });

    test('a no-op correction records nothing', () async {
      final transcriptId = await seed(['same']);
      final word = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(word.id, 'same');
      // Trimming makes this identical too -- the editor pads nothing, but a
      // stray space must not buy a history slot that undoes nothing visible.
      await repository.updateWordText(word.id, '  same  ');

      expect(await liveEventCount(transcriptId), 0);
    });

    test('a reassignment to the speaker already there records nothing',
        () async {
      final transcriptId = await seed(
        ['a', 'b'],
        spans: const [SpeakerSpan(startMs: 0, endMs: 800, speaker: 0)],
      );

      await repository.reassignSpeaker(
        transcriptId: transcriptId,
        fromPosition: 0,
        toPosition: 1,
        speaker: 0,
      );

      expect(await liveEventCount(transcriptId), 0);
    });

    test('undo and redo on an empty history do nothing', () async {
      final transcriptId = await seed(['one']);

      await repository.undo(transcriptId);
      await repository.redo(transcriptId);

      expect((await wordsOf(transcriptId)).single.word, 'one');
      expect(await repository.watchEditHistory(transcriptId).first,
          (canUndo: false, canRedo: false));
    });

    test('one transcript\'s history cannot reach another\'s', () async {
      final first = await seed(['alpha']);
      final second = await seed(['beta']);
      final word = (await wordsOf(first)).single;

      await repository.updateWordText(word.id, 'gamma');

      // Undo aimed at the untouched transcript must be inert, not steal the
      // other's event -- the queries are all scoped by transcript id.
      await repository.undo(second);
      expect((await wordsOf(first)).single.word, 'gamma');
      expect(await repository.watchEditHistory(second).first,
          (canUndo: false, canRedo: false));
    });

    test('an unreadable event is dropped instead of wedging undo', () async {
      final transcriptId = await seed(['one']);
      final word = (await wordsOf(transcriptId)).single;

      await repository.updateWordText(word.id, 'two');
      await repository.updateWordText(word.id, 'three');

      // Corrupt the newest event, as a partial write or a downgrade might.
      final newest = (await (database.select(database.editEvents)
                ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
                ..limit(1))
              .get())
          .single;
      await (database.update(database.editEvents)
            ..where((t) => t.id.equals(newest.id)))
          .write(EditEventsCompanion(payload: const Value('{{{')));

      // First undo consumes the bad row without applying anything...
      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'three');

      // ...and the history behind it still works.
      await repository.undo(transcriptId);
      expect((await wordsOf(transcriptId)).single.word, 'one');
    });
  });

  group('bounded window', () {
    test('the log prunes to the limit and stays undoable to its edge',
        () async {
      final transcriptId = await seed(['w0']);
      final word = (await wordsOf(transcriptId)).single;

      const overshoot = 5;
      for (var i = 1; i <= AppDatabase.editHistoryLimit + overshoot; i++) {
        await repository.updateWordText(word.id, 'w$i');
      }

      expect(await liveEventCount(transcriptId), AppDatabase.editHistoryLimit);

      // Undoing the whole window walks back to the oldest edit still kept --
      // not to the original text, which is exactly what "bounded" costs.
      for (var i = 0; i < AppDatabase.editHistoryLimit; i++) {
        await repository.undo(transcriptId);
      }
      expect((await wordsOf(transcriptId)).single.word, 'w$overshoot');
      expect(await repository.watchEditHistory(transcriptId).first,
          (canUndo: false, canRedo: true));
    });
  });
}
