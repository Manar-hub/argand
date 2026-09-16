import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/features/library/library_screen.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The library's two import entry points, added for Timeline mode.
///
/// **`ProjectScreen`/`TimelineBody` are deliberately not exercised here**,
/// for the same reason `phase6_ui_test.dart` excludes `ProjectScreen`: both
/// modes' preview builds a `MediaPlayer`, and `video_player` has no host
/// implementation, which leaves a pending timer that wedges every test after
/// it. The mode switch and Timeline's bottom toolbar are verified on-device
/// instead (`docs/progress.md`'s Phase 8.5/9 addendum).
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// `testWidgets`, plus an explicit unmount before the test ends -- see
  /// `phase6_ui_test.dart`'s `uiTest` for why this matters with Drift.
  void uiTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  Widget host(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('library entry points', () {
    uiTest('shows the create-project and transcribe panels', (tester) async {
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      // Two entry points that differ in *when* transcription happens, which is
      // the distinction the whole multi-clip model rests on: Create project
      // makes an empty shell to add clips to, Transcribe turns one file into a
      // project immediately.
      expect(find.text('Create project'), findsOneWidget);
      expect(
        find.text('Name it, then add clips on the timeline'),
        findsOneWidget,
      );
      expect(find.text('Transcribe'), findsOneWidget);
      expect(
        find.text('Video or audio — transcribed on your device'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    uiTest('Create project asks for a name first', (tester) async {
      await tester.pumpWidget(host(const LibraryScreen()));
      await settle(tester);

      await tester.tap(find.text('Create project'));
      await settle(tester);

      expect(find.text('Name this project'), findsOneWidget);
      // Prefilled as a hint rather than required: naming exists because a
      // multi-clip project has no filename to borrow one from, not to force
      // the user to invent something before they can start.
      expect(find.text('Untitled project'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    // Confirming the dialog is deliberately *not* driven here. It pushes
    // `ProjectScreen`, which builds a `MediaPlayer`, and `video_player` has no
    // host implementation -- the controller leaves a pending timer that fails
    // the test that created it and then wedges every test after it. Same
    // reason `phase6_ui_test.dart` excludes that screen. What creation
    // actually does is asserted against the repository below, and the flow end
    // to end is driven on-device.

    uiTest('both panels stay distinct and tappable at double text scale',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: LibraryScreen(),
            ),
          ),
        ),
      );
      await settle(tester);

      // A RenderFlex overflow throws during layout, so an empty
      // `takeException` is the assertion that chunky type plus this app's
      // thick borders did not break the panel row (CLAUDE.md's 2x text scale
      // rule).
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Create project'), findsOneWidget);
      expect(find.text('Transcribe'), findsOneWidget);
    });
  });

  group('creating an empty project', () {
    test('makes a project with a name and no media', () async {
      final repository = TranscriptRepository(database, MediaConverter());

      final projectId = await repository.createEmptyProject(title: 'road trip');

      final project = await database.findProject(projectId);
      expect(project!.title, 'road trip');
      // The state the old import flow could never produce, and the whole point
      // of the entry point: a project that exists before any media does.
      expect(await database.clipsForProject(projectId), isEmpty);
    });

    test('clips append in order and removal closes the gap', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = await repository.createEmptyProject(title: 'trip');

      for (final title in ['first', 'second', 'third']) {
        await database.appendClip(
          clipId: repository.newId(),
          projectId: projectId,
          mediaPath: '/media/$projectId/$title.mp4',
          duration: const Duration(seconds: 5),
          title: title,
        );
      }

      var clips = await database.clipsForProject(projectId);
      expect([for (final clip in clips) clip.title], ['first', 'second', 'third']);
      expect([for (final clip in clips) clip.position], [0, 1, 2]);

      await database.softDeleteClip(clips[1].id);

      // Positions stay a contiguous run. A hole would survive into the next
      // reorder and put two clips on one slot.
      clips = await database.clipsForProject(projectId);
      expect([for (final clip in clips) clip.title], ['first', 'third']);
      expect([for (final clip in clips) clip.position], [0, 1]);
    });

    test('a clip with no usable duration is repaired, a real one is kept',
        () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = await repository.createEmptyProject(title: 'trip');

      final unknown = repository.newId();
      final zero = repository.newId();
      final known = repository.newId();

      await database.appendClip(
        clipId: unknown,
        projectId: projectId,
        mediaPath: '/media/$projectId/a.mp4',
        duration: null,
        title: 'a',
      );
      await database.appendClip(
        clipId: zero,
        projectId: projectId,
        mediaPath: '/media/$projectId/b.mp4',
        duration: Duration.zero,
        title: 'b',
      );
      await database.appendClip(
        clipId: known,
        projectId: projectId,
        mediaPath: '/media/$projectId/c.mp4',
        duration: const Duration(seconds: 12),
        title: 'c',
      );

      for (final id in [unknown, zero, known]) {
        await database.fillMissingClipDuration(id, const Duration(seconds: 29));
      }

      // Null and zero both mean "nobody has measured this yet" -- a
      // zero-length clip cannot exist, and treating one as real would leave
      // every clip the migration carried over stuck at a minimum width.
      expect((await database.findClip(unknown))!.durationMs, 29000);
      expect((await database.findClip(zero))!.durationMs, 29000);
      // A duration that was actually measured is never overwritten.
      expect((await database.findClip(known))!.durationMs, 12000);
    });

    test('reordering rewrites the whole order', () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = await repository.createEmptyProject(title: 'trip');

      for (final title in ['a', 'b', 'c']) {
        await database.appendClip(
          clipId: repository.newId(),
          projectId: projectId,
          mediaPath: '/media/$projectId/$title.mp4',
          duration: const Duration(seconds: 5),
          title: title,
        );
      }

      final clips = await database.clipsForProject(projectId);
      await database.reorderClips(
        projectId: projectId,
        orderedIds: [clips[2].id, clips[0].id, clips[1].id],
      );

      final reordered = await database.clipsForProject(projectId);
      expect([for (final clip in reordered) clip.title], ['c', 'a', 'b']);
      expect([for (final clip in reordered) clip.position], [0, 1, 2]);
    });

    test('a clip carries its own transcript, independent of its siblings',
        () async {
      final repository = TranscriptRepository(database, MediaConverter());
      final projectId = await repository.createEmptyProject(title: 'trip');

      final first = repository.newId();
      final second = repository.newId();
      for (final (id, title) in [(first, 'one'), (second, 'two')]) {
        await database.appendClip(
          clipId: id,
          projectId: projectId,
          mediaPath: '/media/$projectId/$title.mp4',
          duration: const Duration(seconds: 5),
          title: title,
        );
      }

      await repository.saveClipTranscript(
        projectId: projectId,
        clipId: first,
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

      // Transcribing one clip says nothing about the other -- which is what
      // makes "transcribe only the clips worth the minutes" real rather than
      // an all-or-nothing choice dressed up per clip.
      final transcribed = await repository.findTranscriptForClip(first);
      expect(transcribed, isNotNull);
      expect(transcribed!.fullText, 'hello');
      expect(await repository.findTranscriptForClip(second), isNull);
    });
  });
}
