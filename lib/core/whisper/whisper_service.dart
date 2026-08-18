import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

part 'whisper_service.g.dart';

/// Wraps whisper_ggml_plus for on-device transcription.
///
/// Talks to the package's lower-level [Whisper] API rather than
/// [WhisperController.transcribe] because that convenience method hardcodes
/// `isRealtime: true` even for file input, and doesn't expose `noFallback`
/// (the toggle for this project's locked temperature_inc=0.0 param) --
/// see docs/engine-architecture.md.
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

  /// Transcribes an already-prepared 16kHz mono WAV file.
  Future<WhisperTranscribeResponse> transcribeWav(String wavPath) async {
    await ensureModelReady();

    final whisper = Whisper(model: _model);
    return whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        threads: _lockedThreads,
        splitOnWord: true,
        noFallback: true,
        isRealtime: false,
        // Package bug workaround: with splitOnWord true, the Dart-side VAD
        // resolver (bundled_vad_model_resolver.dart) deliberately leaves
        // vadModelPath null since VAD doesn't apply, but the native JSON
        // layer requires vad_model_path to always be a string and throws
        // `type_error.302` on a JSON null. An empty string satisfies it
        // without re-enabling VAD.
        vadModelPath: '',
      ),
      modelPath: await _modelPath(),
    );
  }
}

@Riverpod(keepAlive: true)
WhisperService whisperService(Ref ref) => WhisperService();
