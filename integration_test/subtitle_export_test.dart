import 'package:argand/core/captions/caption_grouper.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/project_screen.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Caption export, driven on a device.
///
/// The serialisers themselves are covered exhaustively on the host
/// (`test/subtitle_export_test.dart`). What only a device can show is the
/// screen: that the control appears where it should, that the sheet offers both
/// formats, and that the controller runs the whole way through against real
/// rows in Android's SQLite.
///
/// **The save dialog itself is not driven.** `FilePicker.saveFile` hands off to
/// Android's Storage Access Framework, which is another app's UI and outside
/// the test harness — tapping a format in an automated run would block until
/// the timeout. The empty-transcript path is exercised instead, because it is
/// the one route that completes without ever opening that dialog.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void log(String message) => debugPrint('EXPORT $message');

  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase();
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget host(String projectId) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProjectScreen(projectId: projectId),
        ),
      );

  Future<String> seed(String projectId, List<String> texts) async {
    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: 'export fixture',
      mediaPath: '/dev/null',
      duration: null,
      language: TranscriptionLanguage.english,
      speakerSpans: const [
        SpeakerSpan(startMs: 0, endMs: 1200, speaker: 0),
        SpeakerSpan(startMs: 1200, endMs: 4000, speaker: 1),
      ],
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: texts.join(' '),
        detectedLanguage: 'en',
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

  testWidgets('the control appears in playback and hides while editing',
      (tester) async {
    final projectId = repository.newId();
    await seed(projectId, ['Hello', 'there.', 'That', 'is', 'right.']);

    await tester.pumpWidget(host(projectId));
    await settle(tester);
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    // Edit mode replaces it with undo/redo: exporting is something you do to a
    // finished transcript, and the bar has room for one set at a time.
    expect(find.byIcon(Icons.file_download_outlined), findsNothing);
    expect(find.byIcon(Icons.undo), findsOneWidget);

    await repository.deleteProject(projectId);
  });

  testWidgets('the sheet offers both formats and the speaker toggle',
      (tester) async {
    final projectId = repository.newId();
    await seed(projectId, ['Hello', 'there.']);

    await tester.pumpWidget(host(projectId));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await settle(tester);

    expect(find.text('SubRip (.srt)'), findsOneWidget);
    expect(find.text('WebVTT (.vtt)'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);

    // Attribution is on by default: speaker-coloured captions are the app's
    // signature, so a file that drops the speakers is the deliberate choice.
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    log('sheet         -> both formats, speakers on by default');

    // Dismissed rather than chosen. Tapping a format here would reach
    // `FilePicker.saveFile` on a transcript that has words, opening the system
    // save dialog and blocking the run until it timed out.
    Navigator.of(tester.element(find.byType(SwitchListTile))).pop();
    await settle(tester);

    await repository.deleteProject(projectId);
  });

  testWidgets('an empty transcript says so instead of opening a save dialog',
      (tester) async {
    final projectId = repository.newId();
    // An import whose engine run returned nothing still creates a transcript.
    await seed(projectId, const []);

    await tester.pumpWidget(host(projectId));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await settle(tester);
    await tester.tap(find.text('WebVTT (.vtt)'));
    await settle(tester);

    // Reaching this at all is the assertion: had the controller not caught the
    // empty case, the Storage Access Framework dialog would have opened and
    // this run would have hung until it timed out.
    expect(find.text('There are no captions to export yet.'), findsOneWidget);
    log('empty         -> refused before the save dialog');

    await repository.deleteProject(projectId);
  });

  testWidgets('real rows serialise to a well-formed file on device',
      (tester) async {
    final projectId = repository.newId();
    final transcriptId = await seed(
      projectId,
      ['Hello', 'there.', 'That', 'is', 'right.', 'It', 'was', 'the', 'first.'],
    );

    final words = await repository.watchWords(transcriptId).first;
    final srt = formatSubtitles(
      groupIntoCues(words),
      format: SubtitleFormat.srt,
      speakerLabel: (cue) => 'Speaker ${cue.speaker! + 1}',
    );

    log('--- srt from real rows ---');
    for (final line in srt.trimRight().split('\n')) {
      log('| $line');
    }

    expect(srt, startsWith('1\n'));
    expect(srt, contains(' --> '));
    expect(srt, contains('Speaker 1'));
    // Every word in the transcript reaches the file. A caption file that
    // quietly drops speech is worse than no caption file.
    for (final word in words) {
      expect(srt, contains(word.word));
    }

    await repository.deleteProject(projectId);
  });
}
