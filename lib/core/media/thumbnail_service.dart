import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'thumbnail_service.g.dart';

/// Frames sampled out of a clip, for the timeline's filmstrip.
///
/// A **MethodChannel** to native Kotlin, the mechanism CLAUDE.md §8 names for
/// OS-level services. Android's `MediaMetadataRetriever` does the decoding,
/// which keeps this on the platform's own decoders and out of FFmpeg's way —
/// the same rule the audio pipeline follows (`docs/engine-architecture.md`).
///
/// **Android only.** There is no iOS counterpart yet, exactly as the share
/// sheet has none; iOS is deferred project-wide (CLAUDE.md §3). On any other
/// platform this returns an empty list and the filmstrip falls back to its
/// plain fill, which is a clip you cannot preview rather than a broken screen.
class ThumbnailService {
  const ThumbnailService();

  static const _channel = MethodChannel('argand/thumbnails');

  /// How many frames a clip of a given length is worth showing.
  ///
  /// Roughly one per two seconds so a longer clip gets a longer strip — which
  /// is what makes the filmstrip read as a span of time rather than as a fixed
  /// row of icons — but bounded at both ends: a very short clip still gets
  /// enough frames to look like a strip, and an hour-long one does not decode
  /// eighteen hundred JPEGs to be scrolled past.
  static int frameCountFor(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return _minFrames;
    return (seconds ~/ 2).clamp(_minFrames, _maxFrames);
  }

  static const _minFrames = 3;
  static const _maxFrames = 40;

  /// Frame images for [mediaPath], generating them if they are not on disk.
  ///
  /// Cached in [cacheDir] — the clip's own `thumbs/` directory — so a project
  /// reopened later does not decode its video again. They live with the clip
  /// rather than in the OS cache so that removing the clip removes them in the
  /// same recursive delete, with no second cleanup path to forget.
  ///
  /// Returns an empty list rather than throwing when extraction fails: a
  /// filmstrip with no pictures is a degraded timeline, not a broken one, and
  /// an audio-only clip legitimately has no frames at all.
  Future<List<String>> framesFor({
    required String mediaPath,
    required String cacheDir,
    required int count,
  }) async {
    final cached = await _cachedFrames(cacheDir, count);
    if (cached.isNotEmpty) return cached;

    try {
      final paths = await _channel.invokeListMethod<String>('extractFrames', {
        'mediaPath': mediaPath,
        'outputDir': cacheDir,
        'count': count,
      });
      return paths ?? const [];
    } on MissingPluginException {
      // A platform with no implementation. Not an error worth surfacing.
      return const [];
    } catch (error) {
      debugPrint('Could not extract frames from $mediaPath: $error');
      return const [];
    }
  }

  /// Frames already on disk, or empty if the set is missing or incomplete.
  ///
  /// All or nothing on purpose: a half-written directory, from extraction
  /// interrupted by the process dying, should be regenerated rather than shown
  /// as a strip with holes in it.
  Future<List<String>> _cachedFrames(String cacheDir, int count) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return const [];

    final paths = [
      for (var index = 0; index < count; index++)
        p.join(cacheDir, '$index.jpg'),
    ];
    for (final path in paths) {
      if (!await File(path).exists()) return const [];
    }
    return paths;
  }
}

@Riverpod(keepAlive: true)
ThumbnailService thumbnailService(Ref ref) => const ThumbnailService();

/// The frame images for one clip, keyed so two clips never share a strip.
///
/// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
/// no reason to pin its paths in memory, and regenerating is a directory
/// listing once the JPEGs exist.
@riverpod
Future<List<String>> clipFrames(
  Ref ref, {
  required String mediaPath,
  required String cacheDir,
  required int count,
}) {
  return ref.watch(thumbnailServiceProvider).framesFor(
        mediaPath: mediaPath,
        cacheDir: cacheDir,
        count: count,
      );
}
