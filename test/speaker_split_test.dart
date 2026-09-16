import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/transcript/speaker_names.dart';
import 'package:argand/core/transcript/speaker_turns.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Splitting a turn, which reassignment by turn could never do.
///
/// The repository already accepted an arbitrary position range; nothing in the
/// UI could express one. These pin the behaviour the Speakers scope depends on,
/// and in particular that **undo restores both original speakers** — which only
/// works because `SpeakerEdit` records its before-state per position rather
/// than as one value.
void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  /// Six words, all given to speaker 0 by diarization.
  Future<String> seed({List<SpeakerSpan>? spans}) async {
    final projectId = repository.newId();
    const texts = ['One', 'two', 'three', 'four', 'five', 'six.'];

    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: 'clip',
      mediaPath: '/tmp/clip.wav',
      duration: null,
      language: TranscriptionLanguage.english,
      speakerSpans:
          spans ?? const [SpeakerSpan(startMs: 0, endMs: 2400, speaker: 0)],
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

  group('splitting a turn', () {
    test('a middle range moves and the turn becomes three', () async {
      final id = await seed();
      expect(groupIntoSpeakerTurns(await wordsOf(id)), hasLength(1));

      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 2,
        toPosition: 3,
        speaker: 1,
      );

      final turns = groupIntoSpeakerTurns(await wordsOf(id));
      expect(turns, hasLength(3));
      expect(turns.map((t) => t.speaker), [0, 1, 0]);
      expect(turns[1].words.map((w) => w.word), ['three', 'four']);
    });

    test('undo restores both speakers, not just one', () async {
      // The reason `SpeakerEdit.before` is a per-position map. A scalar would
      // put the whole range back on one speaker and quietly destroy the split
      // that was already there.
      final id = await seed(
        spans: const [
          SpeakerSpan(startMs: 0, endMs: 1200, speaker: 0),
          SpeakerSpan(startMs: 1200, endMs: 2400, speaker: 1),
        ],
      );
      final before = (await wordsOf(id)).map((w) => w.speakerId).toList();
      expect(before.toSet().length, greaterThan(1),
          reason: 'the fixture must span two speakers for this to mean anything');

      // A range deliberately crossing the existing boundary.
      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 4,
        speaker: 2,
      );
      expect(
        (await wordsOf(id)).sublist(1, 5).map((w) => w.speakerId),
        ['2', '2', '2', '2'],
      );

      await repository.undo(id);
      expect((await wordsOf(id)).map((w) => w.speakerId), before);
    });

    test('a single word can be moved on its own', () async {
      final id = await seed();

      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 3,
        toPosition: 3,
        speaker: 1,
      );

      final words = await wordsOf(id);
      expect(words[3].speakerId, '1');
      expect(words[2].speakerId, '0');
      expect(words[4].speakerId, '0');
    });

    test('a speaker the transcript never had can be assigned', () async {
      // What makes splitting possible when diarization merged two people
      // entirely: the second speaker has no words yet.
      final id = await seed();

      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 0,
        toPosition: 1,
        speaker: 4,
      );

      final turns = groupIntoSpeakerTurns(await wordsOf(id));
      expect(turns.first.speaker, 4);
      expect(turns.map((t) => t.speaker), [4, 0]);
    });

    test('the whole range is one undo step', () async {
      final id = await seed();

      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 4,
        speaker: 1,
      );

      await repository.undo(id);
      expect(
        (await wordsOf(id)).map((w) => w.speakerId).toSet(),
        {'0'},
        reason: 'one undo must put the entire range back, not one word of it',
      );
      expect(await repository.watchEditHistory(id).first,
          (canUndo: false, canRedo: true));
    });

    test('reassigning to the speaker already there records nothing', () async {
      final id = await seed();

      await repository.reassignSpeaker(
        transcriptId: id,
        fromPosition: 1,
        toPosition: 3,
        speaker: 0,
      );

      expect(await repository.watchEditHistory(id).first,
          (canUndo: false, canRedo: false));
    });
  });

  group('speaker names', () {
    test('round-trip through the transcript row', () async {
      final id = await seed();

      await repository.renameSpeaker(
        transcriptId: id,
        speaker: 0,
        name: 'Ana',
      );

      final stored = SpeakerNames.decode(
        (await database.findTranscript(id))!.speakerNames,
      );
      expect(stored[0], 'Ana');
    });

    test('an untouched transcript stores nothing at all', () async {
      final id = await seed();
      expect((await database.findTranscript(id))!.speakerNames, isNull);
    });

    test('clearing the last name returns the column to null', () async {
      final id = await seed();

      await repository.renameSpeaker(transcriptId: id, speaker: 0, name: 'Ana');
      await repository.renameSpeaker(transcriptId: id, speaker: 0, name: '');

      expect((await database.findTranscript(id))!.speakerNames, isNull);
    });

    test('naming one speaker leaves the others on their default', () async {
      final id = await seed();

      await repository.renameSpeaker(transcriptId: id, speaker: 1, name: 'Bo');

      final stored = SpeakerNames.decode(
        (await database.findTranscript(id))!.speakerNames,
      );
      expect(stored[1], 'Bo');
      expect(stored.labelFor(0, defaultLabel: 'Speaker 1'), 'Speaker 1');
    });

    test('renaming a missing transcript is a no-op, not a crash', () async {
      await repository.renameSpeaker(
        transcriptId: 'nope',
        speaker: 0,
        name: 'Ana',
      );
    });
  });
}
