import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/timeline/project_timeline.dart';
import 'import_controller.dart' show ImportStage;
import 'transcript_repository.dart';
import 'transcription_run.dart';

part 'layer_transcription_controller.g.dart';

/// Shortest range worth handing to the engine.
///
/// Sherpa discards speech under `minDurationOn` of 0.2s and whisper's VAD
/// floor is 250ms, so anything below this produces an empty transcript at the
/// cost of a full model run. A sliver this size is almost always the tail of a
/// layer overhanging the clip beneath it rather than something the user drew.
const int minimumTranscribableMs = 250;

/// What transcribing one layer is doing right now.
sealed class LayerTranscriptionStatus {
  const LayerTranscriptionStatus();
}

class LayerTranscriptionIdle extends LayerTranscriptionStatus {
  const LayerTranscriptionIdle();
}

class LayerTranscriptionRunning extends LayerTranscriptionStatus {
  const LayerTranscriptionRunning(
    this.stage, {
    this.percent,
    this.clipIndex = 0,
    this.clipCount = 1,
  });

  final ImportStage stage;
  final int? percent;

  /// Which of the layer's clips is being worked on, so a layer spanning
  /// several does not appear to restart from zero at each boundary.
  final int clipIndex;
  final int clipCount;
}

class LayerTranscriptionFailed extends LayerTranscriptionStatus {
  const LayerTranscriptionFailed(this.error);

  final Object error;
}

/// Transcribes exactly the stretch of timeline a layer covers.
///
/// **A layer is a request; this is what answers it.** The layer says which
/// audio matters, and a run here produces one transcript per clip the layer
/// overlaps — never one per layer, because word timings are relative to a
/// clip's own media and a single transcript spanning two clips would have no
/// coherent timebase.
///
/// Clips are run **one after another, never in parallel**. Two whisper
/// contexts is not a throughput win on a phone, and the emulator already dies
/// at three sequential runs; a layer covering four clips would be four at
/// once. Each transcript is committed as it lands, so a failure part-way keeps
/// what already succeeded. A failed run costs the attempt and nothing else:
/// the clips still play and the layer still stands, so the action can simply
/// be taken again -- the same reasoning import uses for not rolling back a
/// clip that is already committed.
///
/// Two engine properties leak through here and are worth knowing:
///
/// - **Language auto-detection reads only the opening ~30s** of whatever it is
///   given, so two layers over one clip can independently detect different
///   languages. Pinning the language in settings avoids it.
/// - **Speaker numbers come from each diarization run** and are cluster
///   indices with meaning only inside it. They already did not correspond
///   across clips; with layers they no longer correspond *within* one either.
@riverpod
class LayerTranscriptionController extends _$LayerTranscriptionController {
  @override
  LayerTranscriptionStatus build(String layerId) =>
      const LayerTranscriptionIdle();

  /// Runs the engine over each clip the layer covers.
  ///
  /// Does nothing if the layer already has transcripts: re-running is
  /// destructive of word corrections and speaker names, so it goes through
  /// [rerun] where the caller has confirmed it.
  Future<void> transcribe() => _run(replacing: false);

  /// Transcribes again, discarding what this layer produced before.
  ///
  /// **Allowed, unlike re-transcribing a whole clip.** A layer is a request,
  /// and re-running it with a different model or language is an obvious thing
  /// to want. Refusing outright would be routed around by deleting the layer
  /// and redrawing it, which loses exactly the same data with no warning at
  /// all — so the destructive path is offered openly, and the caller is
  /// expected to have said what is lost.
  Future<void> rerun() => _run(replacing: true);

  Future<void> _run({required bool replacing}) async {
    if (state is LayerTranscriptionRunning) return;

    final repository = ref.read(transcriptRepositoryProvider);
    final layer = await repository.findLayer(layerId);
    if (layer == null) return;

    final existing = await repository.transcriptsForLayer(layerId);
    if (existing.isNotEmpty && !replacing) {
      state = const LayerTranscriptionIdle();
      return;
    }

    final timeline = ref.read(projectTimelineProvider(layer.projectId));
    final ranges = [
      for (final range in timeline.rangesFor(
        startMs: layer.startMs,
        endMs: layer.endMs,
      ))
        // Dropped with a reason rather than silently: a sliver under the
        // engine's own floor comes back empty, and an empty transcript beside
        // the others looks like a failure rather than like a range too short
        // to say anything.
        if (range.clipEndMs - range.clipStartMs >= minimumTranscribableMs)
          range
        else
          ..._skipped(range),
    ];

    if (ranges.isEmpty) {
      state = const LayerTranscriptionIdle();
      return;
    }

    try {
      // A process killed mid-run never reaches its own cleanup, so the
      // leftovers are swept here rather than accumulating one per crash.
      await TranscriptionRunner.sweepSlices();

      if (replacing) {
        await repository.discardLayerTranscripts(layerId);
      }

      for (final (index, range) in ranges.indexed) {
        final clip = await repository.findClip(range.clipId);
        if (clip == null) continue;

        final outcome = await TranscriptionRunner(ref).run(
          mediaPath: clip.mediaPath,
          range: (startMs: range.clipStartMs, endMs: range.clipEndMs),
          onStage: (stage, {int? percent}) {
            state = LayerTranscriptionRunning(
              stage,
              percent: percent,
              clipIndex: index,
              clipCount: ranges.length,
            );
          },
        );

        state = LayerTranscriptionRunning(
          ImportStage.saving,
          clipIndex: index,
          clipCount: ranges.length,
        );

        // Committed per clip rather than all at the end. The engine has
        // already been paid for at this point, and holding the result back
        // only creates a window in which a later failure throws it away.
        await repository.saveClipTranscript(
          projectId: layer.projectId,
          clipId: range.clipId,
          language: outcome.language,
          speakerSpans: outcome.speakerSpans,
          result: outcome.result,
          layerId: layerId,
          // The engine saw the range starting at zero; this is what puts its
          // words back where they were spoken in the clip.
          offsetMs: range.clipStartMs,
          rangeEndMs: range.clipEndMs,
        );
      }

      state = const LayerTranscriptionIdle();
    } catch (error, stackTrace) {
      debugPrint('Could not transcribe layer $layerId: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = LayerTranscriptionFailed(error);
    }
  }

  /// Logs a range too short to transcribe and contributes nothing.
  Iterable<ClipRange> _skipped(ClipRange range) sync* {
    debugPrint(
      'Layer $layerId covers only ${range.clipEndMs - range.clipStartMs}ms of '
      'clip ${range.clipId}, below the ${minimumTranscribableMs}ms the engine '
      'can say anything about. Skipping that clip.',
    );
  }
}
