import 'dart:typed_data';

/// Conversions between the two ways this project has to hold audio.
///
/// On disk everything is 16-bit signed PCM inside a RIFF/WAVE container, which
/// is what whisper.cpp reads and what `audio_decoder` writes. In memory the
/// ONNX models take `Float32List` normalised to roughly -1.0..1.0. Neither
/// side is negotiable, so the conversion is a fixed cost of running any
/// model over an extracted WAV.
///
/// Deliberately free functions over plain typed data: nothing here touches the
/// filesystem or FFI, so it is fully testable on the host VM.

/// Scale between the two representations.
///
/// 32768 (2^15), not 32767: the signed 16-bit range is asymmetric (-32768 to
/// 32767), and dividing by the negative bound is what maps full-scale negative
/// samples to exactly -1.0. This is also the constant whisper.cpp and
/// sherpa-onnx use internally, so a round trip through both agrees.
const double _pcm16Scale = 32768.0;

/// Decodes little-endian 16-bit PCM into normalised floats.
///
/// [bytes] must hold whole samples; a trailing odd byte is ignored rather than
/// throwing, because callers stream fixed-size blocks whose final one may be
/// short.
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
///
/// Exists so a caller that already knows the total sample count can allocate
/// the [Float32List] once and stream into it. The alternative — reading the
/// whole file to a [Uint8List] and calling [pcm16ToFloat32] — holds the bytes
/// *and* the floats at the same time, which for a 30-minute recording is an
/// extra ~58MB on top of the ~115MB that has to exist anyway.
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
///
/// Clamps rather than wrapping. A speech-enhancement model can return samples
/// slightly outside -1.0..1.0 — it reconstructs a waveform, it does not
/// promise a range — and an unclamped conversion would wrap those to the
/// opposite polarity, turning a loud peak into a click the decoder hears as a
/// consonant.
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
///
/// [dataBytes] may be zero when the length is not yet known: write the
/// placeholder, stream the samples, then seek back to offset 0 and write this
/// again with the real total. That two-pass approach is what keeps memory flat
/// for an arbitrarily long file — the alternative is buffering every sample
/// just to learn how many there were.
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
