import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/video/export_options.dart';
import 'package:argand/features/transcription/editor_mode_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/features/transcription/video_canvas.dart';
import 'package:argand/features/transcription/video_settings.dart';
import 'package:argand/features/transcription/video_settings_panel.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoSettings', () {
    test('round-trips through storage', () {
      const settings = VideoSettings(
        aspect: ExportAspect.portrait9x16,
        quality: ExportQuality.p720,
        corner: WatermarkCorner.bottomLeft,
        previewWatermark: false,
      );

      expect(VideoSettings.decode(settings.encode()), settings);
    });

    test('a project never set up opens with the defaults', () {
      expect(VideoSettings.decode(null), VideoSettings.defaults);
      expect(VideoSettings.decode('not json'), VideoSettings.defaults);
    });

    test('an unknown value falls back rather than failing the project', () {
      // Written by a newer build with a shape this one does not know.
      final decoded = VideoSettings.decode(
        '{"aspect":"cinema21x9","quality":"p720","corner":"topLeft"}',
      );

      expect(decoded.aspect, VideoSettings.defaults.aspect);
      expect(decoded.quality, ExportQuality.p720);
      expect(decoded.corner, WatermarkCorner.topLeft);
    });

    test('the export starts from the project\'s own settings', () {
      const settings = VideoSettings(
        aspect: ExportAspect.square1x1,
        corner: WatermarkCorner.bottomRight,
      );

      final options = settings.exportOptions;

      expect(options.aspect, ExportAspect.square1x1);
      expect(options.corner, WatermarkCorner.bottomRight);
      expect(options.watermark, isTrue, reason: 'settings never waive it');
    });
  });

  group('WatermarkCorner', () {
    test('sends the render the anchor it has always used for top-right', () {
      // The render's default was (0.94, 0.90) before corners were choosable;
      // top-right must still land exactly there.
      final encoded = const ExportOptions().encode();

      expect(encoded['watermarkAnchorX'], closeTo(0.94, 1e-9));
      expect(encoded['watermarkAnchorY'], closeTo(0.90, 1e-9));
    });

    test('mirrors that anchor into each corner', () {
      for (final corner in WatermarkCorner.values) {
        final encoded = ExportOptions(corner: corner).encode();

        expect(
          encoded['watermarkAnchorX'],
          closeTo(0.94 * corner.horizontal, 1e-9),
          reason: '$corner',
        );
        expect(
          encoded['watermarkAnchorY'],
          closeTo(0.90 * corner.vertical, 1e-9),
          reason: '$corner',
        );
      }
    });
  });

  group('VideoCanvas', () {
    Future<void> pumpCanvas(
      WidgetTester tester, {
      required double ratio,
      WatermarkCorner? watermark,
    }) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: VideoCanvas(
                ratio: ratio,
                picture: const ColoredBox(color: Colors.blue),
                watermark: watermark,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('fits the output\'s shape inside the stage', (tester) async {
      await pumpCanvas(tester, ratio: 9 / 16);

      // 9:16 in a 400x300 stage is limited by height: 168.75 wide.
      final frame = tester.getSize(find.byType(AspectRatio));
      expect(frame.height, 300);
      expect(frame.width, closeTo(168.75, 0.01));
    });

    testWidgets('puts the mark where the render will', (tester) async {
      await pumpCanvas(
        tester,
        ratio: 16 / 9,
        watermark: WatermarkCorner.bottomLeft,
      );

      final frame = tester.getRect(find.byType(AspectRatio));
      final mark = tester.getRect(find.byType(WatermarkMark));

      // Inset 3% of the width from the left, 5% of the height from the bottom
      // -- the same insets the anchor numbers encode.
      expect(mark.left - frame.left, closeTo(frame.width * 0.03, 0.01));
      expect(frame.bottom - mark.bottom, closeTo(frame.height * 0.05, 0.01));
    });

    testWidgets('draws no mark when asked not to', (tester) async {
      await pumpCanvas(tester, ratio: 1);

      expect(find.byType(WatermarkMark), findsNothing);
    });
  });

  group('the video settings panel', () {
    late AppDatabase database;
    late TranscriptRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TranscriptRepository(database, MediaConverter());
    });

    tearDown(() => database.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// The gear over a stand-in for the timeline, with the panel laid over
    /// it the way both modes lay it out.
    Future<(ProviderContainer, String)> mount(
      WidgetTester tester, {
      double textScale = 1,
      bool animationsOff = false,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final projectId = await repository.createEmptyProject(title: 'reel');
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);
      // Open in Timeline, so the panel's mode item offers Script.
      container
          .read(sessionEditorModeProvider(projectId).notifier)
          .select(EditorMode.timeline);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: animationsOff,
              ),
              child: Scaffold(
                body: Column(
                  children: [
                    // A 16:9 clip on the stage, as both modes draw it.
                    SizedBox(
                      height: 200,
                      child: ProjectStageCanvas(
                        projectId: projectId,
                        sourceSize: const Size(1920, 1080),
                        picture: const ColoredBox(
                          key: Key('picture'),
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    VideoSettingsGear(projectId: projectId),
                    Expanded(
                      child: Stack(
                        children: [
                          const Center(child: Text('timeline behind')),
                          Positioned.fill(
                            child: VideoSettingsPanel(
                              projectId: projectId,
                              mode: EditorMode.timeline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      return (container, projectId);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Future<void> tap(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await settle(tester);
    }

    Finder gear() => find.byType(VideoSettingsGear);

    testWidgets('closed, nothing covers the timeline', (tester) async {
      await mount(tester);

      expect(find.text('Aspect ratio'), findsNothing);
      // The timeline takes its own touches while the panel is away...
      expect(find.text('timeline behind').hitTestable(), findsOneWidget);

      // ...and none while it is open: the dimmed layer takes them instead.
      await tap(tester, gear());
      expect(find.text('timeline behind').hitTestable(), findsNothing);

      await unmount(tester);
    });

    testWidgets('the gear opens one row of items', (tester) async {
      await mount(tester);

      await tap(tester, gear());

      for (final label in ['Script', 'Aspect ratio', 'Resolution', 'Watermark']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await unmount(tester);
    });

    testWidgets('a shape chosen here is the project\'s shape', (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('9:16'));

      expect(
        container.read(projectVideoSettingsProvider(projectId)).value?.aspect,
        ExportAspect.portrait9x16,
      );
      expect(
        VideoSettings.decode(
          await database.readSetting(videoSettingsKey(projectId)),
        ).aspect,
        ExportAspect.portrait9x16,
        reason: 'kept for the next time the project opens',
      );

      await unmount(tester);
    });

    testWidgets('a new shape fits the whole picture, with bars, not a crop',
        (tester) async {
      await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('9:16'));

      final frame = tester.getRect(find.byType(AspectRatio));
      final picture = tester.getRect(find.byKey(const Key('picture')));

      expect(frame.width / frame.height, closeTo(9 / 16, 0.01));
      // The 16:9 picture spans the frame's width and keeps its own shape,
      // leaving black above and below it.
      expect(picture.width, closeTo(frame.width, 0.01));
      expect(picture.width / picture.height, closeTo(16 / 9, 0.01));
      expect(picture.height, lessThan(frame.height));
      expect(picture.center.dy, closeTo(frame.center.dy, 0.01));

      await unmount(tester);
    });

    testWidgets('sizes the footage cannot fill are not offered',
        (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('Resolution'));
      // With no readable source it is assumed 1080p: 2K would be an upscale.
      await tap(tester, find.text('2K'));

      expect(
        container.read(projectVideoSettingsProvider(projectId)).value?.quality,
        VideoSettings.defaults.quality,
      );

      await unmount(tester);
    });

    testWidgets('corners are targets on the stage only while choosing one',
        (tester) async {
      await mount(tester);

      expect(find.bySemanticsLabel('Lower left'), findsNothing);

      await tap(tester, gear());
      await tap(tester, find.text('Watermark'));
      expect(find.bySemanticsLabel('Lower left'), findsOneWidget);

      await tap(tester, gear());
      expect(find.bySemanticsLabel('Lower left'), findsNothing);

      await unmount(tester);
    });

    testWidgets('each item shows only its own settings', (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('Resolution'));
      expect(find.text('9:16'), findsNothing, reason: 'aspect has gone');

      await tap(tester, find.text('720p'));
      expect(
        container.read(projectVideoSettingsProvider(projectId)).value?.quality,
        ExportQuality.p720,
      );

      await unmount(tester);
    });

    testWidgets('the watermark takes the corner that is tapped',
        (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('Watermark'));
      await tap(tester, find.bySemanticsLabel('Lower left'));
      await tap(tester, find.text('Hidden'));

      final settings =
          container.read(projectVideoSettingsProvider(projectId)).value!;
      expect(settings.corner, WatermarkCorner.bottomLeft);
      expect(settings.previewWatermark, isFalse);

      await unmount(tester);
    });

    testWidgets('the mode item switches mode and puts the panel away',
        (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('Script'));

      expect(
        container.read(sessionEditorModeProvider(projectId)),
        EditorMode.script,
      );
      expect(
        container.read(videoSettingsPanelControllerProvider(projectId)).open,
        isFalse,
      );

      await unmount(tester);
    });

    testWidgets('tapping what is behind closes it', (tester) async {
      final (container, projectId) = await mount(tester);

      await tap(tester, gear());
      // Well below the options card, on the dimmed timeline.
      await tap(tester, find.text('timeline behind'));

      expect(
        container.read(videoSettingsPanelControllerProvider(projectId)).open,
        isFalse,
      );
      expect(find.text('Aspect ratio'), findsNothing);

      await unmount(tester);
    });

    testWidgets('reopens on the item it was left on', (tester) async {
      await mount(tester);

      await tap(tester, gear());
      await tap(tester, find.text('Watermark'));
      await tap(tester, gear());
      await tap(tester, gear());

      expect(find.text('Hidden'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('with animations off, it is simply there', (tester) async {
      await mount(tester, animationsOff: true);

      await tester.tap(gear());
      // One frame, no time passing: nothing should need to animate in.
      await tester.pump();

      expect(find.text('Aspect ratio'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('lays out at twice the text size', (tester) async {
      await mount(tester, textScale: 2);

      await tap(tester, gear());
      for (final item in ['Aspect ratio', 'Resolution', 'Watermark']) {
        await tap(tester, find.text(item));
        expect(tester.takeException(), isNull, reason: item);
      }

      await unmount(tester);
    });
  });
}
