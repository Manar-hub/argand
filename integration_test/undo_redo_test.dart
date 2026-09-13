import 'dart:io';

import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/project_screen.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Phase 6 against the real thing: Android's SQLite, the real app documents
/// directory, and real files on the device filesystem.
///
/// The host suite covers the same rules against an in-memory database, which
/// proves the logic. It cannot prove that the schema opens on Android, that the
/// JSON payloads survive a round trip through the platform driver, or that
/// deleting a project actually reclaims bytes -- and the last of those is the
/// bug this phase exists to fix.
///
/// Deliberately does not transcribe. Nothing here depends on whisper, so paying
/// twenty minutes for a decode would only make the check less likely to be run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void log(String message) => debugPrint('UNDO $message');

  late AppDatabase database;
  late MediaConverter converter;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase();
    converter = MediaConverter();
    repository = TranscriptRepository(database, converter);
  });

  tearDown(() => database.close());

  Future<String> seedTranscript(String projectId, List<String> texts) async {
    await repository.saveImport(
      projectId: projectId,
      title: 'undo-fixture',
      mediaPath: '/dev/null',
      duration: null,
      language: TranscriptionLanguage.english,
      speakerSpans: const [SpeakerSpan(startMs: 0, endMs: 4000, speaker: 0)],
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
    return (await repository.findTranscriptForProject(projectId))!.id;
  }

  testWidgets('the edit log survives on Android SQLite', (tester) async {
    final projectId = repository.newId();
    final transcriptId = await seedTranscript(projectId, ['Appie', 'is', 'up']);
    final word = (await repository.watchWords(transcriptId).first).first;

    await repository.updateWordText(word.id, 'API');
    log('after edit    -> ${(await repository.watchWords(transcriptId).first).first.word}');

    await repository.undo(transcriptId);
    final undone = (await repository.watchWords(transcriptId).first).first.word;
    log('after undo    -> $undone');
    expect(undone, 'Appie');

    await repository.redo(transcriptId);
    final redone = (await repository.watchWords(transcriptId).first).first.word;
    log('after redo    -> $redone');
    expect(redone, 'API');

    await repository.deleteProject(projectId);
  });

  testWidgets('history is still there after the database is reopened',
      (tester) async {
    final projectId = repository.newId();
    final transcriptId = await seedTranscript(projectId, ['one']);
    final word = (await repository.watchWords(transcriptId).first).single;
    await repository.updateWordText(word.id, 'two');

    // The whole point of a table rather than a field: closing everything down
    // and coming back must not lose the history. This is the closest a test
    // gets to the user relaunching the app.
    await database.close();
    database = AppDatabase();
    repository = TranscriptRepository(database, converter);

    final history = await repository.watchEditHistory(transcriptId).first;
    log('reopened      -> canUndo=${history.canUndo} canRedo=${history.canRedo}');
    expect(history.canUndo, isTrue);

    await repository.undo(transcriptId);
    expect((await repository.watchWords(transcriptId).first).single.word, 'one');

    await repository.deleteProject(projectId);
  });

  testWidgets('deleting a project actually reclaims the bytes', (tester) async {
    final projectId = repository.newId();
    await seedTranscript(projectId, ['gone']);

    // Stand-ins for the imported video and the extracted WAV, at a size where
    // a failure to delete would be obvious rather than rounding error.
    const payload = 512 * 1024;
    await converter.importToAppStorage(
      projectId: projectId,
      fileName: 'clip.mp4',
      bytes: Stream.value(Uint8List(payload)),
    );
    await converter.importToAppStorage(
      projectId: projectId,
      fileName: 'clip.wav',
      bytes: Stream.value(Uint8List(payload)),
    );

    final before = await converter.projectMediaBytes(projectId);
    log('media before  -> $before bytes');
    expect(before, greaterThanOrEqualTo(payload * 2));

    await repository.deleteProject(projectId);

    final after = await converter.projectMediaBytes(projectId);
    log('media after   -> $after bytes');
    // The bug this phase fixes: before it, this stayed at `before` forever and
    // the space was unreachable except by clearing the whole app's storage.
    expect(after, 0);

    // The row is kept as a tombstone, and the project is hidden either way.
    expect(await repository.findProject(projectId), isNull);
    expect(
      await database.select(database.projects).get(),
      isNotEmpty,
      reason: 'CLAUDE.md 5 forbids hard row deletes',
    );
  });

  testWidgets('the resume position round-trips and is retired on delete',
      (tester) async {
    final projectId = repository.newId();
    await seedTranscript(projectId, ['resume']);
    final key = playbackPositionKey(projectId);

    await database.writeSetting(key, '84200');
    log('stored        -> ${await database.readSetting(key)}');
    expect(await database.readSetting(key), '84200');

    await repository.deleteProject(projectId);
    final cleared = await database.readSetting(key);
    log('after delete  -> $cleared');
    expect(cleared, isNull);
  });

  testWidgets('the schema opens and reports version 3', (tester) async {
    final version = await database
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();

    log('user_version  -> $version');
    expect(version, 3);

    // Read from the open connection rather than by opening a second one --
    // drift warns about that, and rightly: two instances over one file race.
    final path = await database
        .customSelect('PRAGMA database_list')
        .map((row) => row.read<String>('file'))
        .getSingle();
    log('db size       -> ${await File(path).length()} bytes at $path');
  });

  /// The controls themselves, driven by taps.
  ///
  /// On a device rather than in `test/`, because `ProjectScreen` builds a
  /// `MediaPlayer` and `video_player` has no host implementation -- the
  /// controller leaves a pending timer that trips the widget-test invariants.
  /// Here the plugin is real. The player still fails to open the fixture's
  /// `/dev/null` path and falls back to its error state, which is fine: the
  /// history controls live in the app bar and the transcript renders either way.
  group('the app bar controls', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Widget host(String projectId) => ProviderScope(
          // Share the test's database rather than letting the provider open a
          // second one over the same file.
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProjectScreen(projectId: projectId),
          ),
        );

    Finder buttonFor(IconData icon) => find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(IconButton),
        );

    testWidgets('appear only in edit mode, and start disabled', (tester) async {
      final projectId = repository.newId();
      await seedTranscript(projectId, ['Appie', 'is', 'here.']);

      await tester.pumpWidget(host(projectId));
      await settle(tester);

      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.redo), findsNothing);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(tester.widget<IconButton>(buttonFor(Icons.undo)).onPressed, isNull);
      expect(tester.widget<IconButton>(buttonFor(Icons.redo)).onPressed, isNull);

      await repository.deleteProject(projectId);
    });

    testWidgets('undo reverts a correction made through the editor',
        (tester) async {
      final projectId = repository.newId();
      await seedTranscript(projectId, ['Appie', 'is', 'here.']);

      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      // The real gesture: tap the word, retype it, save.
      await tester.tap(find.text('Appie'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'API is here.');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('API'), findsOneWidget);
      log('typed         -> API');

      expect(
        tester.widget<IconButton>(buttonFor(Icons.undo)).onPressed,
        isNotNull,
        reason: 'the edit should have lit the undo button',
      );

      await tester.tap(buttonFor(Icons.undo));
      await settle(tester);
      expect(find.text('Appie'), findsOneWidget);
      expect(find.text('API'), findsNothing);
      log('tapped undo   -> Appie');

      await tester.tap(buttonFor(Icons.redo));
      await settle(tester);
      expect(find.text('API'), findsOneWidget);
      log('tapped redo   -> API');

      await repository.deleteProject(projectId);
    });

    testWidgets('retyping a line splits one word into two and undoes cleanly',
        (tester) async {
      // The reported case, driven through the real dialog: the engine hears
      // "brainbeats" where the speaker said "praying beads".
      final projectId = repository.newId();
      final transcriptId =
          await seedTranscript(projectId, ['It', 'was', 'brainbeats.']);
      final before = await repository.watchWords(transcriptId).first;

      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      // Tapping any word in the line opens the whole line, not that word.
      await tester.tap(find.text('was'));
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'It was brainbeats.',
          reason: 'the editor must be seeded with the whole sentence');
      log('editor        -> "${field.controller!.text}"');

      await tester.enterText(find.byType(TextField), 'It was praying beads.');
      await tester.tap(find.text('Save'));
      await settle(tester);

      final after = await repository.watchWords(transcriptId).first;
      log('after edit    -> ${after.map((w) => w.word).join(' ')}');
      expect(after.map((w) => w.word), ['It', 'was', 'praying', 'beads.']);

      // The line still occupies exactly the time it did, and the words nobody
      // touched are untouched.
      expect(after.first.startMs, before.first.startMs);
      expect(after.last.endMs, before.last.endMs);
      expect(after[1].endMs, before[1].endMs);
      log('span          -> ${after.first.startMs}..${after.last.endMs} '
          '(was ${before.first.startMs}..${before.last.endMs})');

      await tester.tap(buttonFor(Icons.undo));
      await settle(tester);

      final undone = await repository.watchWords(transcriptId).first;
      log('after undo    -> ${undone.map((w) => w.word).join(' ')}');
      expect(undone.map((w) => w.word), ['It', 'was', 'brainbeats.']);
      expect(undone.map((w) => w.position), [0, 1, 2]);

      await repository.deleteProject(projectId);
    });

    testWidgets('Word scope opens one word and confines the change to it',
        (tester) async {
      final projectId = repository.newId();
      final transcriptId =
          await seedTranscript(projectId, ['It', 'was', 'brainbeats.']);
      final before = await repository.watchWords(transcriptId).first;

      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      // The banner control, not a hidden gesture.
      await tester.tap(find.text('Word'));
      await settle(tester);

      await tester.tap(find.text('brainbeats.'));
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'brainbeats.',
          reason: 'Word scope must seed the editor with that word alone');
      log('word editor   -> "${field.controller!.text}"');

      await tester.enterText(find.byType(TextField), 'praying beads.');
      await tester.tap(find.text('Save'));
      await settle(tester);

      final after = await repository.watchWords(transcriptId).first;
      log('after edit    -> ${after.map((w) => w.word).join(' ')}');
      expect(after.map((w) => w.word), ['It', 'was', 'praying', 'beads.']);

      // The pair sits exactly in the box the one word had, and the two words
      // before it did not move by a millisecond.
      expect(after[2].startMs, before[2].startMs);
      expect(after[3].endMs, before[2].endMs);
      expect(after[0].endMs, before[0].endMs);
      expect(after[1].endMs, before[1].endMs);
      log('word box      -> ${after[2].startMs}..${after[3].endMs} '
          '(was ${before[2].startMs}..${before[2].endMs})');

      await tester.tap(buttonFor(Icons.undo));
      await settle(tester);
      expect(
        (await repository.watchWords(transcriptId).first).map((w) => w.word),
        ['It', 'was', 'brainbeats.'],
      );

      await repository.deleteProject(projectId);
    });

    testWidgets('Line scope still opens the whole sentence', (tester) async {
      final projectId = repository.newId();
      await seedTranscript(projectId, ['It', 'was', 'brainbeats.']);

      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      // Line is the default, so this asserts the control did not silently
      // change what a tap does before the user chose anything.
      await tester.tap(find.text('was'));
      await settle(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'It was brainbeats.',
      );

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await repository.deleteProject(projectId);
    });

    testWidgets('history is still offered after the screen is rebuilt',
        (tester) async {
      final projectId = repository.newId();
      await seedTranscript(projectId, ['Appie', 'is', 'here.']);

      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);
      await tester.tap(find.text('Appie'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'API is here.');
      await tester.tap(find.text('Save'));
      await settle(tester);

      // Tear the screen down completely, which is what closing a project does.
      // An in-memory undo stack would not survive this.
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pumpWidget(host(projectId));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await settle(tester);

      expect(
        tester.widget<IconButton>(buttonFor(Icons.undo)).onPressed,
        isNotNull,
        reason: 'the log is a table, so history outlives the widget',
      );

      await tester.tap(buttonFor(Icons.undo));
      await settle(tester);
      expect(find.text('Appie'), findsOneWidget);
      log('after rebuild -> undo still worked');

      await repository.deleteProject(projectId);
    });
  });
}
