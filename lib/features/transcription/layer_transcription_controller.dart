import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/database/database.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/timeline/timeline_event.dart';
import 'timeline_history.dart';
import '../../core/translation/translator.dart';
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

    // Collected across the whole run rather than per clip: a layer covering
    // several clips is still one action, and undo should take all of it back.
    final written = <String>[];

    try {
      // A process killed mid-run never reaches its own cleanup, so the
      // leftovers are swept here rather than accumulating one per crash.
      await TranscriptionRunner.sweepSlices();

      if (replacing) {
        await repository.discardLayerTranscripts(layerId);
      }

      final clips = <String, MediaClip>{};
      for (final range in ranges) {
        final clip = await repository.findClip(range.clipId);
        if (clip != null) clips[range.clipId] = clip;
      }

      final groups = groupContiguousRanges(ranges, clips);

      for (final (index, group) in groups.indexed) {
        final mediaPath = clips[group.first.clipId]!.mediaPath;
        final from = group.first.clipStartMs;
        final to = group.last.clipEndMs;

        // **One run for the whole recording, not one per clip.** Splitting a
        // clip does not make it two recordings, but a run per clip meant a
        // diarization run per clip -- and speaker numbers are cluster indices
        // with meaning only inside the run that produced them. The same person
        // either side of a cut came back as two speakers, in two colours,
        // because nothing had ever compared them.
        final outcome = await TranscriptionRunner(ref).run(
          mediaPath: mediaPath,
          range: (startMs: from, endMs: to),
          onStage: (stage, {int? percent}) {
            state = LayerTranscriptionRunning(
              stage,
              percent: percent,
              clipIndex: index,
              clipCount: groups.length,
            );
          },
        );

        state = LayerTranscriptionRunning(
          ImportStage.saving,
          clipIndex: index,
          clipCount: groups.length,
        );

        // The words are shared out by time, but the speaker spans are not:
        // every clip in the group is handed the same ones, so assignment
        // happens in the single space the one run established.
        for (final range in group) {
          written.add(await repository.saveClipTranscript(
            projectId: layer.projectId,
            clipId: range.clipId,
            language: outcome.language,
            speakerSpans: outcome.speakerSpans,
            result: segmentsWithin(
              outcome.result,
              fromMs: range.clipStartMs - from,
              toMs: range.clipEndMs - from,
            ),
            layerId: layerId,
            // The engine saw the *group* starting at zero, so this is what
            // puts its words back where they were spoken in the file.
            offsetMs: from,
            // What this clip covers, which is its own share of the run.
            rangeStartMs: range.clipStartMs,
            rangeEndMs: range.clipEndMs,
          ));
        }
      }

      await _record(repository, layer.projectId, written);

      // The Transcribe sheet's "Translate to". Never fails the run: the
      // words are saved, and Translate on the captions is the retry.
      final to = await ref.read(translationTargetProvider.future);
      if (to != null && written.isNotEmpty) {
        state = const LayerTranscriptionRunning(ImportStage.translating);
        final failure = await repository.translateAll(
          transcriptIds: written,
          to: to,
          translator: ref.read(translatorProvider),
        );
        if (failure != null) debugPrint('Translation after run: $failure');
      }

      state = const LayerTranscriptionIdle();
    } catch (error, stackTrace) {
      // Recorded even when the run died part-way. Whatever committed is on
      // screen, and undo has to be able to reach what is on screen.
      await _record(repository, layer.projectId, written);
      debugPrint('Could not transcribe layer $layerId: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = LayerTranscriptionFailed(error);
    }
  }

  /// Records the run, so undo takes back the transcription itself.
  ///
  /// **A separate event from the layer that asked for it.** Drawing a layer
  /// and running the engine over it are two actions at two moments; with only
  /// the first recorded, undo after transcribing reached past the words to the
  /// track underneath them -- which is how the track disappeared while its
  /// captions stayed on the video.
  ///
  /// A rerun's *discarded* words are not part of this. Undoing a rerun retires
  /// what the rerun wrote without restoring what it replaced, because the
  /// discard is not in the history either; the layer is left ready to be run
  /// again, which is the state the rerun started from.
  Future<void> _record(
    TranscriptRepository repository,
    String projectId,
    List<String> transcriptIds,
  ) async {
    if (transcriptIds.isEmpty) return;

    await repository.recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.transcribeRun,
      payload: transcribeRunPayload(transcriptIds: transcriptIds),
    );
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

/// Groups ranges that are really one recording.
///
/// Two ranges belong together when they play the **same file** and meet
/// exactly -- which is what splitting a clip produces. Anything else starts a
/// new group: a different file is a different recording, and a gap means the
/// audio between was deliberately cut out and must not be transcribed.
List<List<ClipRange>> groupContiguousRanges(
  List<ClipRange> ranges,
  Map<String, MediaClip> clips,
) {
  final groups = <List<ClipRange>>[];

  for (final range in ranges) {
    final clip = clips[range.clipId];
    if (clip == null) continue;

    final current = groups.isEmpty ? null : groups.last;
    final previous = current?.last;
    final previousClip = previous == null ? null : clips[previous.clipId];

    final joins = previousClip != null &&
        previousClip.mediaPath == clip.mediaPath &&
        previous!.clipEndMs == range.clipStartMs;

    if (joins) {
      current!.add(range);
    } else {
      groups.add([range]);
    }
  }

  return groups;
}

/// The part of [whole] that falls in `[fromMs, toMs)`, in the run's own time.
///
/// Used to share one run's words out among the clips it covered. Half-open, so
/// a segment starting exactly on a cut belongs to the clip after it and no word
/// is stored twice.
WhisperTranscribeResponse segmentsWithin(
  WhisperTranscribeResponse whole, {
  required int fromMs,
  required int toMs,
}) {
  final kept = [
    for (final segment in whole.segments ?? const <WhisperTranscribeSegment>[])
      if (segment.fromTs.inMilliseconds >= fromMs &&
          segment.fromTs.inMilliseconds < toMs)
        segment,
  ];

  return WhisperTranscribeResponse(
    type: whole.type,
    text: kept.map((segment) => segment.text.trim()).join(' ').trim(),
    detectedLanguage: whole.detectedLanguage,
    segments: kept,
  );
}
