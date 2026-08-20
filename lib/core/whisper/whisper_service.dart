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
///
/// Talks to the package's lower-level [Whisper] API rather than
/// [WhisperController.transcribe] for two reasons:
///
///  * Model paths. [WhisperController.getPath] builds the filename from the
///    package's `WhisperModel` enum, a closed set with no value for the
///    quantized `small-q5_1` build that is already bundled here -- nor for the
///    optional downloadable models planned for Tier 2. This service takes a
///    [WhisperModelDescriptor] instead, so which model runs is a runtime
///    choice rather than something baked in at compile time.
///  * Locked inference parameters. The controller defaults to 6 threads and
///    does not surface the params this project pins in
///    docs/engine-architecture.md.
class WhisperService {
  static const int _lockedThreads = 4;

  /// The enum value is inert: [Whisper.transcribe] takes an explicit
  /// `modelPath` and never reads this field. The constructor requires one, so
  /// it is pinned to a constant rather than tracked alongside the selected
  /// model -- keeping them in sync would imply a relationship that does not
  /// exist.
  Whisper get _whisper => const Whisper(model: WhisperModel.base);

  /// Where [model] lives once copied out of the app bundle.
  ///
  /// Same directory the package's own resolver used, so switching to this did
  /// not strand a model an earlier build had already copied. Each model keeps
  /// its own filename, so switching back and forth does not re-copy.
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
    // asset API, so the copy cannot be chunked. `asUint8List` below is a view
    // rather than a second copy, which keeps the peak to roughly one model.
    // Worth revisiting before shipping anything larger.
    final asset = await rootBundle.load(model.assetKey);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
  }

  /// Progress of the running transcription, 0-100.
  ///
  /// Reads a native atomic, so this is safe to poll from the UI isolate while
  /// [transcribeWav] runs. It stays a poll rather than a stream because the
  /// forked `progress_callback` fires on the inference isolate and writes to
  /// that atomic; there is no channel back to Dart to push from. The import
  /// pipeline samples it, see `ImportController`.
  int get progressPercent => _whisper.getProgress();

  /// Transcribes an already-prepared 16kHz mono WAV file using [model].
  ///
  /// [language] is required rather than defaulted. The package's own default
  /// is `'en'`, and taking it silently was a real bug: every file was declared
  /// English regardless of content, with nothing in the output to show for it.
  /// Forcing the caller to name a language keeps that decision visible — and
  /// the two it can name are exactly the user-facing choice, detection or
  /// pinned English.
  ///
  /// [skipSilence] turns on whisper.cpp's built-in Silero VAD, which decodes
  /// only the speech regions of the file and maps the resulting timestamps
  /// back onto the original timeline. The vendored fork had to be patched to
  /// permit this alongside `splitOnWord`; see docs/engine-architecture.md.
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
        noFallback: true,
        suppressNst: true,
        samplingStrategy: 'greedy',
        splitOnWord: true,
        language: language.code,
        // `enabled` rather than `auto`: auto silently degrades to no VAD if
        // the bundled model cannot be prepared, and a setting the user turned
        // on should fail loudly instead of quietly not applying.
        vadMode: skipSilence ? WhisperVadMode.enabled : WhisperVadMode.disabled,
        // Left null so the package resolves its own bundled Silero model. The
        // Phase 0 workaround that passed '' here is gone: the fork's json_get
        // helper tolerates null, and '' would now read as "no model" and make
        // `enabled` throw.
      ),
      modelPath: await modelPath(model),
    );
  }
}

@Riverpod(keepAlive: true)
WhisperService whisperService(Ref ref) => WhisperService();
