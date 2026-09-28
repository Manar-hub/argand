import 'dart:typed_data';

/// Conversions between the two ways this project has to hold audio.

/// Scale between the two representations.
const double _pcm16Scale = 32768.0;

/// Decodes little-endian 16-bit PCM into normalised floats.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final sampleCount = bytes.lengthInBytes ~/ 2;
  final view = ByteData.sublistView(bytes);
  final out = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / _pcm16Scale;
  }
  return out;
}

/// Decodes [bytes] into [out] starting at [outOffset], returning how many
/// samples were written.
int pcm16ToFloat32Into(Uint8List bytes, Float32List out, int outOffset) {
  final available = bytes.lengthInBytes ~/ 2;
  final room = out.length - outOffset;
  final writable = available < room ? available : room;
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < writable; i++) {
    out[outOffset + i] = view.getInt16(i * 2, Endian.little) / _pcm16Scale;
  }
  return writable;
}

/// Encodes normalised floats back to little-endian 16-bit PCM.
Uint8List float32ToPcm16(Float32List samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples.length; i++) {
    final scaled = (samples[i] * _pcm16Scale).round();
    view.setInt16(i * 2, scaled.clamp(-32768, 32767), Endian.little);
  }
  return out;
}

/// Number of bytes in a canonical RIFF/WAVE header, which is what
/// [buildWavHeader] emits. Callers streaming samples reserve this much space
/// up front and rewrite it once the final length is known.
const int canonicalWavHeaderBytes = 44;

/// Builds a 44-byte canonical RIFF/WAVE header.
Uint8List buildWavHeader({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int dataBytes,
}) {
  final header = Uint8List(canonicalWavHeaderBytes);
  final view = ByteData.sublistView(header);
  final blockAlign = channels * (bitsPerSample ~/ 8);

  _writeTag(header, 0, 'RIFF');
  // Everything after this field: the 4-byte 'WAVE' tag plus both chunk
  // headers plus the samples.
  view.setUint32(4, canonicalWavHeaderBytes - 8 + dataBytes, Endian.little);
  _writeTag(header, 8, 'WAVE');

  _writeTag(header, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM fmt chunk body size
  view.setUint16(20, 1, Endian.little); // format tag: uncompressed PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * blockAlign, Endian.little); // byte rate
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);

  _writeTag(header, 36, 'data');
  view.setUint32(40, dataBytes, Endian.little);

  return header;
}

void _writeTag(Uint8List bytes, int offset, String tag) {
  for (var i = 0; i < tag.length; i++) {
    bytes[offset + i] = tag.codeUnitAt(i);
  }
}
