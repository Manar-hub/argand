import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'thumbnail_service.g.dart';

/// Frames sampled out of a clip, for the timeline's filmstrip.
class ThumbnailService {
  const ThumbnailService();

  static const _channel = MethodChannel('argand/thumbnails');

  /// How many frames a clip of a given length is worth showing.
  static int frameCountFor(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return _minFrames;
    return (seconds ~/ 2).clamp(_minFrames, _maxFrames);
  }

  /// How many frames to extract for a filmstrip that has room for [slots].
  static int frameCountForSlots(int slots, Duration duration) {
    final ceiling = duration.inSeconds <= 0
        ? _minFrames
        : (duration.inSeconds * 2).clamp(_minFrames, _maxDetailFrames);

    for (final bucket in _frameBuckets) {
      if (slots <= bucket) return bucket.clamp(_minFrames, ceiling);
    }
    return _frameBuckets.last.clamp(_minFrames, ceiling);
  }

  static const _frameBuckets = [10, 20, 40, 80, 120];

  static const _minFrames = 3;
  static const _maxFrames = 40;

  /// Ceiling once a filmstrip is zoomed in far enough to want detail.
  static const _maxDetailFrames = 120;

  /// Frame images for [mediaPath], generating them if they are not on disk.
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
