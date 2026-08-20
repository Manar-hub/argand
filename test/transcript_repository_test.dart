import 'package:argand/core/database/database.dart';
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
      final repository = TranscriptRepository(database);
      final projectId = repository.newId();

      await repository.saveImport(
        projectId: projectId,
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

      final transcript = await repository.findTranscriptForProject(projectId);
      expect(transcript, isNotNull);
      expect(transcript!.fullText, 'Hello there world');

      final words = await repository.watchWords(transcript.id).first;
      expect(words.map((w) => w.word), ['Hello', 'there', 'world']);
      expect(words.map((w) => w.position), [0, 1, 2]);
      expect(words.first.startMs, 120);
      expect(words.last.endMs, 1100);
    });

    test('saveImport drops whitespace-only segments', () async {
      final repository = TranscriptRepository(database);
      final projectId = repository.newId();

      await repository.saveImport(
        projectId: projectId,
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

      final transcript = await repository.findTranscriptForProject(projectId);
      final words = await repository.watchWords(transcript!.id).first;

      // The blank segment must not survive as an empty, invisible word, and
      // positions must stay contiguous from zero after it is removed.
      expect(words.map((w) => w.word), ['you']);
      expect(words.single.position, 0);
    });

    test('softDeleteProject hides the project without removing the row', () async {
      final repository = TranscriptRepository(database);
      final projectId = repository.newId();

      await repository.saveImport(
        projectId: projectId,
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

      await repository.softDeleteProject(projectId);

      expect(await repository.findProject(projectId), isNull);
      // The row itself survives -- CLAUDE.md 5 forbids hard deletes.
      expect(await database.select(database.projects).get(), hasLength(1));
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
