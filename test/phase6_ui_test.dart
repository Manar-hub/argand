import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/library/library_screen.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// The library's Phase 6 surfaces, driven by taps rather than read from source.
///
/// `WidgetTester` builds the real widget tree over a real in-memory database,
/// so a control wired to the wrong provider, a dialog that does not appear, or
/// a row that overflows fails here with no device involved.
///
/// **`ProjectScreen` is deliberately not here.** It builds a `MediaPlayer`, and
/// `video_player` has no host implementation -- the controller leaves a pending
/// timer that trips `_verifyInvariants`, fails the test that created it and
/// then wedges every test after it. Those controls are driven on a real device
/// instead, in `integration_test/undo_redo_test.dart`.
///
/// What none of this claims is that any of it *looks* right. That needs eyes.
void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  /// Advances a bounded number of frames.
  ///
  /// Not `pumpAndSettle`: the screen shows a `CircularProgressIndicator` while
  /// its providers resolve, and an indeterminate spinner never reaches
  /// quiescence -- so settling waits for a frame that will not come and the run
  /// looks hung. Fixed frames give the providers time without that trap.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// `testWidgets`, plus an explicit unmount before the test ends.
  ///
  /// Drift schedules a zero-duration timer from `StreamQueryStore.markAsClosed`
  /// when a query stream is cancelled, and `ProviderScope` cancels them all as
  /// it disposes. Left to the framework's own teardown that happens *after* the
  /// last pump, so the timer is still pending when `_verifyInvariants` runs --
  /// which fails the test and then wedges every test after it. Unmounting here
  /// and pumping once lets it fire while the clock is still running.
  void uiTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      // A non-zero duration: a bare `pump()` does not advance the fake clock,
      // so a `Timer(Duration.zero)` never comes due.
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  Widget host(Widget child, {double textScale = 1}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        // The real theme, so these tests exercise what ships -- a bare
        // MaterialApp would miss the AppSurface extension entirely.
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    );
  }

  Future<String> seedProject(String title) async {
    final projectId = repository.newId();
    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: title,
      mediaPath: '/tmp/$projectId.mp4',
      duration: const Duration(seconds: 61),
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      result: const WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'hello',
        segments: [
          WhisperTranscribeSegment(
            fromTs: Duration.zero,
            toTs: Duration(milliseconds: 400),
            text: ' hello',
          ),
        ],
      ),
    );
    return projectId;
  }

  group('library row', () {
    uiTest('shows the running time', (tester) async {
      await seedProject('clip');
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      expect(find.text('clip'), findsOneWidget);
      expect(find.textContaining('01:01'), findsOneWidget);
      // The created date is on the face of the card too, so two imports of
      // the same clip can be told apart without opening them.
      expect(find.textContaining('2026'), findsOneWidget);
    });

    uiTest('a long title does not overflow', (tester) async {
      await seedProject(
        'Interview with the entire department, part three, the final cut',
      );
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      // A RenderFlex overflow is an exception thrown during layout, so an empty
      // `takeException` is the assertion. Checked explicitly rather than
      // trusting the test to notice on its own.
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Interview with the entire'), findsOneWidget);
    });

    uiTest('a long title at double text scale does not overflow',
        (tester) async {
      await seedProject(
        'Interview with the entire department, part three, the final cut',
      );
      await tester.pumpWidget(host(const LibraryScreen(), textScale: 2));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Interview with the entire'), findsOneWidget);
    });
  });

  group('delete confirmation', () {
    uiTest('long-press opens a dialog stating it cannot be undone',
        (tester) async {
      await seedProject('doomed');
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      await tester.longPress(find.text('doomed'));
      await settle(tester);

      // The sheet offers all three actions before anything destructive.
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      // The promise the whole design rests on: the user is told before the
      // video is destroyed, rather than given seconds to catch it afterwards.
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);
    });

    uiTest('cancelling keeps the project', (tester) async {
      final projectId = await seedProject('spared');
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      await tester.longPress(find.text('spared'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('spared'), findsOneWidget);
      // A one-shot query, not `watchProjects().first`: a drift query stream
      // only emits after a table-update notification, which the fake clock in
      // a widget test never delivers, so awaiting it hangs the whole run.
      expect(await database.findProject(projectId), isNotNull);
    });

    uiTest('confirming removes it from the library', (tester) async {
      final projectId = await seedProject('doomed');
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      await tester.longPress(find.text('doomed'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);

      expect(find.text('doomed'), findsNothing);
      expect(await database.findProject(projectId), isNull);
      // Soft, not hard: the tombstone row stays for a future sync, while the
      // media -- absent here, since nothing was imported -- is what goes.
      expect(await database.select(database.projects).get(), hasLength(1));
    });

    uiTest('deleting one project leaves the others alone', (tester) async {
      await seedProject('keep me');
      await seedProject('doomed');
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      await tester.longPress(find.text('doomed'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);

      expect(find.text('doomed'), findsNothing);
      expect(find.text('keep me'), findsOneWidget);
    });
  });
}
