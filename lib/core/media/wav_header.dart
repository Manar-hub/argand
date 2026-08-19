import 'dart:typed_data';

/// The parts of a RIFF/WAVE header this project needs to verify.
///
/// Exists because a WAV can be perfectly well-formed and still be wrong: the
/// header describes a format, and nothing guarantees the samples underneath
/// were produced at that rate. Comparing [duration] against the source media's
/// own duration is what catches that.
class WavHeader {
  const WavHeader({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataBytes,
  });

  final int channels;
  final int sampleRate;
  final int bitsPerSample;

  /// Length of the `data` chunk in bytes.
  final int dataBytes;

  /// How long the samples actually run for, derived from the data size rather
  /// than from any duration field.
  Duration get duration {
    final bytesPerSecond = sampleRate * channels * (bitsPerSample ~/ 8);
    if (bytesPerSecond <= 0) return Duration.zero;
    return Duration(microseconds: (dataBytes * 1000000) ~/ bytesPerSecond);
  }

  /// Parses the leading header of a RIFF/WAVE file.
  ///
  /// Only the header is needed, so callers can hand over the first few hundred
  /// bytes instead of a whole multi-megabyte file.
  ///
  /// Throws [FormatException] if this is not a WAV or the required chunks are
  /// missing.
  static WavHeader parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('Too short to be a WAV file');
    }
    final data = ByteData.sublistView(bytes);
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataBytes;

    // Chunks are walked rather than read at fixed offsets: encoders are free to
    // put LIST or fact chunks ahead of `data`, so its position is not fixed.
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = _tag(bytes, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (id == 'fmt ' && body + 16 <= bytes.length) {
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataBytes = size;
        break;
      }

      // Chunks are word-aligned, so an odd size carries one padding byte.
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (channels == null || sampleRate == null || bitsPerSample == null) {
      throw const FormatException('WAV file has no fmt chunk');
    }
    if (dataBytes == null) {
      throw const FormatException('WAV file has no data chunk');
    }

    return WavHeader(
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      dataBytes: dataBytes,
    );
  }

  static String _tag(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  @override
  String toString() =>
      'WavHeader(${sampleRate}Hz, ${channels}ch, $bitsPerSample-bit, '
      '$dataBytes bytes, ${duration.inMilliseconds}ms)';
}
