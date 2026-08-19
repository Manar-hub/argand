import 'dart:io';

import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device checks for the parts of the pipeline that only exist natively.
///
/// `flutter test` cannot cover any of this: `audio_decoder` is a thin shim
/// over MediaCodec/AVFoundation and whisper.cpp is an FFI call into a native
/// library, so both are absent from the host VM.
///
/// Fixtures are pushed to `/data/local/tmp` before running, see
/// docs/progress.md for the exact commands.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const videoFixture = '/data/local/tmp/speech_test.mp4';
  const quicktimeFixture = '/data/local/tmp/speech_test.mov';
  const heAacFixture = '/data/local/tmp/speech_test_heaac.mp4';
  const audioFixture = '/data/local/tmp/test_speech.wav';

  final converter = MediaConverter();

  Future<File> stage(String fixture, String projectId) async {
    final source = File(fixture);
    expect(
      await source.exists(),
      isTrue,
      reason: 'Missing fixture $fixture -- push it with adb first.',
    );
    return converter.importToAppStorage(
      projectId: projectId,
      fileName: fixture.split('/').last,
      bytes: source.openRead(),
    );
  }

  /// Converts [fixture] and asserts the result is genuinely transcribable.
  ///
  /// The duration comparison is the point. A wrong resampling ratio still
  /// yields a valid 16kHz mono header -- only the sample *count* betrays it,
  /// which is exactly how an HE-AAC extraction bug reached a release build
  /// unnoticed. See docs/engine-architecture.md.
  Future<void> expectTranscribableExtraction(
    String fixture,
    String projectId,
  ) async {
    final media = await stage(fixture, projectId);
    final wav = await converter.extractWavForTranscription(media.path);

    expect(await wav.exists(), isTrue);
    final header = WavHeader.parse(await wav.readAsBytes());

    expect(header.sampleRate, 16000);
    expect(header.channels, 1);
    expect(header.bitsPerSample, 16);
    expect(header.dataBytes, greaterThan(0));

    final sourceDuration = await converter.probeDuration(media.path);
    expect(
      sourceDuration,
      isNotNull,
      reason: 'Cannot verify extraction without a source duration',
    );

    final driftMs =
        (header.duration - sourceDuration!).abs().inMilliseconds;
    final allowedMs = (sourceDuration.inMilliseconds * 0.02).clamp(500, 1 << 30);
    expect(
      driftMs,
      lessThanOrEqualTo(allowedMs),
      reason: 'Extracted ${header.duration.inMilliseconds}ms from a '
          '${sourceDuration.inMilliseconds}ms source -- the decoder and the '
          'container disagree about the audio format.',
    );
  }

  tearDown(() async {
    for (final id in ['itest-video', 'itest-mov', 'itest-heaac', 'itest-audio']) {
      await converter.discardProjectMedia(id);
    }
  });

  testWidgets('extracts a 16kHz mono 16-bit WAV from an .mp4 video',
      (tester) async {
    await expectTranscribableExtraction(videoFixture, 'itest-video');
  });

  testWidgets('extracts the same WAV format from a .mov container',
      (tester) async {
    // `.mov` is absent from audio_decoder's own recognized-extension list,
    // which is why MediaConverter never consults that list. This test pins
    // down that the native decoder handles the container regardless.
    await expectTranscribableExtraction(quicktimeFixture, 'itest-mov');
  });

  testWidgets('extracts at the right rate from HE-AAC video', (tester) async {
    // Regression test. HE-AAC carries SBR, so MediaExtractor reports the AAC
    // core sample rate while MediaCodec decodes to double it. Deriving the
    // resampling ratio from the container instead of the decoder produced
    // audio at half speed and twice the length -- valid, and useless.
    await expectTranscribableExtraction(heAacFixture, 'itest-heaac');
  });

  testWidgets('reports a duration for a video container', (tester) async {
    final media = await stage(videoFixture, 'itest-video');
    final duration = await converter.probeDuration(media.path);

    expect(duration, isNotNull);
    expect(duration!.inMilliseconds, greaterThan(0));
  });

  testWidgets('transcribes a converted file end to end', (tester) async {
    final media = await stage(audioFixture, 'itest-audio');
    final wav = await converter.extractWavForTranscription(media.path);

    // Resolves to the default bundled model, matching a fresh install.
    final model = await const WhisperModelCatalog().resolve(null);
    expect(model, isNotNull, reason: 'No model is bundled in this build');

    final result = await WhisperService().transcribeWav(wav.path, model: model!);

    expect(result.text.trim(), isNotEmpty);
    final segments = result.segments ?? const [];
    expect(segments, isNotEmpty);

    // `splitOnWord: true` means one word per segment, and timings must not
    // run backwards -- tap-to-seek and caption grouping both depend on it.
    var previous = -1;
    for (final segment in segments) {
      expect(segment.fromTs.inMilliseconds, greaterThanOrEqualTo(previous));
      previous = segment.fromTs.inMilliseconds;
    }
  });
}
