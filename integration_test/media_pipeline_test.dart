import 'dart:io';

import 'package:argand/core/audio/audio_denoiser.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
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
  // Two speakers in conversation, from sherpa-onnx's speaker-segmentation-models
  // release. Nothing else on the device has more than one voice.
  const twoSpeakerFixture = '/data/local/tmp/two_speakers.wav';

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

    final result = await WhisperService().transcribeWav(
      wav.path,
      model: model!,
      language: TranscriptionLanguage.auto,
      skipSilence: true,
    );

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

  testWidgets('noise suppression returns audio the engine still accepts',
      (tester) async {
    final media = await stage(audioFixture, 'itest-denoise');
    final wav = await converter.extractWavForTranscription(media.path);
    final source = WavHeader.parse(await wav.readAsBytes());

    final denoised = await AudioDenoiser().denoiseWav(wav.path);

    expect(await denoised.exists(), isTrue);
    expect(
      denoised.path,
      isNot(wav.path),
      reason: 'The extracted WAV must survive the pass for a fallback to exist',
    );
    expect(await wav.exists(), isTrue);

    final header = WavHeader.parse(await denoised.readAsBytes());

    // Format has to survive untouched: whisper.cpp takes no sample-rate
    // argument, it assumes 16kHz, so a denoiser that quietly changed the rate
    // would be transcribed at the wrong speed rather than rejected.
    expect(header.sampleRate, 16000);
    expect(header.channels, 1);
    expect(header.bitsPerSample, 16);
    expect(header.dataBytes, greaterThan(0));

    // The duration assertion, not the format one, is what catches a real bug
    // here -- the same lesson the HE-AAC extraction failure taught. A dropped
    // flush() truncates the tail, and a chunking error stretches or shortens
    // the whole file, neither of which touches the header.
    final drift = (header.duration - source.duration).abs();
    expect(
      drift,
      lessThan(const Duration(milliseconds: 250)),
      reason: 'Denoised audio ran for ${header.duration.inMilliseconds}ms '
          'against a ${source.duration.inMilliseconds}ms input',
    );

    await denoised.delete();
  });

  testWidgets('transcribes denoised audio end to end', (tester) async {
    final media = await stage(audioFixture, 'itest-denoise-asr');
    final wav = await converter.extractWavForTranscription(media.path);
    final denoised = await AudioDenoiser().denoiseWav(wav.path);

    final model = await const WhisperModelCatalog().resolve(null);
    expect(model, isNotNull, reason: 'No model is bundled in this build');

    final result = await WhisperService().transcribeWav(
      denoised.path,
      model: model!,
      language: TranscriptionLanguage.auto,
      skipSilence: true,
    );

    // Deliberately not asserting the *text*. Whether denoising helps or hurts
    // word error rate on a given clip is the open question this phase leaves
    // for measurement (docs/progress.md); what a test can pin down is that the
    // pass produces something the engine can still decode into timed words.
    expect(result.text.trim(), isNotEmpty);
    expect(result.segments ?? const [], isNotEmpty);

    await denoised.delete();
  });

  /// The assertion that gates the VAD fork patch.
  ///
  /// With VAD on, whisper.cpp decodes a *compacted* buffer containing only the
  /// speech runs, then maps the resulting times back through
  /// `state->vad_mapping_table`. Upstream refused to allow this alongside
  /// `splitOnWord` at all, on the grounds that word output "requires stable
  /// timestamps". This test is what makes removing that guard defensible:
  /// if the remap were broken, word times would land on the compacted
  /// timeline and run off the end of the media.
  testWidgets('silence skipping keeps word times on the original timeline',
      (tester) async {
    final media = await stage(audioFixture, 'itest-vad-timeline');
    final wav = await converter.extractWavForTranscription(media.path);
    final duration = await converter.probeDuration(media.path);
    expect(duration, isNotNull, reason: 'Fixture duration is needed to bound times');

    final model = await const WhisperModelCatalog().resolve(null);
    expect(model, isNotNull, reason: 'No model is bundled in this build');

    final result = await WhisperService().transcribeWav(
      wav.path,
      model: model!,
      language: TranscriptionLanguage.english,
      skipSilence: true,
    );

    final segments = result.segments ?? const [];
    expect(segments, isNotEmpty, reason: 'VAD dropped a clip that is mostly speech');

    // A little slack: whisper pads speech regions by speech_pad_ms and rounds
    // to centiseconds, so a final word may legitimately end fractionally past
    // the container's own duration.
    final limit = duration! + const Duration(milliseconds: 500);

    var previous = -1;
    for (final segment in segments) {
      expect(
        segment.fromTs.inMilliseconds,
        greaterThanOrEqualTo(previous),
        reason: 'Word times went backwards, so the VAD remap is not monotonic',
      );
      expect(
        segment.toTs,
        lessThanOrEqualTo(limit),
        reason: 'Word ends at ${segment.toTs.inMilliseconds}ms but the media is '
            'only ${duration.inMilliseconds}ms -- times are on the compacted '
            'VAD timeline, not the original one',
      );
      previous = segment.fromTs.inMilliseconds;
    }
  });

  testWidgets('silence skipping suppresses speech invented over silence',
      (tester) async {
    // Pinned English on near-silent audio is whisper.cpp's classic
    // hallucination case -- it emits a stray "you". VAD should find no speech
    // to decode at all, so there is nothing for it to invent over.
    final media = await stage(quicktimeFixture, 'itest-vad-silence');
    final wav = await converter.extractWavForTranscription(media.path);

    final model = await const WhisperModelCatalog().resolve(null);
    final result = await WhisperService().transcribeWav(
      wav.path,
      model: model!,
      language: TranscriptionLanguage.english,
      skipSilence: true,
    );

    expect(
      result.segments ?? const [],
      isEmpty,
      reason: 'Expected no speech in a silent clip, got "${result.text.trim()}"',
    );
  });

  testWidgets('diarization separates two speakers', (tester) async {
    final media = await stage(twoSpeakerFixture, 'itest-diarize');
    final wav = await converter.extractWavForTranscription(media.path);
    final source = WavHeader.parse(await wav.readAsBytes());

    final spans = await SpeakerDiarizer().diarize(wav.path);

    expect(spans, isNotNull, reason: 'Fixture is far under the duration cap');
    expect(spans!, isNotEmpty);

    final speakers = spans.map((s) => s.speaker).toSet();
    expect(
      speakers.length,
      greaterThanOrEqualTo(2),
      reason: 'A two-speaker recording collapsed to ${speakers.length} '
          'speaker(s) -- clustering threshold is merging voices',
    );

    // Spans must be ordered and inside the media, for the same reason word
    // timestamps must be: anything downstream (caption colouring, tap-to-seek)
    // treats these as positions on the real timeline.
    for (final span in spans) {
      expect(span.startMs, greaterThanOrEqualTo(0));
      expect(span.endMs, greaterThan(span.startMs));
      expect(
        span.endMs,
        lessThanOrEqualTo(source.duration.inMilliseconds + 500),
        reason: 'Span runs past the end of the audio',
      );
    }

    // Sorted ascending by start, which diarize() guarantees.
    final starts = spans.map((s) => s.startMs).toList();
    final sorted = [...starts]..sort();
    expect(starts, sorted);
  });

  testWidgets('diarization declines a file past the duration cap', (tester) async {
    // A header claiming far more audio than the cap allows. The guard is
    // checked before any allocation, so this never reads samples -- which is
    // exactly the behaviour being pinned: refuse cheaply rather than OOM.
    final overCap = SpeakerDiarizer.maxDuration + const Duration(minutes: 1);
    final declaredBytes = overCap.inMilliseconds * 16000 * 2 ~/ 1000;

    final dir = await Directory.systemTemp.createTemp('itest-cap');
    final file = File('${dir.path}/oversized.wav');
    await file.writeAsBytes(
      buildWavHeader(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: declaredBytes,
      ),
    );

    final spans = await SpeakerDiarizer().diarize(file.path);

    expect(
      spans,
      isNull,
      reason: 'Files over the cap must return null, not throw and not attempt '
          'a ${declaredBytes ~/ 1048576}MB allocation',
    );

    await dir.delete(recursive: true);
  });

  testWidgets('diarization reports progress through a bound callback',
      (tester) async {
    // Regression test for a bug the other diarization tests could not catch,
    // because they all call diarize() with no onProgress. A Dart closure
    // captures its whole enclosing scope, so passing a callback that is a
    // *method on an object* dragged that object's unsendable fields into the
    // isolate message. Isolate.run then failed before running any of the body,
    // and since diarization is non-fatal the import quietly saved with no
    // speakers -- indistinguishable from diarization finding nothing.
    //
    // The callback here is deliberately a bound instance method, not a bare
    // closure over an int, because that is the shape that broke.
    final collector = _ProgressCollector();

    final media = await stage(twoSpeakerFixture, 'itest-diarize-progress');
    final wav = await converter.extractWavForTranscription(media.path);

    final spans = await SpeakerDiarizer().diarize(
      wav.path,
      onProgress: collector.record,
    );

    expect(spans, isNotNull, reason: 'Diarization must survive a callback');
    expect(spans!, isNotEmpty);
    expect(
      collector.values,
      isNotEmpty,
      reason: 'No progress was reported, so the callback never reached the '
          'native pass',
    );
    for (final value in collector.values) {
      expect(value, inInclusiveRange(0, 100));
    }
  });
}

/// Holds state the way a real caller does, so `record` is a bound method whose
/// receiver has fields — the condition that triggered the original failure.
class _ProgressCollector {
  final List<int> values = [];
  Future<void>? _unsendable;

  void record(int percent) {
    _unsendable ??= Future<void>.value();
    values.add(percent);
  }
}
