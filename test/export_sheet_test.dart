import 'package:argand/core/theme/app_controls.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/theme/app_dialog.dart';
import 'package:argand/core/theme/app_segment_row.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/monetization/placeholder_ad_screen.dart';
import 'package:argand/features/transcription/export_sheet.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// The export sheet, driven by taps over a real in-memory database.
void main() {
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

  /// See `phase6_ui_test.dart`: Drift's stream teardown leaves a zero-length
  /// timer that must fire before the test ends.
  void uiTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      // A phone, not the default 800x600 test window, so the sheet lays out as
      // it does on a device.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  /// A project with one transcribed clip, so every tab has something to offer.
  Future<String> seedTranscribed() async {
    final projectId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: repository.newId(),
      title: 'interview',
      mediaPath: '/tmp/$projectId.mp4',
      duration: const Duration(seconds: 5),
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'Hello there.',
        segments: [
          WhisperTranscribeSegment(
            fromTs: Duration.zero,
            toTs: const Duration(milliseconds: 500),
            text: ' Hello',
          ),
          WhisperTranscribeSegment(
            fromTs: const Duration(milliseconds: 500),
            toTs: const Duration(seconds: 1),
            text: ' there.',
          ),
        ],
      ),
    );
    return projectId;
  }

  /// Opens the sheet from a button and remembers what it returned.
  Future<({ExportDecision? Function() result, int Function() shown})> open(
    WidgetTester tester,
    String projectId, {
    bool online = true,
    bool watchesToEnd = true,
  }) async {
    ExportDecision? result;
    var shown = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          rewardedAdsProvider.overrideWithValue(
            PlaceholderRewardedAds(
              probe: () async => online,
              present: (_) async {
                shown++;
                return watchesToEnd;
              },
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async =>
                      result = await showExportSheet(context, projectId),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);

    return (result: () => result, shown: () => shown);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Finder primaryButton(String label) =>
      find.widgetWithText(AppDialogButton, label);

  uiTest('offers the four formats across the top', (tester) async {
    await open(tester, await seedTranscribed());

    for (final label in ['Video', 'SRT', 'VTT', 'Pro formats']) {
      expect(find.text(label), findsOneWidget);
    }
    // Get Pro is in view before the export, whatever the tab.
    expect(find.text('Get Pro'), findsOneWidget);
  });

  uiTest('without the toggle, the video exports branded', (tester) async {
    final sheet = await open(tester, await seedTranscribed());

    await tapVisible(tester, primaryButton('Export'));

    final decision = sheet.result() as VideoExportDecision;
    expect(decision.options.watermark, isTrue);
    expect(sheet.shown(), 0, reason: 'no ad was asked for');
  });

  uiTest('offline, the watermark cannot be switched off', (tester) async {
    final sheet = await open(tester, await seedTranscribed(), online: false);

    await tapVisible(tester, find.byType(AppToggle));

    expect(tester.widget<AppToggle>(find.byType(AppToggle)).value, isFalse);
    expect(
      find.text("Couldn't load the ad — the watermark stays on."),
      findsOneWidget,
    );
    // And the button still exports -- branded, which is the free path.
    await tapVisible(tester, primaryButton('Export'));
    expect((sheet.result() as VideoExportDecision).options.watermark, isTrue);
  });

  uiTest('the ad plays before export, and finishing it removes the watermark',
      (tester) async {
    final sheet = await open(tester, await seedTranscribed());

    await tapVisible(tester, find.byType(AppToggle));
    expect(primaryButton('Watch ad, then export'), findsOneWidget);

    await tapVisible(tester, primaryButton('Watch ad, then export'));

    expect(sheet.shown(), 1);
    final decision = sheet.result() as VideoExportDecision;
    expect(decision.options.watermark, isFalse);
  });

  uiTest('closing the ad early exports nothing', (tester) async {
    final sheet = await open(
      tester,
      await seedTranscribed(),
      watchesToEnd: false,
    );

    await tapVisible(tester, find.byType(AppToggle));
    await tapVisible(tester, primaryButton('Watch ad, then export'));

    expect(sheet.shown(), 1);
    expect(sheet.result(), isNull, reason: 'the sheet is still open');
    expect(
      find.text('Watch the ad to the end to remove the watermark.'),
      findsOneWidget,
    );
  });

  uiTest('a connection lost after choosing still keeps the watermark',
      (tester) async {
    // Online when the toggle is flipped, gone by the time Export is tapped:
    // the ad's own answer decides, not the earlier check.
    var online = true;
    ExportDecision? result;
    var shown = 0;
    final projectId = await seedTranscribed();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          rewardedAdsProvider.overrideWithValue(
            PlaceholderRewardedAds(
              probe: () async => online,
              present: (_) async {
                shown++;
                return true;
              },
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showExportSheet(context, projectId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    await tapVisible(tester, find.byType(AppToggle));
    online = false;
    await tapVisible(tester, primaryButton('Watch ad, then export'));

    expect(shown, 0);
    expect(result, isNull);
    expect(tester.widget<AppToggle>(find.byType(AppToggle)).value, isFalse);
  });

  uiTest('SRT carries the chosen line length', (tester) async {
    final sheet = await open(tester, await seedTranscribed());

    await tapVisible(tester, find.text('SRT'));
    await tapVisible(tester, find.text('Short'));
    await tapVisible(tester, primaryButton('Export'));

    final decision = sheet.result() as SubtitleExportDecision;
    expect(decision.format, SubtitleFormat.srt);
    expect(decision.lineLength, SubtitleLineLength.short);
    expect(decision.includeSpeakers, isTrue);
  });

  uiTest('with nothing transcribed, the subtitle tabs cannot export',
      (tester) async {
    final projectId = await repository.createEmptyProject(title: 'empty');
    await open(tester, projectId);

    await tapVisible(tester, find.text('VTT'));

    final button = tester.widget<FilledButton>(
      find.descendant(
        of: primaryButton('Export'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  uiTest('the tab row stays put when the tab changes', (tester) async {
    // Sized to its content, the sheet shrank on a shorter tab and the row slid
    // down, so the next tap on a tab landed above the sheet and closed it.
    await open(tester, await seedTranscribed());
    final row = find.byWidgetPredicate((widget) => widget is AppSegmentRow);
    final onVideo = tester.getRect(row);

    await tapVisible(tester, find.text('SRT'));
    expect(tester.getRect(row), onVideo);

    await tapVisible(tester, find.text('Pro formats'));
    expect(tester.getRect(row), onVideo);
    expect(primaryButton('Get Pro'), findsOneWidget, reason: 'still open');
  });

  uiTest('the Pro formats tab offers Pro, not an export', (tester) async {
    await open(tester, await seedTranscribed());

    await tapVisible(tester, find.text('Pro formats'));

    expect(primaryButton('Export'), findsNothing);
    expect(primaryButton('Get Pro'), findsOneWidget);
    expect(find.text('Coming with Pro'), findsNWidgets(3));
  });
}
