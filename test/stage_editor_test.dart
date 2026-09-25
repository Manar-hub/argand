import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:argand/features/transcription/clip_controller.dart';
import 'package:argand/features/transcription/stage_editor.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/features/transcription/video_settings_panel.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Typing into a text happens on the picture, with the keyboard -- never in a
/// dialog.
void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A one-clip project with a text over its first three seconds, on a
  /// stage whose player sits one second in.
  Future<(ProviderContainer, String, String)> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final projectId = repository.newId();
    final clipId = repository.newId();
    await database.createEmptyProject(projectId: projectId, title: 'p');
    await database.appendClip(
      clipId: clipId,
      projectId: projectId,
      mediaPath: '/tmp/a.mp4',
      title: 'a',
      duration: const Duration(seconds: 10),
    );
    final textId = (await repository.addTextLayer(
      projectId: projectId,
      startMs: 0,
      endMs: 3000,
      content: 'Title',
    ))!;

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: ProjectStageCanvas(
                projectId: projectId,
                clipId: clipId,
                sourceSize: const Size(1920, 1080),
                picture: const ColoredBox(color: Colors.blue),
                mediaPositionMs: 1000,
                editable: true,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    return (container, projectId, textId);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the text is on the picture, and a tap picks it',
      (tester) async {
    final (container, projectId, textId) = await mount(tester);

    expect(find.text(' Title '), findsOneWidget);
    await tester.tap(find.text(' Title '));
    await settle(tester);

    expect(
      container.read(timelineSelectionProvider(projectId)),
      {(kind: TimelineItemKind.text, id: textId)},
    );
    expect(find.byType(TextField), findsNothing, reason: 'picked, not typing');

    await unmount(tester);
  });

  testWidgets('a second tap types into it in place, and Done saves',
      (tester) async {
    final (_, projectId, textId) = await mount(tester);

    await tester.tap(find.text(' Title '));
    await settle(tester);
    await tester.tap(find.text(' Title '));
    await settle(tester);

    // A field where the words were -- no dialog anywhere.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'keyboard up');

    // The words as they were, with a cursor after them -- nothing selected,
    // so no highlight or handles appear around them.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Title');
    expect(field.controller!.selection, const TextSelection.collapsed(offset: 5));
    // And no border of any kind: the theme's focused outline must not reach
    // the words on the picture.
    expect(field.decoration!.focusedBorder, InputBorder.none);
    expect(field.decoration!.filled, isFalse);

    await tester.enterText(find.byType(TextField), 'Night walk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.byType(TextField), findsNothing);
    final texts = await repository.textLayersForProject(projectId);
    expect(texts.single.content, 'Night walk');
    expect(texts.single.id, textId);

    await unmount(tester);
  });

  testWidgets('emptying a text removes it', (tester) async {
    final (container, projectId, textId) = await mount(tester);

    // Started from outside the stage, as the Text tool starts it.
    container
        .read(stageEditingProvider(projectId).notifier)
        .start((kind: TimelineItemKind.text, id: textId));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(await repository.textLayersForProject(projectId), isEmpty);

    await unmount(tester);
  });

  testWidgets('typing asked for before the stage is up still opens',
      (tester) async {
    // The Text tool can ask while the player is still loading, before any
    // stage exists to listen. The request must wait for it, not vanish.
    final (container, projectId, textId) = await mount(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await settle(tester);

    container
        .read(stageEditingProvider(projectId).notifier)
        .start((kind: TimelineItemKind.text, id: textId));
    await settle(tester);

    final clipId =
        (await repository.clipsForProject(projectId)).single.id;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: ProjectStageCanvas(
                projectId: projectId,
                clipId: clipId,
                sourceSize: const Size(1920, 1080),
                picture: const ColoredBox(color: Colors.blue),
                mediaPositionMs: 1000,
                editable: true,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(TextField), findsOneWidget);

    await unmount(tester);
  });
}
