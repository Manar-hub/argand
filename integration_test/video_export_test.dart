import 'dart:io';

import 'package:argand/core/database/database.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/video/export_options.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:argand/features/transcription/video_export_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Video export, driven on a device.
///
/// The request-building and filename rules are covered on the host
/// (`test/video_export_test.dart`). **Nothing about the render itself is
/// provable there**: Media3 `Transformer` is a native encoder, so the only way
/// to know an export works is to produce a file and read it back.
///
/// Requires the fixture pushed first:
///
/// ```
/// adb push alberta.mp4 /data/local/tmp/alberta.mp4
/// ```
///
/// **The output goes to the device's Downloads collection**, which from API 29
/// this app cannot reach with `dart:io` — it is shared storage owned by
/// MediaStore, and an app may only touch what it inserted, through the store.
/// So the assertions here are on the size the store reports back, which is the
/// evidence that bytes actually landed. Seeing the file in Downloads is a check
/// to run from the host:
///
/// ```
/// adb shell ls -la /storage/emulated/0/Download
/// ```
///
/// **Watch memory, not just disk** (`docs/progress.md`, open debt 2). Encoding
/// is the heaviest thing this project runs, and the emulator's 4GB is the
/// binding constraint; a run that installs and then prints no test line at all
/// is the out-of-memory signature, not a hang.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const fixture = '/data/local/tmp/alberta.mp4';

  void log(String message) => debugPrint('VIDEO EXPORT $message');

  late AppDatabase database;
  late TranscriptRepository repository;
  late MediaConverter media;

  setUp(() {
    database = AppDatabase();
    media = MediaConverter();
    repository = TranscriptRepository(database, media);
  });

  tearDown(() => database.close());

  /// Imports the fixture as [count] clips of one project, the way "+" does.
  Future<(String projectId, List<MediaClip> clips)> seed(
    int count, {
    String title = 'export',
  }) async {
    final source = File(fixture);
    expect(
      source.existsSync(),
      isTrue,
      reason: 'adb push alberta.mp4 /data/local/tmp/alberta.mp4 first',
    );

    final projectId = await repository.createEmptyProject(title: title);
    final clips = <MediaClip>[];
    for (var i = 0; i < count; i++) {
      clips.add(
        await repository.addClip(
          projectId: projectId,
          fileName: 'alberta$i.mp4',
          bytes: source.openRead(),
        ),
      );
    }
    return (projectId, clips);
  }

  testWidgets('renders one clip into Downloads', (tester) async {
    final (_, clips) = await seed(1);
    final sourceMs = clips.first.durationMs ?? 0;
    log('source duration ${sourceMs}ms');
    expect(sourceMs, greaterThan(0), reason: 'the fixture must probe');

    final started = DateTime.now();
    final video = await const VideoExporter().export(
      clips: [
        (
          path: clips.first.mediaPath,
          startMs: 0,
          endMs: clips.first.durationMs ?? 0,
          captions: const <ExportCaption>[],
        ),
      ],
      fileName: exportFileName(projectTitle: 'single clip', at: DateTime.now()),
      onProgress: (percent) => log('progress $percent%'),
    );

    final elapsed = DateTime.now().difference(started);
    log('wrote ${video.sizeBytes} bytes to ${video.location} '
        'in ${elapsed.inSeconds}s');

    // **The store's own byte count**, not ours. A row can be created without
    // the bytes ever arriving, and that file appears in Downloads and plays as
    // nothing.
    expect(video.sizeBytes, greaterThan(0));
    expect(video.location, contains('Download'));
    expect(video.name, endsWith('.mp4'));

    expect(
      (video.durationMs - sourceMs).abs(),
      lessThan(1000),
      reason: 'the render should be as long as its source',
    );

    // **Compared as an unordered pair.** An encoder that cannot take the
    // requested portrait size may legitimately encode landscape and set a
    // rotation flag, which displays upright; demanding 1080x1920 here would
    // fail a correct render. What must never happen is the aspect changing.
    expect(
      <int>[video.width, video.height]..sort(),
      <int>[1080, 1920],
      reason: 'the render must not change the shape of the picture',
    );
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('concatenates two clips end to end', (tester) async {
    final (_, clips) = await seed(2);
    final timeline = ProjectTimeline.fromClips(clips);
    log('timeline total ${timeline.totalMs}ms across ${clips.length} clips');

    final video = await const VideoExporter().export(
      clips: [
        for (final clip in clips)
          (
            path: clip.mediaPath,
            startMs: 0,
            endMs: clip.durationMs ?? 0,
            captions: const <ExportCaption>[],
          ),
      ],
      fileName: exportFileName(projectTitle: 'joined', at: DateTime.now()),
      onProgress: (percent) => log('progress $percent%'),
    );

    log('wrote ${video.sizeBytes} bytes to ${video.location}, '
        '${video.durationMs}ms, ${video.width}x${video.height}');
    expect(video.sizeBytes, greaterThan(0));

    // **The assertion that matters for concatenation.** A render that silently
    // dropped the second item would still produce a valid, playable file of a
    // plausible size -- file size is a weak signal here, because a re-encode
    // and a stream copy differ in bitrate by more than a dropped clip does.
    // Duration is what actually separates one clip from two.
    expect(
      (video.durationMs - timeline.totalMs).abs(),
      lessThan(1500),
      reason: 'both clips should be in the output',
    );

    expect(
      <int>[video.width, video.height]..sort(),
      <int>[1080, 1920],
      reason: 'joining must not change the shape of the picture',
    );
  }, timeout: const Timeout(Duration(minutes: 40)));

  testWidgets('the controller names the file after the project',
      (tester) async {
    final (projectId, _) = await seed(1, title: 'My Holiday: Part 2');

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    await container
        .read(videoExportControllerProvider(projectId).notifier)
        .export();

    final state = container.read(videoExportControllerProvider(projectId));
    expect(
      state,
      isA<VideoExportDone>(),
      reason: state is VideoExportFailed ? '${state.error}' : 'did not finish',
    );

    final done = state as VideoExportDone;
    log('controller wrote ${done.video.location} (${done.video.sizeBytes}b)');

    expect(done.video.sizeBytes, greaterThan(0));
    expect(done.video.durationMs, greaterThan(0));
    // The colon is illegal in an Android file name; the title must survive it
    // rather than the export failing on it.
    expect(done.video.name, startsWith('My Holiday Part 2'));
    expect(done.video.name, endsWith('.mp4'));
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('burns captions into the picture', (tester) async {
    final (projectId, clips) = await seed(1, title: 'captioned');

    // **Seeded rather than transcribed.** Running whisper here would add
    // minutes and test the engine, which is covered elsewhere; what this needs
    // is words at times a frame can be checked against.
    await repository.saveClipTranscript(
      projectId: projectId,
      clipId: clips.first.id,
      language: TranscriptionLanguage.english,
      speakerSpans: const [SpeakerSpan(startMs: 0, endMs: 20000, speaker: 0)],
      result: const WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'BURNED CAPTION ONE. BURNED CAPTION TWO.',
        detectedLanguage: 'en',
        segments: [
          // 2s-6s, then a deliberate hole, then 12s-16s. The hole is the
          // point: a frame taken inside it must be clean, which is what shows
          // the overlay is actually being hidden between cues rather than
          // being drawn permanently from the first word onwards.
          WhisperTranscribeSegment(
            fromTs: Duration(seconds: 2),
            toTs: Duration(seconds: 6),
            text: ' BURNED CAPTION ONE.',
          ),
          WhisperTranscribeSegment(
            fromTs: Duration(seconds: 12),
            toTs: Duration(seconds: 16),
            text: ' BURNED CAPTION TWO.',
          ),
        ],
      ),
    );

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    await container
        .read(videoExportControllerProvider(projectId).notifier)
        .export();

    final state = container.read(videoExportControllerProvider(projectId));
    expect(
      state,
      isA<VideoExportDone>(),
      reason: state is VideoExportFailed ? '${state.error}' : 'did not finish',
    );

    final done = state as VideoExportDone;
    log('captioned render at ${done.video.location} '
        '(${done.video.sizeBytes}b, ${done.video.durationMs}ms)');

    expect(done.video.sizeBytes, greaterThan(0));

    // Whether the captions are actually *visible*, in the right place and only
    // during their cue, is not answerable from inside the app -- it needs the
    // pixels. Pull the file and look at frames at 4s and 9s.
  }, timeout: const Timeout(Duration(minutes: 20)));

  /// One caption, on screen for the whole of the short window these framing
  /// tests render, so a pulled frame always has text in it to judge.
  const caption = (
    startMs: 0,
    endMs: 6000,
    text: 'FRAMING CHECK',
    colorArgb: 0xFFFFD54F,
  );

  /// Six seconds is enough to see the crop and cheap enough to encode on the
  /// emulator's software codec, which is the binding constraint here.
  const windowMs = 6000;

  Future<ExportedVideo> render(
    MediaClip clip, {
    required ExportOptions options,
    required String title,
  }) {
    return const VideoExporter().export(
      clips: [
        (
          path: clip.mediaPath,
          startMs: 0,
          endMs: windowMs,
          captions: const <ExportCaption>[caption],
        ),
      ],
      fileName: exportFileName(projectTitle: title, at: DateTime.now()),
      options: options,
      onProgress: (percent) => log('progress $percent%'),
    );
  }

  testWidgets('reframes to the chosen shape, cropping rather than padding',
      (tester) async {
    final (_, clips) = await seed(1, title: 'square');

    final video = await render(
      clips.first,
      title: 'square 720',
      options: const ExportOptions(
        quality: ExportQuality.p720,
        aspect: ExportAspect.square1x1,
      ),
    );

    log('square render ${video.width}x${video.height} at ${video.location}');

    // **Exact, not an unordered pair.** The other tests compare sorted
    // dimensions because a portrait render may legitimately come back
    // landscape-plus-rotation; a square one has no such ambiguity, so this is
    // the assertion that actually proves the reframe happened.
    expect(video.width, 720);
    expect(video.height, 720);
    expect(video.sizeBytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('a quality preset names the short edge', (tester) async {
    final (_, clips) = await seed(1, title: 'portrait');

    final video = await render(
      clips.first,
      title: 'portrait 720',
      // Unbranded, so the pulled frame shows a clean corner beside the
      // branded one from the square render above.
      options: const ExportOptions(
        quality: ExportQuality.p720,
        aspect: ExportAspect.portrait9x16,
      ).withWaiver(const WatermarkWaiver.forTesting()),
    );

    log('portrait render ${video.width}x${video.height} at ${video.location}');

    // 720 across and 1280 down, not 405x720: a person choosing 720p for a reel
    // is asking for the familiar size, not for a sliver.
    expect(<int>[video.width, video.height]..sort(), <int>[720, 1280]);
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('a cancelled render publishes nothing', (tester) async {
    final (_, clips) = await seed(1, title: 'cancelled');

    const exporter = VideoExporter();

    // **The error is caught at creation, not awaited later.** A future that
    // fails while nothing is listening becomes an unhandled zone error, and
    // the test harness reports that as a failure even though the refusal is
    // exactly what this test wants.
    Object? refusal;
    final running = exporter.export(
      clips: [
        (
          path: clips.first.mediaPath,
          startMs: 0,
          endMs: clips.first.durationMs ?? windowMs,
          captions: const <ExportCaption>[],
        ),
      ],
      // Deliberately findable from the host: the check this test cannot make
      // for itself is that Downloads has no file by this name afterwards.
      fileName: 'cancelled run.mp4',
      onProgress: (percent) => log('progress $percent%'),
    ).then<void>((_) {}, onError: (Object error) => refusal = error);

    // Long enough that the encoder is genuinely under way -- cancelling before
    // it starts would prove nothing about tearing a running render down.
    await Future<void>.delayed(const Duration(seconds: 5));
    await exporter.cancel();
    await running;

    expect(refusal, isA<VideoExportException>());
    log('cancelled render refused, as it should');

    // The file is written to the cache and published only on success, so
    // nothing should have reached Downloads. Confirmed from the host:
    // adb shell ls /storage/emulated/0/Download | grep cancelled
  }, timeout: const Timeout(Duration(minutes: 20)));
}
