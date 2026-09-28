import 'dart:io';

import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The fork reports the language whisper actually detected.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('LANG $message');

  testWidgets('both auto and pinned report the language actually used',
      (tester) async {
    final media = File('$tmp/two_speakers.wav');
    expect(await media.exists(), isTrue,
        reason: 'adb push two_speakers.wav first');

    final imported = await converter.importToAppStorage(
      projectId: 'detected-language-test',
      clipId: 'clip',
      fileName: 'two_speakers.wav',
      bytes: media.openRead(),
    );

    final model = (await const WhisperModelCatalog().available())
        .firstWhere((m) => m.id == 'base');

    final auto = await WhisperService().transcribeWav(
      imported.path,
      model: model,
      language: TranscriptionLanguage.auto,
      skipSilence: true,
    );
    log('auto   -> detectedLanguage=${auto.detectedLanguage}');

    final pinned = await WhisperService().transcribeWav(
      imported.path,
      model: model,
      language: TranscriptionLanguage.english,
      skipSilence: true,
    );
    log('pinned -> detectedLanguage=${pinned.detectedLanguage}');

    // The clip is English speech, so detection must both fire and be right.
    expect(auto.detectedLanguage, 'en',
        reason: 'auto must report what whisper detected, not the literal '
            'request string');

    expect(pinned.detectedLanguage, 'en',
        reason: 'a pinned language is reported back, so the field always says '
            'which language was used');

    // The value the repository stores. The whole point of the patch is that
    // this is a real code in both modes -- before it, an auto import was saved
    // as the string "auto" and nothing could label the transcript.
    expect(auto.detectedLanguage ?? TranscriptionLanguage.auto.code, 'en');
    expect(pinned.detectedLanguage ?? TranscriptionLanguage.english.code, 'en');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
