import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'wav_codec.dart';
import 'wav_header.dart';

part 'media_converter.g.dart';

/// Thrown when audio extraction produced a file the engine must not be fed.
class AudioExtractionException implements Exception {
  const AudioExtractionException(this.message);

  final String message;

  @override
  String toString() => 'AudioExtractionException: $message';
}

/// Turns an arbitrary picked media file into the 16kHz mono 16-bit PCM WAV that
/// whisper.cpp requires, using native OS decoders (MediaCodec on Android,
/// AVFoundation on iOS) via the `audio_decoder` package.
class MediaConverter {
  /// whisper.cpp's required input format. Not configurable.
  static const int _targetSampleRate = 16000;
  static const int _targetChannels = 1;
  static const int _targetBitDepth = 16;

  /// Writes [bytes] into app-owned storage for one clip, preserving
  /// [fileName]'s extension, and returns the new file.
  Future<File> importToAppStorage({
    required String projectId,
    required String clipId,
    required String fileName,
    required Stream<List<int>> bytes,
  }) async {
    final dir = await _clipDir(projectId, clipId);

    final destination = File(p.join(dir.path, 'source${p.extension(fileName)}'));
    // Streamed rather than buffered: video files routinely run to hundreds of
    // megabytes, which is more than a phone will hand over as one allocation.
    final sink = destination.openWrite();
    try {
      await sink.addStream(bytes);
    } finally {
      await sink.close();
    }
    return destination;
  }

  /// Takes ownership of a file already on disk, moving it if it can.
  Future<File> adoptIntoAppStorage({
    required String projectId,
    required String clipId,
    required String fileName,
    required File source,
  }) async {
    final dir = await _clipDir(projectId, clipId);

    final destination = File(p.join(dir.path, 'source${p.extension(fileName)}'));

    try {
      return await source.rename(destination.path);
    } on FileSystemException {
      await source.openRead().pipe(destination.openWrite());
      // Best-effort: the import has succeeded by this point, and a stranded
      // cache file is the OS's to reclaim rather than a reason to fail.
      try {
        await source.delete();
      } catch (_) {}
      return destination;
    }
  }

  /// Extracts [mediaPath]'s audio track as a 16kHz mono WAV alongside it.
  Future<File> extractWavForTranscription(
    String mediaPath, {
    String? destination,
  }) async {
    // The default path is fixed, which also makes it not re-entrant: two runs
    // against one clip would write the same file.
    final output = File(destination ?? p.setExtension(mediaPath, '.16k.wav'));

    // Converted unconditionally, and deliberately not gated on
    // `AudioDecoder.needsConversion`.
    await AudioDecoder.convertToWav(
      mediaPath,
      output.path,
      sampleRate: _targetSampleRate,
      channels: _targetChannels,
      bitDepth: _targetBitDepth,
    );

    await _verifyTranscribableWav(output, sourcePath: mediaPath);
    return output;
  }

  /// How far the extracted audio may drift from the source's own duration.
  static const Duration _durationFloor = Duration(milliseconds: 500);
  static const double _durationTolerance = 0.02;

  /// Fails the import unless [wav] is genuinely what whisper.cpp expects.
  Future<void> _verifyTranscribableWav(
    File wav, {
    required String sourcePath,
  }) async {
    if (!await wav.exists()) {
      throw const AudioExtractionException('Audio extraction produced no file');
    }

    // Only the header is needed, so the whole file is never read into memory.
    final handle = await wav.open();
    final Uint8List head;
    try {
      head = await handle.read(4096);
    } finally {
      await handle.close();
    }

    final WavHeader header;
    try {
      header = WavHeader.parse(head);
    } on FormatException catch (error) {
      throw AudioExtractionException('Extracted audio is not a usable WAV: ${error.message}');
    }

    if (header.sampleRate != _targetSampleRate ||
        header.channels != _targetChannels ||
        header.bitsPerSample != _targetBitDepth) {
      throw AudioExtractionException(
        'Extracted audio is ${header.sampleRate}Hz/${header.channels}ch/'
        '${header.bitsPerSample}-bit, but the engine requires '
        '$_targetSampleRate Hz mono $_targetBitDepth-bit.',
      );
    }

    if (header.dataBytes <= 0) {
      throw const AudioExtractionException('Extracted audio contains no samples');
    }

    // Skipped when the source duration is unknown -- an unverifiable file is
    // not the same as a bad one.
    final sourceDuration = await probeDuration(sourcePath);
    if (sourceDuration == null || sourceDuration <= Duration.zero) return;

    final drift = (header.duration - sourceDuration).abs();
    final allowed = _maxDuration(
      _durationFloor,
      sourceDuration * _durationTolerance,
    );
    if (drift > allowed) {
      throw AudioExtractionException(
        'Extracted audio runs for ${header.duration.inMilliseconds}ms but the '
        'source is ${sourceDuration.inMilliseconds}ms. The decoder and the '
        'container disagree about the audio format, so the samples would '
        'transcribe as nonsense.',
      );
    }
  }

  static Duration _maxDuration(Duration a, Duration b) => a > b ? a : b;

