import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/video/video_export.dart';
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
///
/// Distinct from [VideoExportFailed]: no render was attempted, so there is
/// nothing to retry and what to say is about the project, not about an error.
class VideoExportEmpty extends VideoExportStatus {
  const VideoExportEmpty();
}

class VideoExportFailed extends VideoExportStatus {
  const VideoExportFailed(this.error);

  final Object error;
}

/// Renders the project's clips into a single MP4 in the device's Downloads.
///
/// **Captions are burned into the picture here and nowhere else.** They stay
/// structured text and timing through every other part of the app, so they
/// remain editable, re-groupable and exportable as SRT; rasterising them is the
/// last thing that happens, to the copy that leaves the device.
///
/// Trims are not applied and no watermark is composited, because neither
/// exists yet. That is the next slice, not an omission here.
///
/// **The file goes to the device's Downloads folder**, not app storage. An
/// export the user cannot open, share or find in a file manager is not an
/// export; where it lands is part of the feature, not an implementation detail.
///
/// One export at a time, enforced here *and* natively. A second encode competes
/// for the same hardware codec, which is the same reasoning that makes the
/// per-clip transcription runs sequential rather than parallel.
@riverpod
class VideoExportController extends _$VideoExportController {
  @override
  VideoExportStatus build(String projectId) => const VideoExportIdle();

  /// Renders the project and saves the result to Downloads.
  Future<void> export() async {
    if (state is VideoExportRunning) return;

    // **Pinned for the duration of the render.** This provider is
    // auto-disposing, and a render runs for minutes -- long enough that
    // leaving the screen part-way through is ordinary rather than exotic.
    // Without this the provider is disposed the moment nothing watches it,
    // and the next write to `state` throws `UnmountedRefException` from
    // inside a job that was otherwise going fine.
    final link = ref.keepAlive();
    try {
      await _run();
    } finally {
      link.close();
    }
  }

  Future<void> _run() async {
    final repository = ref.read(transcriptRepositoryProvider);

    // **Read straight from the repository, not through the clip providers.**
    // `projectTimelineProvider` answers synchronously from a stream that may
    // not have emitted yet, so an export started while those providers were
    // still loading -- or from a screen not watching them, which lets them
    // auto-dispose -- would see an empty timeline beside a full clip list.
    // Those two disagreeing is indistinguishable from an empty project, and
    // the export would quietly render nothing.
    //
    // `clipsForProject` and the stream behind the provider are the same query
    // ordered the same way, and `fromClips` is the same factory the provider
    // uses, so this is the identical answer taken without the lifetime.
    final clips = await repository.clipsForProject(projectId);
    final timeline = ProjectTimeline.fromClips(clips);

    final request = exportRequestFor(
      timeline: timeline,
      clips: clips,
      captionsByClip: await _captionsFor(repository, clips),
    );
    if (request == null) {
      if (ref.mounted) state = const VideoExportEmpty();
      return;
    }

    state = const VideoExportRunning();

    try {
      final project = await repository.findProject(projectId);
      final fileName = exportFileName(
        projectTitle: project?.title ?? '',
        at: DateTime.now(),
      );

      final video = await const VideoExporter().export(
        clips: request.clips,
        fileName: fileName,
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
      if (ref.mounted) state = VideoExportDone(video);
    } catch (error, stackTrace) {
      debugPrint('Could not export $projectId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (ref.mounted) state = VideoExportFailed(error);
    }
  }

  /// The captions to burn over each clip, keyed by clip id.
  ///
  /// **Gathered from the word rows on every export, never from a cache.**
  /// Cues are derived rather than stored precisely so that a corrected word, a
  /// merged sentence or a re-run layer needs no invalidation step -- reading
  /// them fresh here is what makes the burned captions match what the preview
  /// has been showing.
  ///
  /// A clip covered by more than one transcribe layer has more than one
  /// transcript, and all of them contribute; `exportCaptionsFor` puts the
  /// combined words back in time order before grouping.
  Future<Map<String, List<ExportCaption>>> _captionsFor(
    TranscriptRepository repository,
    List<MediaClip> clips,
  ) async {
    final byClip = <String, List<ExportCaption>>{};

    for (final clip in clips) {
      final transcripts = await repository.transcriptsForClip(clip.id);
      if (transcripts.isEmpty) continue;

      final words = <Word>[];
      for (final transcript in transcripts) {
        words.addAll(await repository.watchWords(transcript.id).first);
      }

      final captions = exportCaptionsFor(words);
      if (captions.isNotEmpty) byClip[clip.id] = captions;
    }

    return byClip;
  }

  /// Stops a running render and returns to idle.
  Future<void> cancel() async {
    if (state is! VideoExportRunning) return;
    await const VideoExporter().cancel();
    state = const VideoExportIdle();
  }

  /// Clears a finished or failed run so the action can be taken again.
  void reset() => state = const VideoExportIdle();
}
