import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'import_controller.dart' show ImportStage;
import 'transcript_repository.dart';
import 'transcription_run.dart';

part 'clip_transcription_controller.g.dart';

/// What transcribing one clip is doing right now.
///
/// Mirrors `ImportStatus`'s shape rather than reusing it, because the two carry
/// different results — an import ends with a project id to navigate to, while
/// this ends in place on a clip the user is already looking at.
sealed class ClipTranscriptionStatus {
  const ClipTranscriptionStatus();
}

class ClipTranscriptionIdle extends ClipTranscriptionStatus {
  const ClipTranscriptionIdle();
}

class ClipTranscriptionRunning extends ClipTranscriptionStatus {
  const ClipTranscriptionRunning(this.stage, {this.percent});

  final ImportStage stage;

  /// Only populated where the engine reports real progress — transcription and
  /// diarization. Null elsewhere, meaning "indeterminate".
  final int? percent;
}

class ClipTranscriptionFailed extends ClipTranscriptionStatus {
  const ClipTranscriptionFailed(this.error);

  final Object error;
}

/// Transcribes one clip, on request.
///
/// **The deliberate half of the split.** Adding a clip is cheap and immediate;
/// this is the part that costs minutes of CPU, so it never starts on its own.
/// Selecting a clip reveals the action, and the user takes it.
///
/// Keyed by clip, so two clips have genuinely independent state: transcribing
/// one does not make another look busy, and a failure is attributable to the
/// clip that caused it.
///
/// Note that a clip's word timings are relative to its own media, and its
/// speaker numbering comes from its own diarization run — labels do not
/// correspond across clips (`docs/engine-architecture.md`).
@riverpod
class ClipTranscriptionController extends _$ClipTranscriptionController {
  @override
  ClipTranscriptionStatus build(String clipId) =>
      const ClipTranscriptionIdle();

  /// Runs the engine over the whole of this clip and saves the words.
  ///
  /// **A shortcut for drawing a layer over the clip and running it**, so that
  /// layers stay the single mechanism rather than this being a second one.
  /// The layer it creates is what makes the result show on the timeline track
  /// and what a later re-run would replace.
  ///
  /// Refuses to run twice over the same clip: a second transcript covering the
  /// same range would sit beside the first with no way to tell which the user
  /// meant. Re-transcribing is destructive and needs its own confirmed path,
  /// not an accidental second tap.
  Future<void> transcribe() async {
    if (state is ClipTranscriptionRunning) return;

    final repository = ref.read(transcriptRepositoryProvider);
    final clip = await repository.findClip(clipId);
    if (clip == null) return;

    if ((await repository.transcriptsForClip(clipId)).isNotEmpty) {
      state = const ClipTranscriptionIdle();
      return;
    }

    // Where this clip sits on the project timeline, so the layer lands over
    // the clip it describes rather than at the project's start.
    final timeline = ref.read(projectTimelineProvider(clip.projectId));
    final placement = timeline.placementOf(clipId);

    try {
      final outcome = await TranscriptionRunner(ref).run(
        mediaPath: clip.mediaPath,
        onStage: (stage, {int? percent}) {
          state = ClipTranscriptionRunning(stage, percent: percent);
        },
      );

      state = const ClipTranscriptionRunning(ImportStage.saving);

      final layerId = placement == null
          ? null
          : await repository.addLayer(
              projectId: clip.projectId,
              startMs: placement.startMs,
              endMs: placement.startMs + placement.durationMs,
            );

      await repository.saveClipTranscript(
        projectId: clip.projectId,
        clipId: clipId,
        language: outcome.language,
        speakerSpans: outcome.speakerSpans,
        result: outcome.result,
        layerId: layerId,
        rangeEndMs: clip.durationMs,
      );

      state = const ClipTranscriptionIdle();
    } catch (error, stackTrace) {
      debugPrint('Could not transcribe clip $clipId: $error');
      debugPrintStack(stackTrace: stackTrace);

      // **No rollback, and that is the point.** An import could roll back by
      // deleting its media, because nothing was committed until the very last
      // step. A clip is already committed and is not garbage: the user added
      // it deliberately and it still plays. A failure here costs the
      // transcription attempt and nothing else, so the clip stays and the
      // action can simply be taken again.
      state = ClipTranscriptionFailed(error);
    }
  }

  void reset() => state = const ClipTranscriptionIdle();
}
