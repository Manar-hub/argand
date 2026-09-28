import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/video/export_options.dart';
import '../../core/video/video_export.dart';
import 'clip_controller.dart';
import 'transcript_repository.dart';

part 'video_export_controller.g.dart';

/// What exporting a project is doing right now.
sealed class VideoExportStatus {
  const VideoExportStatus();
}

class VideoExportIdle extends VideoExportStatus {
  const VideoExportIdle();
}

class VideoExportRunning extends VideoExportStatus {
  const VideoExportRunning({this.percent});

  /// Whole percent from `Transformer`, or null before it reports anything.
  final int? percent;
}

class VideoExportDone extends VideoExportStatus {
  const VideoExportDone(this.video);

  final ExportedVideo video;
}

/// Nothing on the timeline could be rendered.
class VideoExportEmpty extends VideoExportStatus {
  const VideoExportEmpty();
}

class VideoExportFailed extends VideoExportStatus {
  const VideoExportFailed(this.error);

  final Object error;
}

/// Renders the project's clips into a single MP4 in the device's Downloads.
@riverpod
class VideoExportController extends _$VideoExportController {
  /// Set while a cancellation is in flight.
  bool _cancelled = false;

  @override
  VideoExportStatus build(String projectId) => const VideoExportIdle();

  /// Renders the project and saves the result to Downloads.
  Future<VideoExportStatus> export({
    ExportOptions options = ExportOptions.defaults,
  }) async {
    if (state is VideoExportRunning) return state;
    _cancelled = false;

    // Set before the first await, not inside [_run].
    state = const VideoExportRunning();

    // Pinned for the duration of the render. This provider is auto-disposing,
    // and a render runs for minutes -- long enough that leaving the screen
    // part-way through is ordinary rather than exotic.
    final link = ref.keepAlive();
    try {
      return await _run(options);
    } finally {
      link.close();
    }
  }

  Future<VideoExportStatus> _run(ExportOptions options) async {
    final repository = ref.read(transcriptRepositoryProvider);

    // Read straight from the repository, not through the clip providers.
    final clips = await repository.clipsForProject(projectId);
    final timeline = ProjectTimeline.fromClips(clips);

    // What the gutter's eyes hid is left out, as the preview leaves it out.
    // Whatever sits on a hidden track is left out.
    final hidden = ref.read(hiddenTracksProvider(projectId));
    final playback =
        hiddenPlaybackOf(hidden, await repository.ensureTracks(projectId));
    bool shows(String? trackId) => trackId == null || !hidden.contains(trackId);

    final request = exportRequestFor(
      timeline: timeline,
      clips: clips,
      withAudio: !playback.audio,
      captionsByClip: await _captionsFor(repository, clips, shows),
      texts: [
        for (final text in await repository.textLayersForProject(projectId))
          if (shows(text.trackId)) text,
        // Burned in exactly as the stage shows it.
        for (final line in await repository.translationTextsForProject(
          projectId: projectId,
          timeline: timeline,
          clips: clips,
        ))
          if (shows(line.trackId)) line,
      ],
      images: [
        for (final image in await repository.imageLayersForProject(projectId))
          if (shows(image.trackId)) image,
      ],
    );
    if (request == null) {
      const empty = VideoExportEmpty();
      if (ref.mounted) state = empty;
      return empty;
    }

    try {
      final project = await repository.findProject(projectId);
      final fileName = exportFileName(
        projectTitle: project?.title ?? '',
        at: DateTime.now(),
      );

      final video = await const VideoExporter().export(
        clips: request.clips,
        fileName: fileName,
        options: options,
        hideVideo: playback.video,
        muteAudio: playback.audio,
        onProgress: (percent) {
          // Dropped if the controller has already finished or been torn down:
          // progress can arrive one poll after completion, and `state` itself
          // throws once the ref is unmounted.
          if (ref.mounted && state is VideoExportRunning) {
            state = VideoExportRunning(percent: percent);
          }
        },
      );

      final captionCount = request.clips
          .fold<int>(0, (total, clip) => total + clip.captions.length);
      debugPrint(
        'Exported $projectId to ${video.location} '
        '(${video.sizeBytes} bytes, ${request.clips.length} clips, '
        '$captionCount captions, ${request.totalMs}ms expected)',
      );
      final done = VideoExportDone(video);
      if (ref.mounted) state = done;
      return done;
    } catch (error, stackTrace) {
      debugPrint('Could not export $projectId: $error');
      debugPrintStack(stackTrace: stackTrace);

      // **A cancelled render is not a failed one.** The exception is the
      // native side acknowledging the stop; reporting it as an error would
      // tell the user their own decision went wrong.
      if (_cancelled) {
        if (ref.mounted) state = const VideoExportIdle();
        return const VideoExportIdle();
      }

      final failed = VideoExportFailed(error);
      if (ref.mounted) state = failed;
      return failed;
    }
  }

  /// The captions to burn over each clip, keyed by clip id.
  Future<Map<String, List<ExportCaption>>> _captionsFor(
    TranscriptRepository repository,
    List<MediaClip> clips,
    bool Function(String? trackId) shows,
  ) async {
    final byClip = <String, List<ExportCaption>>{};
    final layers = {
      for (final layer in await repository.layersForProject(projectId))
        layer.id: layer,
    };

    for (final clip in clips) {
      final transcripts = await repository.transcriptsForClip(clip.id);
      if (transcripts.isEmpty) continue;

      // **Grouped per transcript**, so each caption keeps the placement of
      // the layer it came from. Layers never overlap in time, so grouping
      // them apart breaks no cue that grouping them together would have made.
      final captions = <ExportCaption>[];
      for (final transcript in transcripts) {
        final layer = layers[transcript.layerId];
        captions.addAll(
          exportCaptionsFor(
            // Each sentence sits on its own track once moved, else on its
            // layer's; a hidden one is not burned in.
            [
              for (final word in await repository.watchWords(transcript.id).first)
                if (shows(word.captionTrackId ?? layer?.trackId)) word,
            ],
            // Scoped to what the clip actually plays: a trimmed clip must not
            // carry captions for audio the viewer never hears.
            window: clipWindow(clip),
            placement: layer == null
                ? ItemTransform.captionDefault
                : ItemTransform(
                    x: layer.captionX,
                    y: layer.captionY,
                    scale: layer.captionScale,
                  ),
            look: ItemLook.decode(layer?.captionLook) ?? ItemLook.defaults,
          ),
        );
      }
      captions.sort((a, b) => a.startMs.compareTo(b.startMs));
      if (captions.isNotEmpty) byClip[clip.id] = captions;
    }

    return byClip;
  }

  /// Stops a running render and returns to idle.
  Future<void> cancel() async {
    if (state is! VideoExportRunning) return;

    // Raised before the request goes out, because the refusal can come back
    // before this method resumes.
    _cancelled = true;
    await const VideoExporter().cancel();
    if (ref.mounted) state = const VideoExportIdle();
  }

  /// Clears a finished or failed run so the action can be taken again.
  void reset() => state = const VideoExportIdle();
}
