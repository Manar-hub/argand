import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../media/wav_codec.dart';
import '../media/wav_header.dart';
import 'speaker_assignment.dart';
import 'speaker_diarizer.dart';
import 'speaker_refinement.dart';
import 'speaker_span.dart';

part 'speaker_refiner.g.dart';

/// What a refinement pass did, whether or not it changed anything.
class RefinementResult {
  const RefinementResult({
    required this.spans,
    required this.decisions,
    required this.embeddedRegions,
    required this.elapsedMs,
  });

  /// Refined spans, or the input untouched when the pass declined.
  final List<SpeakerSpan> spans;

  /// One entry per candidate, including the declines — which are the
  /// informative half when tuning thresholds.
  final List<RefinementDecision> decisions;

  final int embeddedRegions;
  final int elapsedMs;

  int get movedCount =>
      decisions.where((d) => d.outcome == RefinementOutcome.moved).length;
}

/// Re-checks doubtful attributions against the audio, using the CAM++ speaker
/// embedding model already bundled for diarization.
///
/// **This refines pyannote rather than replacing it.** Segmentation still
/// decides where turns are; this only answers *who* is speaking in regions
/// segmentation left doubtful, and only when the answer is clear. With weak
/// evidence it changes nothing, so its failure mode is "no improvement" rather
/// than a confident wrong answer.
///
/// It exists because reconciliation cannot reach every error. A word can only
/// be attributed to a speaker segmentation actually reported, and on real
/// material it sometimes reports none — see [SpeakerRefinement] for the
/// measured case that motivated this.
class SpeakerRefiner {
  /// Refines [spans] for the audio in [wavPath].
  ///
  /// [assigned] is the pre-refinement per-word attribution, used to know which
  /// speaker currently holds each sentence. Returns the input unchanged when
  /// there is nothing worth asking about.
  Future<RefinementResult> refine({
    required String wavPath,
    required List<SpeakerSpan> spans,
    required List<WordTiming> words,
    required List<int?> assigned,
    SpeakerRefinement config = const SpeakerRefinement(),
  }) async {
    final started = DateTime.now();

    final plan = planRefinement(
      spans: spans,
      words: words,
      assigned: assigned,
      config: config,
    );
    if (plan.isEmpty) {
      return RefinementResult(
        spans: spans,
        decisions: const [],
        embeddedRegions: 0,
        elapsedMs: DateTime.now().difference(started).inMilliseconds,
      );
    }

    // Resolved on this isolate: path_provider is a platform-channel call, and
    // platform channels only exist on the isolate owning the Flutter engine.
    final diarizer = SpeakerDiarizer();
    await diarizer.ensureModelsReady();
    final supportDir = await getApplicationSupportDirectory();
    final modelPath =
        p.join(supportDir.path, SpeakerDiarizer.embeddingModelFile);

    final decisions = await _spawn(
      wavPath: wavPath,
      embeddingModelPath: modelPath,
      plan: plan,
      config: config,
    );

    return RefinementResult(
      spans: applyRefinements(spans, decisions),
      decisions: decisions,
      embeddedRegions: plan.embedCount,
      elapsedMs: DateTime.now().difference(started).inMilliseconds,
    );
  }

  /// Spawns the worker.
  ///
  /// Every parameter here is sendable, so the closure below has nothing
  /// unsendable in scope to capture. Keep it that way: do not add a callback,
  /// a Future, or a reference to `this` to this signature. An `Isolate.run`
  /// closure captures the enclosing function's whole context, not just what it
  /// mentions, and that bit this project once already — see
  /// docs/engineering-notes.md.
  static Future<List<RefinementDecision>> _spawn({
    required String wavPath,
    required String embeddingModelPath,
    required RefinementPlan plan,
    required SpeakerRefinement config,
  }) {
    return Isolate.run(
      () => _runRefinement(
        wavPath: wavPath,
        embeddingModelPath: embeddingModelPath,
        plan: plan,
        config: config,
      ),
    );
  }
}

