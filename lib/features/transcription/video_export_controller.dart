import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/video/export_options.dart';
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
/// **The watermark is composited here too, and nowhere else.** It lands in the
/// same pass as the captions, which is what CLAUDE.md 9 asks for: pixels are
/// written once, at the end, to the copy that leaves the device.
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
  /// Set while a cancellation is in flight.
  ///
  /// **A flag rather than an ordering.** Stopping the render makes the native
  /// side raise an exception to acknowledge it, and that arrives through the
  /// same catch a real failure does. A first version told them apart by
  /// checking whether the state had already gone idle, which lost the race the
  /// moment the platform answered faster than [cancel] could set it -- and a
  /// user who pressed Cancel was told the render had failed.
  bool _cancelled = false;

  @override
  VideoExportStatus build(String projectId) => const VideoExportIdle();

  /// Renders the project and saves the result to Downloads.
  ///
  /// [options] is what the export dialog collected. It defaults to the same
  /// values the dialog opens on, so a caller with nothing to say about framing
  /// gets the branded, source-shaped 1080p render rather than an error.
  /// Returns the state the render ended in.
  ///
  /// **Returned rather than read back off the provider afterwards.** Both this
  /// and the screen listen to the same notifier, and the screen resets it to
  /// idle as soon as it has shown the outcome -- so a caller that waited and
  /// then looked was reading whichever listener happened to run first. It read
  /// a finished export as a cancelled one.
  Future<VideoExportStatus> export({
    ExportOptions options = ExportOptions.defaults,
  }) async {
    if (state is VideoExportRunning) return state;
    _cancelled = false;

    // **Set before the first await, not inside [_run].** Gathering the clips
    // and their captions is asynchronous, so a caller that opened a progress
    // window and then looked at the state found the controller still idle and
    // concluded the render had already ended -- which closed the window in the
    // same frame it opened. The transition belongs to whoever starts the
    // render, because that is the moment it becomes true.
    state = const VideoExportRunning();

    // **Pinned for the duration of the render.** This provider is
    // auto-disposing, and a render runs for minutes -- long enough that
    // leaving the screen part-way through is ordinary rather than exotic.
    // Without this the provider is disposed the moment nothing watches it,
    // and the next write to `state` throws `UnmountedRefException` from
    // inside a job that was otherwise going fine.
    final link = ref.keepAlive();
    try {
      return await _run(options);
    } finally {
      link.close();
    }
  }

  Future<VideoExportStatus> _run(ExportOptions options) async {
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
      texts: await repository.textLayersForProject(projectId),
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
            await repository.watchWords(transcript.id).first,
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
