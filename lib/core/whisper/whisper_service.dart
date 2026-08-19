import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

part 'whisper_service.g.dart';

/// Wraps whisper_ggml_plus for on-device transcription.
///
/// Talks to the package's lower-level [Whisper] API rather than
/// [WhisperController.transcribe] for two reasons:
///
///  * Model paths. [WhisperController.getPath] derives the filename from the
///    package's `WhisperModel` enum, a closed set that cannot represent the
///    optional downloadable models planned for Tier 2. This service owns its
///    own path resolution instead.
///  * Locked inference parameters. The controller defaults to 6 threads and
///    does not surface the params this project pins in
///    docs/engine-architecture.md.
class WhisperService {
  static const WhisperModel _model = WhisperModel.base;
  static const int _lockedThreads = 4;

  Future<String> _modelPath() => WhisperController().getPath(_model);

  Future<void> ensureModelReady() async {
    final file = File(await _modelPath());
    if (await file.exists()) return;

    final asset = await rootBundle.load('assets/models/ggml-${_model.modelName}.bin');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
  }

  /// Progress of the running transcription, 0-100.
  ///
  /// Reads a native atomic, so this is safe to poll from the UI isolate
  /// while [transcribeWav] runs. Phase 1 turns this into a proper stream on
  /// the service API; polling directly is a Phase 0.5 stopgap.
  int get progressPercent => Whisper(model: _model).getProgress();

  /// Transcribes an already-prepared 16kHz mono WAV file.
  Future<WhisperTranscribeResponse> transcribeWav(String wavPath) async {
    await ensureModelReady();

    final whisper = Whisper(model: _model);
    return whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        // Locked parameters, docs/engine-architecture.md. These are only
        // honoured because the vendored fork wires them through to
        // whisper.cpp; upstream silently ignored all but `threads`.
        threads: _lockedThreads,
        noFallback: true,
        suppressNst: true,
        samplingStrategy: 'greedy',
        splitOnWord: true,
      ),
      modelPath: await _modelPath(),
    );
  }
}

@Riverpod(keepAlive: true)
WhisperService whisperService(Ref ref) => WhisperService();
