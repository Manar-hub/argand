import 'dart:typed_data';

import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pcm16 <-> float32', () {
    test('round-trips every sample losslessly', () {
      // Endpoints and a few interior values. 16-bit PCM has fewer distinct
      // values than float32 has precision, so the round trip must be exact --
      // if it is not, the denoise pass would degrade audio it chose to leave
      // alone.
      final original = Int16List.fromList(
        [-32768, -32767, -1, 0, 1, 12345, 32766, 32767],
      );
      final bytes = Uint8List.view(original.buffer);

      final restored = float32ToPcm16(pcm16ToFloat32(bytes));

      expect(Int16List.view(restored.buffer), original);
    });

    test('maps full-scale negative to exactly -1.0', () {
      // The reason the scale constant is 2^15 rather than 32767: the signed
      // range is asymmetric, and dividing by the positive bound would put the
      // most negative sample outside -1.0.
      final bytes = Uint8List(2)
        ..buffer.asByteData().setInt16(0, -32768, Endian.little);

      expect(pcm16ToFloat32(bytes).first, -1.0);
    });

    test('clamps out-of-range floats instead of wrapping', () {
      // A speech-enhancement model reconstructs a waveform; it does not
      // promise a range. Wrapping would flip a loud peak to the opposite
      // polarity, which the decoder hears as a click rather than a peak.
      final encoded = float32ToPcm16(Float32List.fromList([2.5, -2.5]));
      final samples = Int16List.view(encoded.buffer);

      expect(samples[0], 32767);
      expect(samples[1], -32768);
    });

    test('ignores a trailing odd byte rather than throwing', () {
      // Callers stream fixed-size blocks and the last one can be short.
      expect(pcm16ToFloat32(Uint8List(5)).length, 2);
    });
  });

  group('buildWavHeader', () {
    test('produces a header WavHeader reads back identically', () {
      final header = buildWavHeader(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 32000,
      );

      expect(header.length, canonicalWavHeaderBytes);

      final parsed = WavHeader.parse(header);
      expect(parsed.sampleRate, 16000);
      expect(parsed.channels, 1);
      expect(parsed.bitsPerSample, 16);
      expect(parsed.dataBytes, 32000);
      expect(parsed.dataOffset, canonicalWavHeaderBytes);
      expect(parsed.duration, const Duration(seconds: 1));
    });

    test('the zero-length placeholder is still a parseable WAV', () {
      // The denoiser writes this before it knows the sample count, then
      // rewrites it. If the placeholder were malformed, a crash mid-pass would
      // leave a file nothing could diagnose.
      final parsed = WavHeader.parse(
        buildWavHeader(
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
          dataBytes: 0,
        ),
      );

      expect(parsed.dataBytes, 0);
      expect(parsed.duration, Duration.zero);
    });

    test('declares a RIFF size consistent with the payload', () {
      // Some decoders trust the RIFF size over the data size. Getting this
      // wrong truncates playback without any parse error to point at it.
      final header = buildWavHeader(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 1000,
      );

      final riffSize =
          ByteData.sublistView(header).getUint32(4, Endian.little);
      expect(riffSize, canonicalWavHeaderBytes - 8 + 1000);
    });
  });
}
