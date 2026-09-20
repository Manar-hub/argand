import 'dart:typed_data';

import 'package:argand/core/audio/waveform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds little-endian signed 16-bit PCM from [samples].
Uint8List pcm(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

void main() {
  group('peaksFromPcm16', () {
    test('produces one reading per bucket', () {
      // 1000Hz at 10 peaks/second is 100 samples per bucket; 500 samples is
      // five whole buckets.
      final peaks = peaksFromPcm16(
        pcm(List.filled(500, 1000)),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      expect(peaks, hasLength(5));
    });

    test('a partial final bucket still draws a bar', () {
      // Two and a bit buckets. The remainder must round up, or the lane would
      // be shorter than the clip it sits under.
      final peaks = peaksFromPcm16(
        pcm(List.filled(250, 1000)),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      expect(peaks, hasLength(3));
    });

    test('takes the bucket peak, not its mean', () {
      // One loud sample among 99 silent ones. A mean would bury it; the whole
      // point of the lane is that it does not.
      final loud = List.filled(100, 0)..[50] = 20000;
      final quiet = List.filled(100, 5000);

      final peaks = peaksFromPcm16(
        pcm([...loud, ...quiet]),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      // Normalised against 20000, so the spike is full height and the steady
      // 5000 bucket is a quarter of it.
      expect(peaks[0], waveformPeakMax);
      expect(peaks[1], closeTo(waveformPeakMax * 5000 / 20000, 1));
    });

    test('normalises against the loudest sample in the clip', () {
      // Recorded 20dB down. It must still fill the lane -- this is a
      // navigation aid, not a level meter.
      final peaks = peaksFromPcm16(
        pcm([...List.filled(100, 300), ...List.filled(100, 150)]),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      expect(peaks[0], waveformPeakMax);
      expect(peaks[1], closeTo(waveformPeakMax / 2, 1));
    });

    test('silence yields zeroed readings rather than a division by zero', () {
      final peaks = peaksFromPcm16(
        pcm(List.filled(200, 0)),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      expect(peaks, hasLength(2));
      expect(peaks.every((p) => p == 0), isTrue);
    });

    test('handles the most-negative sample without overflowing', () {
      // -32768 negated is still -32768 in two's complement. Left unclamped
      // this makes `loudest` negative and every bar comes out wrong.
      final peaks = peaksFromPcm16(
        pcm([...List.filled(100, -32768), ...List.filled(100, 16384)]),
        sampleRate: 1000,
        peaksPerSecond: 10,
      );

      expect(peaks[0], waveformPeakMax);
      expect(peaks[1], closeTo(waveformPeakMax / 2, 2));
    });

    test('tolerates a truncated trailing byte', () {
      final bytes = pcm(List.filled(100, 1000));
      final odd = Uint8List.sublistView(bytes, 0, bytes.length - 1);

      expect(
        peaksFromPcm16(odd, sampleRate: 1000, peaksPerSecond: 10),
        hasLength(1),
      );
    });

    test('empty input yields no readings', () {
      expect(
        peaksFromPcm16(Uint8List(0), sampleRate: 16000),
        isEmpty,
      );
    });

    test('a nonsensical rate yields no readings rather than throwing', () {
      expect(peaksFromPcm16(pcm([1, 2, 3]), sampleRate: 0), isEmpty);
      expect(
        peaksFromPcm16(pcm([1, 2, 3]), sampleRate: 16000, peaksPerSecond: 0),
        isEmpty,
      );
    });
  });

  group('resamplePeaks', () {
    test('averages when narrowing', () {
      final peaks = Uint8List.fromList([0, 100, 200, 0]);

      expect(resamplePeaks(peaks, 2), [50, 100]);
    });

    test('repeats the covering reading when widening', () {
      // Widening past the stored resolution must not draw zeros between the
      // real readings -- that would look like silence that is not there.
      final peaks = Uint8List.fromList([10, 20]);

      expect(resamplePeaks(peaks, 4), [10, 10, 20, 20]);
    });

    test('an exact match is returned unchanged', () {
      final peaks = Uint8List.fromList([1, 2, 3]);

      expect(resamplePeaks(peaks, 3), [1, 2, 3]);
    });

    test('every stored reading contributes when narrowing', () {
      // Sampling every Nth reading instead of averaging would drop the spike
      // entirely and the lane would shimmer as the axis changed.
      final peaks = Uint8List.fromList([0, 0, 0, 255]);

      expect(resamplePeaks(peaks, 1), [63]);
    });

    test('degenerate inputs yield an empty lane', () {
      expect(resamplePeaks(Uint8List(0), 10), isEmpty);
      expect(resamplePeaks(Uint8List.fromList([1, 2]), 0), isEmpty);
      expect(resamplePeaks(Uint8List.fromList([1, 2]), -1), isEmpty);
    });
  });
}
