import 'dart:math' as math;
import 'dart:typed_data';

/// How many amplitude readings are kept per second of audio.
///
/// Chosen against what the timeline can actually draw: at the timeline's 24
/// pixels per second, twenty readings a second gives a bar per pixel, so the
/// lane is fully detailed at the default zoom and degrades by averaging rather
/// than by running out of data if the axis is ever stretched.
///
/// The cost of the choice is what makes it safe to store: one byte per
/// reading is **20 bytes per second, about 1.2KB per audio-minute**. A
/// two-hour project is under 150KB, which is why this can live in the database
/// beside the clip while the 16kHz WAV it came from is still discarded (see
/// the data-layer rule in CLAUDE.md §5). Re-extracting that WAV costs a full
/// native decode; keeping the peaks costs a rounding error.
const int waveformPeaksPerSecond = 20;

/// The largest value a peak can take. One byte per reading, so the lane's
/// height is quantised to 1/255 of the track -- far finer than a pixel.
const int waveformPeakMax = 255;

/// Reduces 16-bit mono PCM to one peak amplitude per bucket.
///
/// **Peak, not average.** A mean over a 50ms bucket pulls every bar towards
/// the middle and flattens exactly the transients that make a waveform legible
/// as speech -- the visible gaps between words are the thing a user scrubs by.
/// Taking the loudest sample in the bucket keeps those edges.
///
/// Returns one byte per bucket scaled to 0..[waveformPeakMax], normalised
/// against the loudest sample in the whole clip so a quietly-recorded clip
/// still fills the lane. Normalisation is deliberate: this is a navigation
/// aid, not a level meter, and a clip that draws as a flat line because it was
/// recorded at -30dB tells the user nothing about where the speech is.
///
/// [pcm] is raw sample bytes with no header -- little-endian signed 16-bit,
/// one channel. Callers holding a whole WAV must seek to `WavHeader.dataOffset`
/// first rather than assuming a 44-byte header.
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
///
/// The stored resolution is fixed but the width a clip occupies is not -- it
/// follows the clip's duration and the zoom. Averaging down (rather than
/// sampling every Nth peak) is what stops a bar pattern from shimmering as the
/// axis changes, because every stored reading contributes to whatever is drawn.
///
/// Returns values in 0..[waveformPeakMax]. An empty [peaks] or a non-positive
/// [width] yields an empty list, which callers draw as a flat lane.
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
