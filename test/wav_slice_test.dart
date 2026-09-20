import 'dart:io';
import 'dart:typed_data';

import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ramp of 16-bit samples, so a slice can be checked against where it came
/// from rather than only against its length.
Uint8List ramp(int sampleCount) {
  final bytes = Uint8List(sampleCount * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < sampleCount; i++) {
    view.setInt16(i * 2, i % 30000, Endian.little);
  }
  return bytes;
}

/// Writes a canonical 16kHz mono WAV of [ms] milliseconds.
File writeWav(Directory dir, String name, int ms) {
  final samples = 16 * ms; // 16 samples per millisecond at 16kHz.
  final pcm = ramp(samples);
  final file = File('${dir.path}/$name')
    ..writeAsBytesSync([
      ...buildWavHeader(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: pcm.length,
      ),
      ...pcm,
    ]);
  return file;
}

/// The same audio, but with a `LIST` chunk sitting between `fmt ` and `data`.
///
/// **The single most valuable case here.** Encoders routinely write `LIST` or
/// `fact` ahead of `data`, which pushes the samples past the canonical
/// 44-byte offset. An implementation that seeks to a hardcoded 44 passes every
/// other test in this file and slices metadata as if it were audio.
File writeWavWithListChunk(Directory dir, String name, int ms) {
  final pcm = ramp(16 * ms);
  const listPayload = 'INFOISFT      argand test fixture';
  final list = Uint8List.fromList(listPayload.codeUnits);
  final listChunk = <int>[
    ...'LIST'.codeUnits,
    ...(ByteData(4)..setUint32(0, list.length, Endian.little))
        .buffer
        .asUint8List(),
    ...list,
    // RIFF chunks are word-aligned, so an odd-sized one carries a pad byte
    // that is not counted in its declared size. The payload here is
    // deliberately odd so the walk has to skip it -- an implementation that
    // does not lands one byte into `data` and reads every sample shifted.
    if (list.length.isOdd) 0,
  ];

  // `fmt ` is the first 36 bytes of a canonical header; `data` is the last 8.
  final canonical = buildWavHeader(
    sampleRate: 16000,
    channels: 1,
    bitsPerSample: 16,
    dataBytes: pcm.length,
  );
  final fmt = canonical.sublist(0, 36);
  final dataTag = canonical.sublist(36, 44);

  final body = <int>[...fmt.sublist(12), ...listChunk, ...dataTag, ...pcm];
  final riff = <int>[
    ...'RIFF'.codeUnits,
    ...(ByteData(4)..setUint32(0, 4 + body.length, Endian.little))
        .buffer
        .asUint8List(),
    ...'WAVE'.codeUnits,
    ...body,
  ];

  return File('${dir.path}/$name')..writeAsBytesSync(riff);
}

WavHeader headerOf(File file) =>
    WavHeader.parse(file.readAsBytesSync().sublist(0, 1024));

Uint8List samplesOf(File file) {
  final bytes = file.readAsBytesSync();
  final header = WavHeader.parse(bytes.sublist(0, 1024));
  return Uint8List.sublistView(
    bytes,
    header.dataOffset,
    header.dataOffset + header.dataBytes,
  );
}

void main() {
  late Directory dir;
  late MediaConverter converter;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('argand_slice');
    converter = MediaConverter();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('sliceWav', () {
    test('writes exactly the requested range', () async {
      final source = writeWav(dir, 'source.wav', 10000);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 2000,
        endMs: 5000,
      );

      expect(headerOf(slice).duration.inMilliseconds, 3000);
    });

    test('carries the format through unchanged', () async {
      final source = writeWav(dir, 'source.wav', 2000);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 0,
        endMs: 1000,
      );

      final header = headerOf(slice);
      expect(header.sampleRate, 16000);
      expect(header.channels, 1);
      expect(header.bitsPerSample, 16);
    });

    test('takes the samples from where the range actually starts', () async {
      // Length alone would pass even if the slice came from the wrong offset,
      // which is the failure that shows up as a transcript of the wrong words.
      final source = writeWav(dir, 'source.wav', 4000);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 1000,
        endMs: 2000,
      );

      // 1000ms in is sample 16000, and the ramp makes every sample its own
      // index modulo 30000.
      final view = ByteData.sublistView(samplesOf(slice));
      expect(view.getInt16(0, Endian.little), 16000);
      expect(view.getInt16(2, Endian.little), 16001);
    });

    test('finds the samples past a LIST chunk', () async {
      // An implementation that seeks to a constant 44 slices the LIST payload
      // as if it were audio and produces a transcript of noise.
      final source = writeWavWithListChunk(dir, 'listed.wav', 4000);
      expect(headerOf(source).dataOffset, greaterThan(44),
          reason: 'fixture must actually displace the data chunk');

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 1000,
        endMs: 2000,
      );

      final view = ByteData.sublistView(samplesOf(slice));
      expect(view.getInt16(0, Endian.little), 16000);
      expect(headerOf(slice).duration.inMilliseconds, 1000);
    });

    test('clamps a range that runs past the end of the audio', () async {
      // A layer drawn past the end of its media. The tail is the honest
      // answer; failing would make a slightly-too-long layer untranscribable.
      final source = writeWav(dir, 'source.wav', 2000);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 1500,
        endMs: 9000,
      );

      expect(headerOf(slice).duration.inMilliseconds, 500);
    });

    test('refuses a range that is empty once clamped', () async {
      final source = writeWav(dir, 'source.wav', 1000);

      expect(
        () => converter.sliceWav(
          source: source.path,
          destination: '${dir.path}/slice.wav',
          startMs: 5000,
          endMs: 6000,
        ),
        throwsA(isA<AudioExtractionException>()),
      );
    });

    test('refuses a zero-length range', () async {
      final source = writeWav(dir, 'source.wav', 1000);

      expect(
        () => converter.sliceWav(
          source: source.path,
          destination: '${dir.path}/slice.wav',
          startMs: 400,
          endMs: 400,
        ),
        throwsA(isA<AudioExtractionException>()),
      );
    });

    test('refuses a source that is not there', () async {
      expect(
        () => converter.sliceWav(
          source: '${dir.path}/missing.wav',
          destination: '${dir.path}/slice.wav',
          startMs: 0,
          endMs: 1000,
        ),
        throwsA(isA<AudioExtractionException>()),
      );
    });

    test('keeps sample alignment on an odd millisecond boundary', () async {
      // At 16kHz a millisecond is 16 samples, but an odd *byte* offset would
      // shift every sample after it by one and turn speech into noise. The
      // slice must always begin on a whole sample.
      final source = writeWav(dir, 'source.wav', 3000);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 333,
        endMs: 1777,
      );

      expect(headerOf(slice).dataBytes.isEven, isTrue);
      final view = ByteData.sublistView(samplesOf(slice));
      // 333ms is sample 5328 exactly; the ramp proves nothing slid by a byte.
      expect(view.getInt16(0, Endian.little), 5328);
    });

    test('a whole-file range reproduces the audio', () async {
      final source = writeWav(dir, 'source.wav', 1500);

      final slice = await converter.sliceWav(
        source: source.path,
        destination: '${dir.path}/slice.wav',
        startMs: 0,
        endMs: 1500,
      );

      expect(samplesOf(slice), samplesOf(source));
    });
  });
}
