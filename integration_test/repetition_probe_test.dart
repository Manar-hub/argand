import 'dart:io';

import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:argand/core/text/repetition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Diagnostic, not a pass/fail test.
///
/// **The question it answers.** `guess.mp4` transcribes correctly until a burst
/// of laughter, at which point the decoder emits a "ha ha ha" loop and the real
/// speech in that window is never transcribed. The same audio through stock
/// `whisper-cli` is clean.
///
/// That bounds the problem hard: the audio is transcribable, the model can
/// transcribe it, and the default parameters handle laughter correctly. So the
/// loop comes from one of *our* deviations from those defaults — `temperature_inc`
/// 0.2 -> 0.0 (via `noFallback`), `suppress_nst` false -> true,
/// `split_on_word`/`max_len` false/0 -> true/1, and VAD off -> on.
///
/// The mechanism is visible in the source. `main.cpp:321-324` turns `noFallback`
/// into `temperature_inc = 0.0f`; `whisper.cpp:6868` then builds a
/// single-element temperature ladder; and `whisper.cpp:7565` gates the whole
/// quality check on `it != temperatures.size() - 1`, which with one temperature
/// is never true. The entropy detector at `whisper.cpp:7541` still fires and
/// still sets `decoder.failed` — its verdict is simply never read. **whisper.cpp
/// detects the loop and then discards the detection.**
///
/// **Run one test at a time**, cheapest first:
///
/// ```
/// flutter test integration_test/repetition_probe_test.dart -d <dev> --plain-name locate
/// flutter test integration_test/repetition_probe_test.dart -d <dev> --plain-name ladder
/// ```
///
/// Reads a **pre-extracted WAV** and a model **already on disk**, both from
/// `/data/local/tmp`. Neither is an optimisation detail: making the probe
/// convert the 39MB `.mp4` itself, and copy a 148MB model out of the asset
/// bundle, cost half an hour before the first measurement and is what this
/// rewrite removes.
///
/// ```
/// adb push guesswav.wav            /data/local/tmp/guess.wav
/// adb push assets/models/ggml-base.bin /data/local/tmp/ggml-base.bin
/// ```
///
/// It changes nothing that ships: `WhisperService.transcribeWav` hard-codes the
/// locked parameters, so this builds its own [TranscribeRequest] and calls
/// [Whisper.transcribe] directly rather than widening that signature.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const wavFixture = '/data/local/tmp/guess.wav';
  const modelFixture = '/data/local/tmp/ggml-base.bin';

  /// Window the `ladder` test measures on, so the matrix runs on the few
  /// seconds that actually fail rather than the whole file. Set from what
  /// `locate` reports. Null means the whole file.
  const sliceStartMs = null;
  const sliceEndMs = null;

  void log(String message) => debugPrint('REP $message');

  /// Writes samples [startMs, endMs) of [source] into a new 16kHz mono WAV.
  Future<File> slice(File source, int startMs, int endMs) async {
    final bytes = await source.readAsBytes();
    final header = WavHeader.parse(bytes);
    final blockAlign = header.channels * (header.bitsPerSample ~/ 8);
    final bytesPerMs = header.sampleRate * blockAlign / 1000;

    // Rounded to whole frames; a partial frame would shift every sample.
    var from = (startMs * bytesPerMs).floor() ~/ blockAlign * blockAlign;
    var to = (endMs * bytesPerMs).ceil() ~/ blockAlign * blockAlign;
    if (from < 0) from = 0;
    if (to > header.dataBytes) to = header.dataBytes;

    final payload = Uint8List.sublistView(
      bytes,
      header.dataOffset + from,
      header.dataOffset + to,
    );
    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, 'rep-slice.wav'));
    await out.writeAsBytes([
      ...buildWavHeader(
        sampleRate: header.sampleRate,
        channels: header.channels,
        bitsPerSample: header.bitsPerSample,
        dataBytes: payload.length,
      ),
      ...payload,
    ]);
    return out;
  }

  /// Runs one configuration and reports what came out.
  ///
  /// Words are derived by splitting every segment on whitespace rather than
  /// assuming one segment per word, so a `splitOnWord: false` row is measured
  /// on the same footing as the rest.
  Future<void> run(
    String wavPath,
    String label, {
    bool noFallback = true,
    bool suppressNst = true,
    String samplingStrategy = 'greedy',
    bool vad = true,
    bool splitOnWord = true,
    String modelPath = modelFixture,
    bool dumpAll = false,
  }) async {
    log('$label | starting...');
    final watch = Stopwatch()..start();
    final result = await const Whisper(model: WhisperModel.base).transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        threads: 4,
        // Matches the app's default language setting.
        language: 'auto',
        noFallback: noFallback,
        suppressNst: suppressNst,
        samplingStrategy: samplingStrategy,
        splitOnWord: splitOnWord,
        vadMode: vad ? WhisperVadMode.enabled : WhisperVadMode.disabled,
      ),
      modelPath: modelPath,
    );
    watch.stop();

    final segments = result.segments ?? const <WhisperTranscribeSegment>[];
    final words = <({String text, int startMs})>[];
    for (final segment in segments) {
      for (final token in segment.text.trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        words.add((text: token, startMs: segment.fromTs.inMilliseconds));
      }
    }

    final texts = [for (final w in words) w.text];
    final runs = findRepetitions(texts);
    final worst = findWorstRepetition(texts);

    log('$label | ${watch.elapsed.inSeconds}s words=${texts.length} '
        'segments=${segments.length} loops=${runs.length} '
        'ratio=${repetitionRatio(texts).toStringAsFixed(4)} '
        'worst=${worst ?? "none"}');

    // Dump each loop's neighbourhood, so "did the real speech come back?" is
    // answerable from this log rather than by re-running.
    for (final loop in runs) {
      final from = (loop.startIndex - 12).clamp(0, texts.length);
      final to = (loop.endIndex + 12).clamp(0, texts.length);
      log('$label |   loop at ${words[loop.startIndex].startMs}ms $loop');
      log('$label |   ...${texts.sublist(from, to).join(" ")}...');
    }

    if (dumpAll) {
      final buffer = StringBuffer();
      for (final word in words) {
        buffer.write('${word.text} ');
      }
      log('$label | FULL: ${buffer.toString().trim()}');
    }
  }

  testWidgets(
    'locate: reproduce the loop and time one pass',
    (tester) async {
      final wav = File(wavFixture);
      expect(await wav.exists(), isTrue,
          reason: 'Missing $wavFixture -- adb push it first');
      expect(await File(modelFixture).exists(), isTrue,
          reason: 'Missing $modelFixture -- adb push it first');

      final header = WavHeader.parse(await wav.readAsBytes());
      log('fixture ${header.sampleRate}Hz ch=${header.channels} '
          'bits=${header.bitsPerSample} duration=${header.duration}');

      await run(wav.path, 'A shipped', dumpAll: true);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'ladder: one deviation reverted at a time',
    (tester) async {
      final source = File(wavFixture);
      expect(await source.exists(), isTrue);

      var wav = source;
      if (sliceStartMs != null && sliceEndMs != null) {
        wav = await slice(source, sliceStartMs, sliceEndMs);
        log('sliced $sliceStartMs-${sliceEndMs}ms -> ${wav.path}');
      }

      await run(wav.path, 'A shipped');
      await run(wav.path, 'B fallback', noFallback: false);
      await run(wav.path, 'C nst-off', suppressNst: false);
      await run(wav.path, 'D beam', samplingStrategy: 'beam');
      await run(wav.path, 'E vad-off', vad: false);
      await run(wav.path, 'F fallback+nst',
          noFallback: false, suppressNst: false);
      await run(wav.path, 'G no-splitword', splitOnWord: false);
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