List<RefinementDecision> _runRefinement({
  required String wavPath,
  required String embeddingModelPath,
  required RefinementPlan plan,
  required SpeakerRefinement config,
}) {
  // FFI bindings are per-isolate state, so this is required here even though
  // diarization already called it on another isolate.
  sherpa.initBindings();

  final input = File(wavPath).openSync();
  sherpa.SpeakerEmbeddingExtractor? extractor;

  try {
    final header = WavHeader.parse(input.readSync(4096));
    if (header.sampleRate != SpeakerDiarizer.requiredSampleRate ||
        header.channels != 1 ||
        header.bitsPerSample != 16) {
      throw StateError(
        'Refinement needs 16kHz mono 16-bit audio, got '
        '${header.sampleRate}Hz ${header.channels}ch ${header.bitsPerSample}bit',
      );
    }

    extractor = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(
        model: embeddingModelPath,
        numThreads: 1,
        // Defaults to true and dumps an onnxruntime session log per call.
        debug: false,
      ),
    );

    final bytesPerMs = header.sampleRate * (header.bitsPerSample ~/ 8) / 1000;

    Float32List? embed(int startMs, int endMs) {
      var from = (startMs * bytesPerMs).floor();
      var to = (endMs * bytesPerMs).ceil();
      if (from < 0) from = 0;
      if (to > header.dataBytes) to = header.dataBytes;
      if (to <= from) return null;

      // Only the region is read, never the whole file: a 1.5s window is 48KB
      // of PCM against however many minutes the recording runs to.
      input.setPositionSync(header.dataOffset + from);
      final bytes = input.readSync(to - from);
      if (bytes.isEmpty) return null;

      final stream = extractor!.createStream();
      try {
        stream.acceptWaveform(
          samples: pcm16ToFloat32(bytes),
          sampleRate: header.sampleRate,
        );
        stream.inputFinished();
        // Not enough audio to characterise a voice. Treated the same as a
        // failed computation: skip the region, change nothing.
        if (!extractor.isReady(stream)) return null;
        final embedding = extractor.compute(stream);
        return embedding.isEmpty ? null : embedding;
      } finally {
        stream.free();
      }
    }

    // Voice prints first. A speaker without one cannot win a reassignment, and
    // cannot lose one either.
    //
    // Each proposed reference is split in half and both halves embedded. If
    // they do not sound like each other, the span holds more than one voice --
    // a turn segmentation never reported -- and learning from it would fold the
    // wrong person into this speaker's print. Testing that acoustically is what
    // replaced guessing at it from span length and sentence count, which
    // depended on how whisper happened to segment and so changed with the
    // transcription model.
    final prints = <int, Float32List>{};
    plan.references.forEach((speaker, regions) {
      final vectors = <Float32List>[];
      for (final region in regions) {
        final middle = region.startMs + (region.endMs - region.startMs) ~/ 2;
        final first = unitVector(embed(region.startMs, middle));
        final second = unitVector(embed(middle, region.endMs));

        if (first != null && second != null) {
          if (cosineSimilarity(first, second) < config.minReferenceCoherence) {
            continue;
          }
        }

        final vector = unitVector(embed(region.startMs, region.endMs));
        if (vector != null) vectors.add(vector);
      }
      final centroid = centroidOf(vectors);
      if (centroid != null) prints[speaker] = centroid;
    });

    if (prints.length < 2) return const [];

    final decisions = <RefinementDecision>[];
    for (final candidate in plan.candidates) {
      final vector = unitVector(embed(candidate.startMs, candidate.endMs));
      if (vector == null) {
        decisions.add(RefinementDecision(
          candidate: candidate,
          similarities: const {},
          newSpeaker: null,
          outcome: RefinementOutcome.skippedNoEmbedding,
        ));
        continue;
      }

      final similarities = <int, double>{
        for (final entry in prints.entries)
          entry.key: cosineSimilarity(vector, entry.value),
      };

      final outcome = decideOne(
        similarities: similarities,
        currentSpeaker: candidate.currentSpeaker,
        config: config,
      );

      int? winner;
      if (outcome == RefinementOutcome.moved) {
        var best = similarities.keys.first;
        var bestScore = double.negativeInfinity;
        similarities.forEach((speaker, score) {
          if (score > bestScore) {
            bestScore = score;
            best = speaker;
          }
        });
        winner = best;
      }

      decisions.add(RefinementDecision(
        candidate: candidate,
        similarities: similarities,
        newSpeaker: winner,
        outcome: outcome,
      ));
    }

    return decisions;
  } finally {
    extractor?.free();
    input.closeSync();
  }
}

@Riverpod(keepAlive: true)
SpeakerRefiner speakerRefiner(Ref ref) => SpeakerRefiner();
