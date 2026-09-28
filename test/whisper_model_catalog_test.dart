import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/features/transcription/transcription_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a model file dropped into assets/models', () {
    test("is listed under whisper.cpp's own name", () {
      expect(WhisperModelCatalog.modelIdOf('ggml-base.bin'), 'base');
      expect(WhisperModelCatalog.modelIdOf('ggml-small-q5_1.bin'), 'small-q5_1');
    });

    test('and under the whisper-<size>.gguf name converters give it', () {
      expect(
        WhisperModelCatalog.modelIdOf('whisper-medium-q4_0.gguf'),
        'medium-q4_0',
      );
      expect(WhisperModelCatalog.modelIdOf('ggml-large-v3.gguf'), 'large-v3');
    });

    test('the other models in the folder are not whisper models', () {
      expect(
        WhisperModelCatalog.modelIdOf('pyannote-segmentation-3.0.onnx'),
        isNull,
      );
      expect(WhisperModelCatalog.modelIdOf('gtcrn_simple.onnx'), isNull);
      expect(WhisperModelCatalog.modelIdOf('ggml-.bin'), isNull);
      expect(WhisperModelCatalog.modelIdOf('sub/ggml-base.bin'), isNull);
    });

    test('an unnamed model reads by its size', () {
      expect(readableModelId('medium-q4_0'), 'Medium (q4_0)');
      expect(readableModelId('tiny'), 'Tiny');
      expect(readableModelId('large-v3-turbo'), 'Large (v3-turbo)');
    });
  });
}
