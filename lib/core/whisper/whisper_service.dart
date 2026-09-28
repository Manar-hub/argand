import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'transcription_language_controller.dart';
import 'whisper_model_catalog.dart';

part 'whisper_service.g.dart';

/// Wraps whisper_ggml_plus for on-device transcription.
class WhisperService {
  static const int _lockedThreads = 4;

  /// The enum value is inert: [Whisper.transcribe] takes an explicit
  /// `modelPath` and never reads this field.
  Whisper get _whisper => const Whisper(model: WhisperModel.base);

  /// Where [model] lives once copied out of the app bundle.
  Future<String> modelPath(WhisperModelDescriptor model) async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, model.fileName);
  }

  /// Copies [model] out of the bundle on first use.
  Future<void> ensureModelReady(WhisperModelDescriptor model) async {
    final file = File(await modelPath(model));
    if (await file.exists()) return;

    // Note: this materialises the whole model in memory before writing --
    // ~148MB for base, ~190MB for small-q5_1. Flutter exposes no streaming
    // asset API, so the copy cannot be chunked.
    final asset = await rootBundle.load(model.assetKey);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
  }

  /// Progress of the running transcription, 0-100.
  int get progressPercent => _whisper.getProgress();

  /// Transcribes an already-prepared 16kHz mono WAV file using [model].
  Future<WhisperTranscribeResponse> transcribeWav(
    String wavPath, {
    required WhisperModelDescriptor model,
    required TranscriptionLanguage language,
    required bool skipSilence,
  }) async {
    await ensureModelReady(model);

    return _whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        // Locked parameters, docs/engine-architecture.md. These are only
        // honoured because the vendored fork wires them through to
        // whisper.cpp; upstream silently ignored all but `threads`.
        threads: _lockedThreads,
        // Was `true`, which pinned decoding to a single temperature and was the
        // direct cause of the "ha ha ha" repetition loops.
        noFallback: false,
        suppressNst: true,
        samplingStrategy: 'greedy',
        splitOnWord: true,
        language: language.code,
        // `enabled` rather than `auto`: auto silently degrades to no VAD if
        // the bundled model cannot be prepared, and a setting the user turned
        // on should fail loudly instead of quietly not applying.
        vadMode: skipSilence ? WhisperVadMode.enabled : WhisperVadMode.disabled,
        // Left null so the package resolves its own bundled Silero model.
      ),
      modelPath: await modelPath(model),
    );
  }
}

@Riverpod(keepAlive: true)
WhisperService whisperService(Ref ref) => WhisperService();
