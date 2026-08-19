import 'dart:typed_data';

import 'package:argand/core/media/wav_header.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a canonical 44-byte RIFF/WAVE header followed by [dataBytes] of
/// silence, optionally with an extra chunk before `data`.
Uint8List buildWav({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int dataBytes,
  bool withListChunk = false,
}) {
  final builder = BytesBuilder();
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);

  void tag(String value) => builder.add(value.codeUnits);
  void uint32(int value) =>
      builder.add(Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little));
  void uint16(int value) =>
      builder.add(Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little));

  tag('RIFF');
  uint32(36 + dataBytes);
  tag('WAVE');
  tag('fmt ');
  uint32(16);
  uint16(1);
  uint16(channels);
  uint32(sampleRate);
  uint32(byteRate);
  uint16(channels * (bitsPerSample ~/ 8));
  uint16(bitsPerSample);
  if (withListChunk) {
    // An odd-sized chunk, so the parser's word-alignment padding is exercised.
    tag('LIST');
    uint32(5);
    builder.add(Uint8List(6));
  }
  tag('data');
  uint32(dataBytes);
  builder.add(Uint8List(dataBytes));

  return builder.toBytes();
}

void main() {
  group('WavHeader', () {
    test('reads format and derives duration from the data size', () {
      // One second of 16kHz mono 16-bit audio.
      final bytes = buildWav(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 32000,
      );

      final header = WavHeader.parse(bytes);

      expect(header.sampleRate, 16000);
      expect(header.channels, 1);
      expect(header.bitsPerSample, 16);
      expect(header.dataBytes, 32000);
      expect(header.duration, const Duration(seconds: 1));
    });

    test('finds the data chunk behind an intervening chunk', () {
      final bytes = buildWav(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 16000,
        withListChunk: true,
      );

      final header = WavHeader.parse(bytes);

      expect(header.dataBytes, 16000);
      expect(header.duration, const Duration(milliseconds: 500));
    });

    test('duration exposes a wrong-ratio resample that the header hides', () {
      // The HE-AAC failure: the header says 16kHz mono, and it is telling the
      // truth about the format. There are simply twice as many samples as the
      // source had, because the resampler used half the correct ratio.
      final bytes = buildWav(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 32000 * 2,
      );

      final header = WavHeader.parse(bytes);

      expect(header.sampleRate, 16000, reason: 'format looks correct');
      expect(header.duration, const Duration(seconds: 2));
    });

    test('rejects data that is not a WAV', () {
      expect(
        () => WavHeader.parse(Uint8List.fromList('not a wav file!!'.codeUnits)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a truncated file', () {
      expect(
        () => WavHeader.parse(Uint8List.fromList('RI'.codeUnits)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