  /// Duration of [mediaPath], or null if the platform cannot report it.
  Future<Duration?> probeDuration(String mediaPath) async {
    try {
      final info = await AudioDecoder.getAudioInfo(mediaPath);
      return info.duration;
    } catch (_) {
      // Intentionally catch-all rather than just AudioConversionException:
      // this metadata is cosmetic, and a container the native probe dislikes
      // must not sink an import whose audio transcribes perfectly well.
      return null;
    }
  }

  /// Removes a project's entire media directory. Used to roll back a failed
  /// import so half-copied files do not accumulate.
  Future<void> discardProjectMedia(String projectId) async {
    final dir = Directory(p.join(await _mediaDirPath(), projectId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Where one clip's source, extracted WAV and thumbnails live.
  Future<Directory> _clipDir(String projectId, String clipId) async {
    final dir = Directory(p.join(await _mediaDirPath(), projectId, clipId));
    await dir.create(recursive: true);
    return dir;
  }

  /// Where one clip's filmstrip frames are cached.
  String thumbnailDirFor({required String clipId, required String mediaPath}) {
    final parent = p.dirname(mediaPath);
    return p.basename(parent) == clipId
        ? p.join(parent, 'thumbs')
        : p.join(parent, 'thumbs-$clipId');
  }

  /// Total bytes a project's media directory occupies, or 0 if it has none.
  Future<int> projectMediaBytes(String projectId) async {
    final dir = Directory(p.join(await _mediaDirPath(), projectId));
    if (!await dir.exists()) return 0;

    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        continue;
      }
    }
    return total;
  }

  Future<String> _mediaDirPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'media');
  }
  /// Writes the samples between [startMs] and [endMs] of [source] to
  /// [destination] as a WAV in the same format.
  Future<File> sliceWav({
    required String source,
    required String destination,
    required int startMs,
    required int endMs,
  }) async {
    final input = File(source);
    if (!await input.exists()) {
      throw AudioExtractionException('No audio to slice at $source');
    }

    final handle = await input.open();
    try {
      // Only the head is read to parse the header: the chunk walk needs a few
      // hundred bytes, never the whole multi-megabyte file.
      final head = await handle.read(_headerProbeBytes);
      final header = WavHeader.parse(head);

      // The same arithmetic `speaker_refiner.dart` reads embedding windows
      // with.
      final bytesPerMs =
          header.sampleRate * (header.bitsPerSample ~/ 8) * header.channels / 1000;

      var from = (startMs * bytesPerMs).floor();
      var to = (endMs * bytesPerMs).ceil();
      if (from < 0) from = 0;
      if (to > header.dataBytes) to = header.dataBytes;
      // Whole samples only. A range starting mid-sample would shift every
      // byte after it by one and turn the audio into noise.
      final align = header.channels * (header.bitsPerSample ~/ 8);
      from -= from % align;
      to -= to % align;

      if (to <= from) {
        throw AudioExtractionException(
          'Range ${startMs}ms-${endMs}ms is empty within ${header.duration.inMilliseconds}ms of audio',
        );
      }

      final output = File(destination);
      await output.parent.create(recursive: true);
      final sink = output.openWrite();
      try {
        sink.add(buildWavHeader(
          sampleRate: header.sampleRate,
          channels: header.channels,
          bitsPerSample: header.bitsPerSample,
          dataBytes: to - from,
        ));

        // Never a constant 44: `WavHeader` walks the chunks precisely because
        // encoders put `LIST` or `fact` ahead of `data`, and seeking to a
        // guessed offset would slice from the wrong place -- or from metadata.
        await handle.setPosition(header.dataOffset + from);

        var remaining = to - from;
        while (remaining > 0) {
          final chunk = await handle.read(
            remaining < _sliceChunkBytes ? remaining : _sliceChunkBytes,
          );
          if (chunk.isEmpty) break;
          sink.add(chunk);
          remaining -= chunk.length;
        }
      } finally {
        await sink.close();
      }

      await _verifySlice(output, expected: to - from, source: header);
      return output;
    } finally {
      await handle.close();
    }
  }

  /// Checks a slice is the format and the length it was asked for.
  Future<void> _verifySlice(
    File slice, {
    required int expected,
    required WavHeader source,
  }) async {
    final handle = await slice.open();
    final WavHeader written;
    try {
      written = WavHeader.parse(await handle.read(_headerProbeBytes));
    } finally {
      await handle.close();
    }

    if (written.sampleRate != source.sampleRate ||
        written.channels != source.channels ||
        written.bitsPerSample != source.bitsPerSample) {
      throw AudioExtractionException(
        'Slice changed format: ${written.sampleRate}Hz/${written.channels}ch/'
        '${written.bitsPerSample}-bit from ${source.sampleRate}Hz/'
        '${source.channels}ch/${source.bitsPerSample}-bit',
      );
    }

    if (written.dataBytes != expected) {
      throw AudioExtractionException(
        'Slice is ${written.dataBytes} bytes, expected $expected',
      );
    }
  }

  /// Enough of a file to contain any reasonable RIFF header and its chunks.
  static const int _headerProbeBytes = 1024;

  /// Copy granularity. Large enough that a long slice is not thousands of
  /// reads, small enough that memory stays flat.
  static const int _sliceChunkBytes = 256 * 1024;
}

@Riverpod(keepAlive: true)
MediaConverter mediaConverter(Ref ref) => MediaConverter();
