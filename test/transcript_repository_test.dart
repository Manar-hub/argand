import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  // The real provider opens a file in the app documents directory, which does
  // not exist under `flutter test`, so every test swaps in an in-memory
  // database.
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));

  group('TranscriptRepository', () {
    test('saveImport stores words in engine order with their timings', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = repository.newId();

      final clipId = repository.newId();
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: 'interview',
        mediaPath: '/tmp/interview.mp4',
        duration: const Duration(seconds: 3),
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        result: const WhisperTranscribeResponse(
          type: 'transcribe',
          text: ' Hello there world',
          // `splitOnWord: true` returns one word per segment, each padded with
          // a leading space -- the shape this test pins down.
          segments: [
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 120),
              toTs: Duration(milliseconds: 400),
              text: ' Hello',
            ),
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 400),
              toTs: Duration(milliseconds: 700),
              text: ' there',
            ),
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 700),
              toTs: Duration(milliseconds: 1100),
              text: ' world',
            ),
          ],
        ),
      );

      final transcript = (await repository.transcriptsForClip(clipId)).firstOrNull;
      expect(transcript, isNotNull);
      expect(transcript!.fullText, 'Hello there world');

      final words = await repository.watchWords(transcript.id).first;
      expect(words.map((w) => w.word), ['Hello', 'there', 'world']);
      expect(words.map((w) => w.position), [0, 1, 2]);
      expect(words.first.startMs, 120);
      expect(words.last.endMs, 1100);
    });

    test('saveImport drops whitespace-only segments', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = repository.newId();

      final clipId = repository.newId();
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: 'pauses',
        mediaPath: '/tmp/pauses.wav',
        duration: null,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        result: const WhisperTranscribeResponse(
          type: 'transcribe',
          text: ' you',
          segments: [
            WhisperTranscribeSegment(
              fromTs: Duration.zero,
              toTs: Duration(milliseconds: 200),
              text: '  ',
            ),
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 200),
              toTs: Duration(milliseconds: 500),
              text: ' you',
            ),
          ],
        ),
      );

      final transcript = (await repository.transcriptsForClip(clipId)).firstOrNull;
      final words = await repository.watchWords(transcript!.id).first;

      // The blank segment must not survive as an empty, invisible word, and
      // positions must stay contiguous from zero after it is removed.
      expect(words.map((w) => w.word), ['you']);
      expect(words.single.position, 0);
    });

    test('deleteProject hides the project without removing the row', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = repository.newId();

      final clipId = repository.newId();
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: 'clip',
        mediaPath: '/tmp/clip.m4a',
        duration: null,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        result: const WhisperTranscribeResponse(
          type: 'transcribe',
          text: 'hi',
          segments: [],
        ),
      );

      await repository.deleteProject(projectId);

      expect(await repository.findProject(projectId), isNull);
      // The row itself survives -- CLAUDE.md 5 forbids hard deletes.
      expect(await database.select(database.projects).get(), hasLength(1));
    });

    test('correcting a word changes its text and nothing else', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = repository.newId();

      final clipId = repository.newId();
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: 'edit',
        mediaPath: '/tmp/edit.wav',
        duration: null,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        result: const WhisperTranscribeResponse(
          type: 'transcribe',
          text: ' Appie',
          segments: [
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 2390),
              toTs: Duration(milliseconds: 2780),
              text: ' Appie',
            ),
          ],
        ),
      );

      final transcript = (await repository.transcriptsForClip(clipId)).firstOrNull;
      final before = (await repository.watchWords(transcript!.id).first).single;

      await repository.updateWordText(before.id, 'API');

      final after = (await repository.watchWords(transcript.id).first).single;
      expect(after.word, 'API');
      // The point of the whole feature: a correction fixes what was heard, not
      // when it was said. Moving these would desynchronise tap-to-seek, the
      // playback highlight and every caption boundary from the audio.
      expect(after.startMs, before.startMs);
      expect(after.endMs, before.endMs);
      expect(after.position, before.position);
    });

    test('reassigning a turn rewrites exactly that range', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = repository.newId();

      final clipId = repository.newId();
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: 'turns',
        mediaPath: '/tmp/turns.wav',
        duration: null,
        language: TranscriptionLanguage.english,
        speakerSpans: const [
          SpeakerSpan(startMs: 0, endMs: 400, speaker: 0),
          SpeakerSpan(startMs: 400, endMs: 1200, speaker: 1),
        ],
        result: const WhisperTranscribeResponse(
          type: 'transcribe',
          text: " That's right. Yes",
          segments: [
            WhisperTranscribeSegment(
              fromTs: Duration.zero,
              toTs: Duration(milliseconds: 400),
              text: " That's",
            ),
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 400),
              toTs: Duration(milliseconds: 800),
              text: ' right.',
            ),
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: 800),
              toTs: Duration(milliseconds: 1200),
              text: ' Yes',
            ),
          ],
        ),
      );

      final transcript = (await repository.transcriptsForClip(clipId)).firstOrNull;

      // "That's right." arrived split across two speakers -- the reported
      // failure. Putting both words on one speaker is the correction, and it
      // must leave the following word alone.
      await repository.reassignSpeaker(
        transcriptId: transcript!.id,
        fromPosition: 0,
        toPosition: 1,
        speaker: 1,
      );

      final after = await repository.watchWords(transcript.id).first;
      expect(after.map((w) => w.speakerId), ['1', '1', '1']);
      expect(after.map((w) => w.startMs), [0, 400, 800]);
    });

    tearDown(() => database.close());
  });

  // There is deliberately no widget test for LibraryScreen here. The screen
  // renders off a drift `watch()` stream, and such a stream does not resolve
  // under testWidgets' fake-async clock: the test hangs until the harness
  // times it out, with or without `runAsync`, and closing the database inside
  // the fake zone hangs the same way. Covering it properly needs an
  // integration_test driving a real binding, which belongs with the on-device
  // work rather than here.
}
