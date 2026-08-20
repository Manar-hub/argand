import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../media/wav_codec.dart';
import '../media/wav_header.dart';

part 'audio_denoiser.g.dart';

/// Thrown when the noise-suppression pass could not produce usable audio.
///
/// Deliberately not a silent fallback to the unprocessed WAV. A caller asked
/// for enhanced audio; handing back the original under the same name would
/// look like success and be indistinguishable from it. Whether that is fatal
/// to the wider operation is the caller's call.
class AudioDenoiseException implements Exception {
  const AudioDenoiseException(this.message);

  final String message;

  @override
  String toString() => 'AudioDenoiseException: $message';
}

/// Runs GTCRN speech enhancement over a 16kHz mono WAV.
///
/// **This is deliberately NOT wired into the Tier 1 transcription pipeline.**
/// It was, and was measured: on already-clean speech it substituted correct
/// words for wrong ones ("real life" -> "marine life"), because it
/// reconstructs the waveform rather than merely selecting from it. What it did
/// fix — a whisper.cpp repetition loop on unclear audio — is handled instead by
/// voice activity detection, which cannot corrupt the samples it keeps and is
/// faster besides. See docs/progress.md, Phase 2, for both A/B results, and
/// [SilenceSkippingEnabled] for what replaced it.
///
/// It is kept, tested and ready because it still answers a question VAD cannot:
/// speech that is *continuously* noisy has no silence to skip, and whisper's
/// internal representations remain noise-variant. That is the standalone
/// "clean up my audio" feature, which is **Tier 2** — do not re-wire this into
/// the transcription path to get there.
///
/// **Why the streaming denoiser for a batch pipeline.** sherpa-onnx also
/// exposes `OfflineSpeechDenoiser`, which takes an entire waveform in one
/// call. At 16kHz mono float32 that is ~230MB of Dart heap for a one-hour
/// recording, before the returned copy — untenable on a phone, and CLAUDE.md 2
/// makes resource cost a correctness concern rather than a later optimisation.
/// `OnlineSpeechDenoiser` consumes fixed-size chunks and is fed straight from
/// disk into a file sink, so peak memory is a few kilobytes regardless of how
/// long the recording is. The model and its output are identical either way.
class AudioDenoiser {
  /// GTCRN, ~48K parameters — small enough that cost was never the reason it
  /// left the transcription pipeline. Accuracy was. See the class doc.
  static const String modelFileName = 'gtcrn_simple.onnx';
  static const String modelAssetKey = 'assets/models/$modelFileName';

  /// GTCRN is trained at 16kHz, which is also whisper.cpp's required rate, so
  /// the whole pipeline shares one rate and no resampling is needed anywhere
  /// in this pass.
  static const int requiredSampleRate = 16000;

  /// Where the model lives once copied out of the bundle.
  ///
  /// sherpa-onnx loads by filesystem path, and Flutter assets are not files —
  /// they live inside the package archive — so a copy is unavoidable. At
  /// ~536KB this is nothing like the whisper model copy, which has to
  /// materialise ~148MB in memory to do the same job.
  Future<String> modelPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, modelFileName);
  }

  Future<void> ensureModelReady() async {
    final file = File(await modelPath());
    if (await file.exists()) return;

    final asset = await rootBundle.load(modelAssetKey);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
  }

  /// Denoises [wavPath] and returns the enhanced copy alongside it.
  ///
  /// The input is written to a new file rather than replaced in place, so a
  /// failure part-way through cannot destroy the extracted audio and leave the
  /// import with nothing to fall back to. How long the result is kept is the
  /// caller's policy, not this class's — see `ImportController`.
  Future<File> denoiseWav(String wavPath) async {
    await ensureModelReady();
    // Resolved out here, not inside the isolate: `getApplicationSupportDirectory`
    // is a platform-channel call, and platform channels exist only on the
    // isolate that owns the Flutter engine. Everything the isolate body needs
    // is therefore reduced to plain strings first.
    final model = await modelPath();
    final outputPath = p.setExtension(wavPath, '.denoised.wav');

    // Isolate.run keeps ONNX inference off the UI isolate. Note that the FFI
    // bindings are per-isolate state in sherpa-onnx — initialising them here
    // would not make them visible in there — which is why _runDenoisePass
    // calls initBindings itself.
    await Isolate.run(
      () => _runDenoisePass(
        inputPath: wavPath,
        outputPath: outputPath,
        modelPath: model,
      ),
    );

    return File(outputPath);
  }
}

