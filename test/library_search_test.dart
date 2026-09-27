import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/library_search.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  // Deleting a project reaches for the platform to remove its media.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });
  tearDown(() => database.close());

  /// A project called [title] whose one clip says [words], one per 500ms.
  Future<({String projectId, String clipId})> project(
    String title,
    List<String> words,
  ) async {
    final projectId = repository.newId();
    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: title,
      mediaPath: '/tmp/$title.mp4',
      duration: const Duration(seconds: 30),
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: words.join(' '),
        segments: [
          for (final (i, word) in words.indexed)
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: i * 500),
              toTs: Duration(milliseconds: i * 500 + 400),
              text: ' $word',
            ),
        ],
      ),
    );
    return (projectId: projectId, clipId: clipId);
  }

  group('searchTokens / phraseMatchesAt', () {
    test('tokens are lower-cased words; blank is no search', () {
      expect(searchTokens('  Hello   World '), ['hello', 'world']);
      expect(searchTokens('   '), isEmpty);
    });

    test('each token must sit inside the word at its place', () {
      final words = ['Well,', 'hello', 'world.', 'Bye'];
      expect(phraseMatchesAt(words, 1, ['hello', 'wor']), isTrue);
      expect(phraseMatchesAt(words, 1, ['hello', 'bye']), isFalse);
      expect(phraseMatchesAt(words, 3, ['bye', 'now']), isFalse);
    });

    test('LIKE wildcards are escaped', () {
      expect(escapeLike(r'50%_a\b'), r'50\%\_a\\b');
    });
  });

  group('AppDatabase.searchLibrary', () {
    test('an empty query finds nothing, so the caller shows every project',
        () async {
      await project('Interview', ['hello']);
      expect(await database.searchLibrary('  '), isEmpty);
    });

    test('finds a project by its title', () async {
      final a = await project('Morning interview', ['hello']);
      await project('Podcast', ['hello']);

      final hits = await database.searchLibrary('interview');
      expect(hits.map((h) => h.project.id), [a.projectId]);
      expect(hits.single.word, isNull);
    });

    test('finds a word, with its clip, time and the words around it',
        () async {
      final a = await project('Talk', [
        for (var i = 0; i < 12; i++) 'w$i',
        'Syria,',
        for (var i = 0; i < 12; i++) 'x$i',
      ]);

      final hit = (await database.searchLibrary('syria')).single;
      expect(hit.project.id, a.projectId);
      final word = hit.word!;
      expect(word.clipId, a.clipId);
      expect(word.startMs, 12 * 500);
      expect(word.snippet[word.matchStart], 'Syria,');
      expect(word.matchLength, 1);
      // Eight words either side.
      expect(word.snippet.first, 'w4');
      expect(word.snippet.last, 'x7');
    });

    test('a phrase has to be said in order', () async {
      await project('A', ['the', 'quick', 'brown', 'fox']);
      final b = await project('B', ['quick', 'the', 'fox', 'brown']);

      final quickBrown = await database.searchLibrary('quick brown');
      expect(quickBrown, hasLength(1));
      expect(quickBrown.single.word!.snippet, ['the', 'quick', 'brown', 'fox']);

      final theFox = await database.searchLibrary('the fox');
      expect(theFox.map((h) => h.project.id), [b.projectId]);
    });

    test('finds what a word was corrected to, not what it was', () async {
      await project('Edited', ['praying', 'beads']);
      final transcript =
          (await database.select(database.transcripts).get()).single;
      final words = await repository.watchWords(transcript.id).first;
      await repository.updateWordText(words.first.id, 'brainbeats');

      expect(await database.searchLibrary('praying'), isEmpty);
      expect(await database.searchLibrary('brainbeats'), hasLength(1));
    });

    test('deleted projects are not found', () async {
      final a = await project('Gone', ['hello']);
      await repository.deleteProject(a.projectId);

      expect(await database.searchLibrary('hello'), isEmpty);
      expect(await database.searchLibrary('gone'), isEmpty);
    });

    test('a typed % is looked for, not a wildcard', () async {
      await project('Numbers', ['fifty', 'percent']);
      expect(await database.searchLibrary('%'), isEmpty);
    });
  });
}
