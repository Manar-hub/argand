import 'dart:convert';
import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/video/export_options.dart';
import '../../core/video/video_export.dart';
import 'transcript_repository.dart';

part 'video_settings.g.dart';

/// How a project's video is framed: the shape and size it renders at, where its
/// watermark goes, and whether the preview shows that watermark.
class VideoSettings {
  const VideoSettings({
    this.aspect = ExportAspect.source,
    this.quality = ExportQuality.p1080,
    this.corner = WatermarkCorner.topRight,
    this.previewWatermark = true,
  });

  static const VideoSettings defaults = VideoSettings();

  final ExportAspect aspect;
  final ExportQuality quality;
  final WatermarkCorner corner;

  /// Whether the timeline draws the watermark over the preview.
  final bool previewWatermark;

  VideoSettings copyWith({
    ExportAspect? aspect,
    ExportQuality? quality,
    WatermarkCorner? corner,
    bool? previewWatermark,
  }) {
    return VideoSettings(
      aspect: aspect ?? this.aspect,
      quality: quality ?? this.quality,
      corner: corner ?? this.corner,
      previewWatermark: previewWatermark ?? this.previewWatermark,
    );
  }

  /// The options an export of this project starts from, branded.
  ExportOptions get exportOptions =>
      ExportOptions(aspect: aspect, quality: quality, corner: corner);

  /// [exportOptions] for a source with [sourceShortEdge] pixels on its short
  /// edge: the chosen size, brought down to one the footage can fill.
  ExportOptions exportOptionsFor(int? sourceShortEdge) =>
      exportOptions.copyWith(quality: quality.fitTo(sourceShortEdge));

  /// Stored by name, not index, so reordering an enum cannot reinterpret a
  /// project someone already set up.
  String encode() => jsonEncode({
        'aspect': aspect.name,
        'quality': quality.name,
        'corner': corner.name,
        'previewWatermark': previewWatermark,
      });

  /// Falls back to the defaults for anything missing or unrecognised: a
  /// setting from a newer build, or none at all, should open the project as
  /// it would have opened before, not fail to open it.
  static VideoSettings decode(String? json) {
    if (json == null) return defaults;

    Object? map;
    try {
      map = jsonDecode(json);
    } on FormatException {
      return defaults;
    }
    if (map is! Map) return defaults;

    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((value) => value.name == name, orElse: () => fallback);

    return VideoSettings(
      aspect: pick(ExportAspect.values, map['aspect'], defaults.aspect),
      quality: pick(ExportQuality.values, map['quality'], defaults.quality),
      corner: pick(WatermarkCorner.values, map['corner'], defaults.corner),
      previewWatermark: map['previewWatermark'] is bool
          ? map['previewWatermark'] as bool
          : defaults.previewWatermark,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoSettings &&
      other.aspect == aspect &&
      other.quality == quality &&
      other.corner == corner &&
      other.previewWatermark == previewWatermark;

  @override
  int get hashCode => Object.hash(aspect, quality, corner, previewWatermark);
}

/// The `Settings` key a project's video settings live under.
String videoSettingsKey(String projectId) => 'project.$projectId.video';

/// A project's video settings, changed live.
@riverpod
class ProjectVideoSettings extends _$ProjectVideoSettings {
  @override
  Future<VideoSettings> build(String projectId) async {
    final db = ref.watch(appDatabaseProvider);
    return VideoSettings.decode(
      await db.readSetting(videoSettingsKey(projectId)),
    );
  }

  /// Applies [next] now and stores it.
  Future<void> change(VideoSettings next) async {
    state = AsyncData(next);
    await ref
        .read(appDatabaseProvider)
        .writeSetting(videoSettingsKey(projectId), next.encode());
  }
}

/// The pixel size of the project's footage: its first clip, which is what the
/// render sizes every export from.
@riverpod
Future<({int width, int height})?> projectSourceSize(
  Ref ref,
  String projectId,
) async {
  final clips = await ref.watch(projectClipsProvider(projectId).future);
  if (clips.isEmpty) return null;
  return const VideoExporter().sourceSize(clips.first.mediaPath);
}

/// The short edge of [size], or null when the size is unknown.
int? shortEdgeOf(({int width, int height})? size) =>
    size == null ? null : math.min(size.width, size.height);
