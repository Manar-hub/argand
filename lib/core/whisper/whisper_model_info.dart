import 'dart:io';
import 'dart:typed_data';

/// What a whisper.cpp model file says about itself, read from its header -- how
/// the model screen tells a new model is ready to run before anything is
/// transcribed with it.
class WhisperModelInfo {
  const WhisperModelInfo({
    required this.audioLayers,
    required this.audioState,
    required this.mels,
    required this.vocabulary,
    required this.fileType,
  });

  /// `'ggml'` as a little-endian u32.
  static const _magic = 0x67676d6c;
  static const _headerBytes = 4 + 11 * 4;

  final int audioLayers;
  final int audioState;

  /// 80 for every model before large-v3, 128 from it.
  final int mels;
  final int vocabulary;

  /// ggml's `ftype`, the weights' format.
  final int fileType;

  /// The family, from the encoder's depth, as whisper.cpp names them.
  String get size => switch (audioLayers) {
        4 => 'tiny',
        6 => 'base',
        12 => 'small',
        24 => 'medium',
        32 => 'large',
        _ => '$audioLayers-layer',
      };

  /// The weights' format -- `f16`, `q5_1` ... -- or null for one this does
  /// not name. The quantisation version is folded in by thousands.
  String? get format => switch (fileType % 1000) {
        0 => 'f32',
        1 => 'f16',
        2 => 'q4_0',
        3 => 'q4_1',
        7 => 'q8_0',
        8 => 'q5_0',
        9 => 'q5_1',
        _ => null,
      };

  /// Reads the header of the model at [path]; null when it is not a whisper
  /// model this engine can load.
  static Future<WhisperModelInfo?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final raf = await file.open();
    try {
      return parse(await raf.read(_headerBytes));
    } finally {
      await raf.close();
    }
  }

  /// [bytes], the start of a model file; null unless it is a whisper header
  /// with sensible values.
  static WhisperModelInfo? parse(Uint8List bytes) {
    if (bytes.length < _headerBytes) return null;
    final data = ByteData.sublistView(bytes);
    int at(int index) => data.getInt32(4 + index * 4, Endian.little);
    if (data.getUint32(0, Endian.little) != _magic) return null;
    final info = WhisperModelInfo(
      vocabulary: at(0),
      audioState: at(2),
      audioLayers: at(4),
      mels: at(9),
      fileType: at(10),
    );
    final plausible = info.vocabulary > 50000 &&
        info.vocabulary < 60000 &&
        info.audioLayers > 0 &&
        info.audioLayers <= 64 &&
        (info.mels == 80 || info.mels == 128);
    return plausible ? info : null;
  }
}
