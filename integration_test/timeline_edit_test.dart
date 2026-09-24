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
///
/// **These are only provable here.** `timeline_mode_test.dart` deliberately
/// does not pump `ProjectScreen` on the host, because both modes build a
/// `MediaPlayer` and `video_player` has no host implementation. Selection,
/// splitting and the preview are exactly the parts that behaviour hides, so
/// they get driven against the real screen instead.
///
/// Requires the fixture:
///
/// ```
/// adb push alberta.mp4 /data/local/tmp/alberta.mp4
/// ```
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
  ///
  /// **The order matters and is not the default one.** The shared decoder
  /// saves its playback position from `onDispose`, which cannot await, and
  /// `flutter_test` disposes the widget tree in its *own* teardown -- after
  /// this file's. So closing the database in `tearDown` races a write that has
  /// not been issued yet, and drift reports a rolled-back transaction on a
  /// test that already passed. Disposing here puts the write first.
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
  ///
  /// Read off the semantics tree rather than off a provider, because what is
  /// being checked is that the *screen* agrees -- a provider holding the right
  /// value while the tile swallowed the tap is exactly the bug.
  /// Taps a part of [finder] that is actually on screen.
  ///
  /// **`tester.tap` aims at the centre, which does not work here.** A clip's
  /// width *is* its duration, so a 42-second clip is a thousand points wide on
  /// a 448-point screen and its centre is somewhere off to the right. Aiming
  /// there misses entirely -- and misses differently depending on where the
  /// timeline happens to be scrolled, which is a flaky test rather than a
  /// flaky app. A person taps the part they can see; so does this.
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

    // **The regression.** Selecting a clip grows trim handles at both ends,
    // and those are `HitTestBehavior.opaque`. On a narrow tile they cover it
    // completely, so a handle that only listened for drags swallowed every
    // tap and the clip could never be let go of again.
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