/// The whole pass, running on a background isolate.
///
/// Streams input WAV -> float32 chunk -> GTCRN -> 16-bit PCM -> output WAV,
/// never holding more than one chunk of either representation.
void _runDenoisePass({
  required String inputPath,
  required String outputPath,
  required String modelPath,
}) {
  // Per-isolate FFI state: sherpa-onnx resolves its native symbols into
  // isolate-local storage, so every isolate that calls the API has to do this
  // once. Cheap — it is a dlopen of an already-loaded library.
  sherpa.initBindings();

  final input = File(inputPath).openSync();
  RandomAccessFile? output;
  sherpa.OnlineSpeechDenoiser? denoiser;

  try {
    final header = WavHeader.parse(input.readSync(4096));
    if (header.sampleRate != AudioDenoiser.requiredSampleRate ||
        header.channels != 1 ||
        header.bitsPerSample != 16) {
      throw AudioDenoiseException(
        'Noise suppression needs ${AudioDenoiser.requiredSampleRate}Hz mono '
        '16-bit audio but was given ${header.sampleRate}Hz/'
        '${header.channels}ch/${header.bitsPerSample}-bit.',
      );
    }

    denoiser = sherpa.OnlineSpeechDenoiser(
      sherpa.OnlineSpeechDenoiserConfig(
        model: sherpa.OfflineSpeechDenoiserModelConfig(
          gtcrn: sherpa.OfflineSpeechDenoiserGtcrnModelConfig(model: modelPath),
          // One thread. GTCRN runs far faster than real time at this size, and
          // the four threads whisper is pinned to are the ones that matter for
          // total import time; spending more here would only contend with the
          // decode work that follows.
          numThreads: 1,
          // The package defaults this to true, which writes an onnxruntime
          // session dump to logcat on every import.
          debug: false,
          provider: 'cpu',
        ),
      ),
    );

    // The model dictates its own chunk size. Feeding it anything else works
    // but makes the native side re-buffer, and a mismatched chunk is the usual
    // cause of clicks at frame boundaries in enhanced audio.
    final frameShift = denoiser.frameShiftInSamples;
    if (frameShift <= 0) {
      throw const AudioDenoiseException(
        'Denoiser reported no frame size; the model failed to load.',
      );
    }

    output = File(outputPath).openSync(mode: FileMode.write);
    // Placeholder: the true sample count is not known until the last chunk has
    // been flushed, so the header is rewritten at the end.
    output.writeFromSync(
      buildWavHeader(
        sampleRate: AudioDenoiser.requiredSampleRate,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 0,
      ),
    );

    final chunkBytes = frameShift * 2;
    var remaining = header.dataBytes;
    var written = 0;
    input.setPositionSync(header.dataOffset);

    while (remaining > 0) {
      final wanted = remaining < chunkBytes ? remaining : chunkBytes;
      final raw = input.readSync(wanted);
      // A `data` chunk size can overstate what the file actually holds if the
      // writer was interrupted. Stop at the real end rather than looping.
      if (raw.isEmpty) break;
      remaining -= raw.length;

      final denoised = denoiser.run(
        samples: pcm16ToFloat32(raw),
        sampleRate: AudioDenoiser.requiredSampleRate,
      );
      written += _appendSamples(output, denoised.samples);
    }

    // Drains the model's internal lookahead buffer. Skipping this truncates
    // the tail of the recording — a few hundred milliseconds, which is easily
    // a whole final word.
    written += _appendSamples(output, denoiser.flush().samples);

    if (written == 0) {
      throw const AudioDenoiseException(
        'Noise suppression produced no audio.',
      );
    }

    output.setPositionSync(0);
    output.writeFromSync(
      buildWavHeader(
        sampleRate: AudioDenoiser.requiredSampleRate,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: written,
      ),
    );
  } on FormatException catch (error) {
    throw AudioDenoiseException(
      'Noise suppression could not read its input: ${error.message}',
    );
  } finally {
    denoiser?.free();
    output?.closeSync();
    input.closeSync();
  }
}

/// Appends [samples] to [output] as 16-bit PCM, returning the bytes written.
int _appendSamples(RandomAccessFile output, Float32List samples) {
  if (samples.isEmpty) return 0;
  final bytes = float32ToPcm16(samples);
  output.writeFromSync(bytes);
  return bytes.lengthInBytes;
}

@Riverpod(keepAlive: true)
AudioDenoiser audioDenoiser(Ref ref) => AudioDenoiser();
