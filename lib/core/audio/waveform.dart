import 'dart:math' as math;
import 'dart:typed_data';

/// How many amplitude readings are kept per second of audio.
const int waveformPeaksPerSecond = 20;

/// The largest value a peak can take. One byte per reading, so the lane's
/// height is quantised to 1/255 of the track -- far finer than a pixel.
const int waveformPeakMax = 255;

/// Reduces 16-bit mono PCM to one peak amplitude per bucket.
Uint8List peaksFromPcm16(
  Uint8List pcm, {
  required int sampleRate,
  int peaksPerSecond = waveformPeaksPerSecond,
}) {
  if (sampleRate <= 0 || peaksPerSecond <= 0) return Uint8List(0);

  final samples = Int16List.sublistView(
    // An odd trailing byte is a truncated final sample, not an error worth
    // failing a whole clip's lane over. Drop it.
    pcm.length.isEven ? pcm : Uint8List.sublistView(pcm, 0, pcm.length - 1),
  );
  if (samples.isEmpty) return Uint8List(0);

  final samplesPerBucket = sampleRate ~/ peaksPerSecond;
  if (samplesPerBucket <= 0) return Uint8List(0);

  // Round up, so a partial final bucket still produces a bar. Dropping it
  // would shorten the lane against the clip it sits under, and the two must
  // measure the same axis.
  final bucketCount = (samples.length + samplesPerBucket - 1) ~/ samplesPerBucket;
  final raw = Uint16List(bucketCount);

  var loudest = 0;
  for (var bucket = 0; bucket < bucketCount; bucket++) {
    final start = bucket * samplesPerBucket;
    final end = math.min(start + samplesPerBucket, samples.length);

    var peak = 0;
    for (var i = start; i < end; i++) {
      // -32768 has no positive counterpart in a signed 16-bit range, so
      // negating it overflows back to itself. Clamp before taking magnitude.
      final sample = samples[i];
      final magnitude = sample == -32768 ? 32767 : sample.abs();
      if (magnitude > peak) peak = magnitude;
    }

    raw[bucket] = peak;
    if (peak > loudest) loudest = peak;
  }

  final out = Uint8List(bucketCount);
  // Digital silence: every bar is zero, and scaling by it would divide by
  // zero. A flat empty lane is the correct picture of a silent clip.
  if (loudest == 0) return out;

  for (var bucket = 0; bucket < bucketCount; bucket++) {
    out[bucket] = (raw[bucket] * waveformPeakMax / loudest).round();
  }
  return out;
}

/// Resamples [peaks] onto exactly [width] buckets for drawing.
List<int> resamplePeaks(Uint8List peaks, int width) {
  if (peaks.isEmpty || width <= 0) return const [];
  if (peaks.length == width) return peaks;

  final out = List<int>.filled(width, 0);
  for (var i = 0; i < width; i++) {
    final start = i * peaks.length ~/ width;
    var end = (i + 1) * peaks.length ~/ width;
    // Widening past the stored resolution: several output bars map to one
    // reading and `start == end`. Draw that reading rather than a zero.
    if (end <= start) end = start + 1;

    var total = 0;
    for (var j = start; j < end && j < peaks.length; j++) {
      total += peaks[j];
    }
    out[i] = total ~/ (math.min(end, peaks.length) - start);
  }
  return out;
}
