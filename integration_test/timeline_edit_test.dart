import 'dart:io';

import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/clip_trim.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/features/transcription/editor_mode_controller.dart';
import 'package:argand/features/transcription/project_screen.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The timeline's editing gestures, driven on a device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const fixture = '/data/local/tmp/alberta.mp4';

  void log(String message) => debugPrint('TIMELINE EDIT $message');

  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase();
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  /// Takes the screen down while the database is still open.
  Future<void> closeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(String projectId, MediaClip clip)> seed() async {
    final source = File(fixture);
    expect(
      source.existsSync(),
      isTrue,
      reason: 'adb push alberta.mp4 /data/local/tmp/alberta.mp4 first',
    );

    final projectId = await repository.createEmptyProject(title: 'edit');
    final clip = await repository.addClip(
      projectId: projectId,
      fileName: 'shot.mp4',
      bytes: source.openRead(),
    );
    return (projectId, clip);
  }

  Widget host(String projectId) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProjectScreen(
            projectId: projectId,
            initialMode: EditorMode.timeline,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Whether the timeline is showing [label] as selected.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    final rect = tester.getRect(finder);
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final visible = rect.intersect(screen);

    expect(
      visible.width > 0 && visible.height > 0,
      isTrue,
      reason: 'nothing of the target is on screen to tap',
    );
    await tester.tapAt(visible.center);
  }

  bool isSelected(WidgetTester tester, String label) {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    // `flagsCollection` returns a `Tristate` that Flutter does not export, so
    // there is no public, non-deprecated way to ask this from a test.
    // ignore: deprecated_member_use
    return node.hasFlag(SemanticsFlag.isSelected);
  }

  testWidgets('a clip can be selected and, crucially, deselected',
      (tester) async {
    final (projectId, clip) = await seed();

    await tester.pumpWidget(host(projectId));
    await settle(tester);

    final tile = find.bySemanticsLabel(clip.title);
    expect(tile, findsOneWidget, reason: 'the clip should be on the timeline');
    expect(isSelected(tester, clip.title), isFalse);

    await tapVisible(tester, tile);
    await settle(tester);
    expect(isSelected(tester, clip.title), isTrue);

    // The regression. Selecting a clip grows trim handles at both ends, and
    // those are `HitTestBehavior.opaque`.
    await tapVisible(tester, tile);
    await settle(tester);
    expect(
      isSelected(tester, clip.title),
      isFalse,
      reason: 'a second tap must release the clip',
    );

    await closeScreen(tester);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('splitting and then rolling the cut keeps the project length',
      (tester) async {
    final (projectId, clip) = await seed();
    final sourceMs = clip.durationMs ?? 0;
    log('source is ${sourceMs}ms');
    expect(sourceMs, greaterThan(0));

    await repository.splitClip(clipId: clip.id, atClipMs: sourceMs ~/ 3);

    var clips = await repository.clipsForProject(projectId);
    expect(clips, hasLength(2));
    expect(
      ProjectTimeline.fromClips(clips).totalMs,
      sourceMs,
      reason: 'a split must not change how long the project is',
    );

    // **The 14s file that became a 22s project.** Dragging one half outward
    // used to re-cover footage the other half already played, so the two
    // together ran longer than the file they came from.
    final rolled = rollCut(
      left: clips.first,
      right: clips.last,
      deltaMs: 4000,
    );
    await repository.rollCut(
      leftClipId: clips.first.id,
      rightClipId: clips.last.id,
      cut: rolled,
    );

    clips = await repository.clipsForProject(projectId);
    final total = ProjectTimeline.fromClips(clips).totalMs;
    log('after rolling: ${total}ms across ${clips.length} clips');

    expect(
      total,
      sourceMs,
      reason: 'moving the cut must not lengthen the project',
    );
    expect(
      clipWindow(clips.first).endMs,
      clipWindow(clips.last).startMs,
      reason: 'the halves must still meet',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
