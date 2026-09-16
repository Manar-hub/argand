import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'wav_header.dart';

part 'media_converter.g.dart';

/// Thrown when audio extraction produced a file the engine must not be fed.
///
/// Deliberately fatal to the import. A malformed WAV is loud and obvious, but
/// a *plausible* one that simply holds the wrong samples is not: whisper.cpp
/// accepts it and returns a fluent, confident, wrong transcript. Failing here
/// is the only way that stays visible.
class AudioExtractionException implements Exception {
  const AudioExtractionException(this.message);

  final String message;

  @override
  String toString() => 'AudioExtractionException: $message';
}

/// Turns an arbitrary picked media file into the 16kHz mono 16-bit PCM WAV
/// that whisper.cpp requires, using native OS decoders (MediaCodec on
/// Android, AVFoundation on iOS) via the `audio_decoder` package.
///
/// No FFmpeg anywhere in this path -- see docs/engine-architecture.md for
/// why that dependency is excluded.
class MediaConverter {
  /// whisper.cpp's required input format. Not configurable.
  static const int _targetSampleRate = 16000;
  static const int _targetChannels = 1;
  static const int _targetBitDepth = 16;

  /// Writes [bytes] into app-owned storage for one clip, preserving
  /// [fileName]'s extension, and returns the new file.
  ///
  /// Takes a stream rather than a source path on purpose. On Android the
  /// picker usually hands back a `content://` URI, which has no filesystem
  /// path at all -- and even when a path exists, the read grant behind it is
  /// revocable once the picker session ends, so a project that stored it
  /// would fail to open on a later launch. Copying the bytes out is the only
  /// approach that holds for both cases, and it is also what share-sheet
  /// import will need later.
  ///
  /// The extension is preserved because the native decoders and the video
  /// player both use it to pick a container parser.
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
  ///
  /// For the share sheet, where the native side has already copied the bytes
  /// out of a `content://` provider into the cache directory. Copying again
  /// would mean writing a video twice and holding two copies of it at once,
  /// which on a phone with a few gigabytes free is a real cost rather than a
  /// theoretical one.
  ///
  /// Cache and documents live on the same filesystem inside the app sandbox, so
  /// the rename is atomic and instant. The copy is a genuine fallback rather
  /// than dead code: nothing guarantees that, and a device that partitions them
  /// differently must still be able to import.
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
  ///
  /// Works on video containers as well as audio files: the native backends
  /// select the audio track and ignore the video one, which is first-class
  /// behaviour on both platforms rather than an edge case.
  Future<File> extractWavForTranscription(String mediaPath) async {
    final output = File(p.setExtension(mediaPath, '.16k.wav'));

    // Converted unconditionally, and deliberately not gated on
    // `AudioDecoder.needsConversion`. Two reasons that helper is wrong here:
    // it matches against the package's own hardcoded extension list, which
    // omits `.mov` -- the default iPhone capture container -- and so reports a
    // `.mov` as needing no conversion at all; and it answers "is this already
    // WAV", which is not the question. An existing WAV can still be 44.1kHz
    // stereo, which whisper.cpp will not accept. The native decoders read
    // `.mov` audio as readily as `.mp4`, so the platform is left to reject
    // only what it genuinely cannot decode.
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
  ///
  /// Some slack is expected: decoders drop encoder priming samples and the
  /// resampler rounds at chunk boundaries. The failure this catches is not
  /// subtle -- a wrong resampling ratio stretches the audio by a whole
  /// multiple -- so the tolerance only has to exclude that.
  static const Duration _durationFloor = Duration(milliseconds: 500);
  static const double _durationTolerance = 0.02;

  /// Fails the import unless [wav] is genuinely what whisper.cpp expects.
  ///
  /// Checks the declared format *and* the sample count behind it. Both matter:
  /// this exact guard exists because `audio_decoder` once produced a file whose
  /// header correctly read 16kHz mono while the samples were resampled at half
  /// the right ratio -- the audio came out at half speed and twice the length,
  /// well-formed and completely wrong. See docs/engine-architecture.md.
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
  ///
  /// Never fatal: duration is display metadata, and a file that transcribes
  /// fine should not fail import because its container lacks a duration.
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

  /// Removes the directory a media file lives in.
  ///
  /// Addressed by *path* rather than by project id, because duplicated projects
  /// share one file: the directory belongs to whichever project first imported
  /// it, and the last project to be deleted is rarely that one.
  Future<void> discardMediaAt(String mediaPath) async {
    final dir = Directory(p.dirname(mediaPath));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes one clip's media without touching its siblings.
  ///
  /// **Two layouts have to be told apart here, and getting it wrong destroys a
  /// project's other clips.** A clip added since schema 5 owns its directory
  /// (`media/<projectId>/<clipId>/`), so removing that directory takes its
  /// source, its extracted WAV and its thumbnails in one step. A clip carried
  /// over by the schema-5 migration still sits directly in the *project*
  /// directory (`media/<projectId>/source.mp4`), which it shares with every
  /// clip added afterwards -- deleting that directory would take them all.
  ///
  /// So the parent directory is only removed when it is genuinely the clip's
  /// own, which is exactly the case where its name is the clip id. Otherwise
  /// the source file and its derived WAV go individually and the directory
  /// stays.
  Future<void> discardClipMedia({
    required String clipId,
    required String mediaPath,
  }) async {
    final parent = Directory(p.dirname(mediaPath));

    if (p.basename(parent.path) == clipId) {
      if (await parent.exists()) await parent.delete(recursive: true);
      return;
    }

    for (final entity in <FileSystemEntity>[
      File(mediaPath),
      File(p.setExtension(mediaPath, '.16k.wav')),
      Directory(thumbnailDirFor(clipId: clipId, mediaPath: mediaPath)),
    ]) {
      // Best-effort per entry: the row is already gone by the time this runs,
      // so a stranded byte is a leak to report, never a failure to raise.
      try {
        if (await entity.exists()) await entity.delete(recursive: true);
      } on FileSystemException {
        continue;
      }
    }
  }

  /// Where one clip's source, extracted WAV and thumbnails live.
  ///
  /// A directory per clip rather than per project, because a project holds
  /// several and the source filename is a fixed `source.<ext>` -- two clips in
  /// one directory would overwrite each other, and their derived
  /// `source.16k.wav` would collide even when the extensions differed.
  Future<Directory> _clipDir(String projectId, String clipId) async {
    final dir = Directory(p.join(await _mediaDirPath(), projectId, clipId));
    await dir.create(recursive: true);
    return dir;
  }

  /// The directory holding every clip of [projectId].
  Future<String> projectMediaDir(String projectId) async =>
      p.join(await _mediaDirPath(), projectId);

  /// Where one clip's filmstrip frames are cached.
  ///
  /// Derived from the media path rather than from ids, so it lands beside the
  /// source for both layouts -- inside the clip's own directory for a clip
  /// added since schema 5, and beside `source.<ext>` for one the migration
  /// carried over. Named per clip in the second case, since those share the
  /// project directory and would otherwise collide.
  String thumbnailDirFor({required String clipId, required String mediaPath}) {
    final parent = p.dirname(mediaPath);
    return p.basename(parent) == clipId
        ? p.join(parent, 'thumbs')
        : p.join(parent, 'thumbs-$clipId');
  }

  /// Total bytes a project's media directory occupies, or 0 if it has none.
  ///
  /// Counts the imported source file and the extracted WAV together, which is
  /// what the user actually pays for in storage -- the WAV alone runs about
  /// 1.9 MB per minute of audio at 16kHz mono 16-bit.
  ///
  /// Individual files that vanish mid-walk are skipped rather than throwing: a
  /// size readout is informational, and must not be able to break the library
  /// list if an import is cleaning up concurrently.
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
}

@Riverpod(keepAlive: true)
MediaConverter mediaConverter(Ref ref) => MediaConverter();
