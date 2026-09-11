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
import 'span_validation.dart';

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

  /// Re-labels short spans segmentation appears to have invented.
  ///
  /// **Runs before anything reads the spans**, because a spurious span edge
  /// cannot be repaired downstream: once it exists, whether a word falls left
  /// or right of it decides that word's speaker, so two transcription models
  /// that time the same word differently disagree about who said it. Measured
  /// on `two_speakers.wav`, where an 810ms span in the middle of one speaker's
  /// sentence split "That's right." one word per speaker under `small-q5_1`
  /// while `base` was unaffected.
  ///
  /// **Takes no transcript.** Suspects come from span geometry and voice prints
  /// come from [referenceRegionsOf], neither of which consults whisper, so the
  /// correction is identical for every transcription model by construction
  /// rather than by tuning.
  ///
  /// Non-fatal by contract: returns [spans] unchanged when there is nothing to
  /// challenge, when fewer than two voices can be learned, or when a region
  /// yields no embedding. Doing nothing is always a valid outcome here.
  Future<List<SpeakerSpan>> validateSpans({
    required String wavPath,
    required List<SpeakerSpan> spans,
    SpanValidation config = const SpanValidation(),
    SpeakerRefinement refinement = const SpeakerRefinement(),
  }) async {
    final suspects = suspectSpans(spans, config: config);
    if (suspects.isEmpty) return spans;

    final references = referenceRegionsOf(spans, config: refinement);
    if (references.length < 2) return spans;

    // Platform channels only exist on the isolate owning the Flutter engine,
    // so the model path is resolved here rather than in the worker.
    final diarizer = SpeakerDiarizer();
    await diarizer.ensureModelsReady();
    final supportDir = await getApplicationSupportDirectory();
    final modelPath =
        p.join(supportDir.path, SpeakerDiarizer.embeddingModelFile);

    final similarities = await _spawnSimilarities(
      wavPath: wavPath,
      embeddingModelPath: modelPath,
      references: references,
      regions: [
        for (final suspect in suspects)
          suspect.embedRegion(config) ??
              (startMs: suspect.startMs, endMs: suspect.endMs),
      ],
      config: refinement,
    );

    final reassigned = <SuspectSpan>[
      for (var i = 0; i < suspects.length; i++)
        if (challengerWins(suspects[i], similarities[i], config: config))
          suspects[i],
    ];

    return applyValidations(spans, reassigned);
  }

  /// How much each region in [regions] sounds like each speaker.
  ///
  /// **This decides nothing.** It answers "who does this stretch sound like",
  /// and hands the numbers back for a caller to weigh. [refine] uses the same
  /// voice prints to make a standalone verdict, gated on [SpeakerRefinement
  /// .minMargin]; this exists because that gate is the wrong shape for evidence
  /// that only needs to break a tie rather than win outright.
  ///
  /// The motivating case: a two-word sentence split across a spurious span
  /// boundary. Coverage alone puts the words on different speakers, and the
  /// acoustic margin is far too thin for [refine] to act on alone -- but as one
  /// term inside a sequence decision it is enough to settle which speaker the
  /// whole sentence belongs to. [validateSpans] is the consumer: it asks
  /// whether a short span segmentation reported is really a different voice.
  ///
  /// Returns one map per region, speaker to cosine similarity. A region that
  /// could not be embedded -- too short for CAM++ -- yields an empty map, which
  /// the sequence decoder treats as "no acoustic opinion" rather than as
  /// evidence against.
  Future<List<Map<int, double>>> similaritiesFor({
    required String wavPath,
    required List<SpeakerSpan> spans,
    required List<WordTiming> words,
    required List<int?> assigned,
    required List<({int startMs, int endMs})> regions,
    SpeakerRefinement config = const SpeakerRefinement(),
  }) async {
    if (regions.isEmpty) return const [];

    // Reuses refinement's own reference selection so both stages learn a
    // speaker's voice from exactly the same audio. References come from span
    // geometry, so they do not move with the transcription model.
    final plan = planRefinement(
      spans: spans,
      words: words,
      assigned: assigned,
      config: config,
    );

    final diarizer = SpeakerDiarizer();
    await diarizer.ensureModelsReady();
    final supportDir = await getApplicationSupportDirectory();
    final modelPath =
        p.join(supportDir.path, SpeakerDiarizer.embeddingModelFile);

    return _spawnSimilarities(
      wavPath: wavPath,
      embeddingModelPath: modelPath,
      references: plan.references,
      regions: regions,
      config: config,
    );
  }

  /// Sendable-only parameters, for the reason spelled out on [_spawn].
  static Future<List<Map<int, double>>> _spawnSimilarities({
    required String wavPath,
    required String embeddingModelPath,
    required Map<int, List<({int startMs, int endMs})>> references,
    required List<({int startMs, int endMs})> regions,
    required SpeakerRefinement config,
  }) {
    return Isolate.run(
      () => _runSimilarities(
        wavPath: wavPath,
        embeddingModelPath: embeddingModelPath,
        references: references,
        regions: regions,
        config: config,
      ),
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

/// Everything both isolate entrypoints need: a validated WAV, a live CAM++
/// extractor, and a region embedder over them.
///
/// Both passes previously carried their own copy of this. The duplicate was
/// deliberate at the time -- the second pass was being measured against the
/// first, and sharing code would have meant editing the function under test --
/// but that comparison is finished, so the copy is now just two places to fix
/// the same bug.
class _EmbeddingSession {
  _EmbeddingSession._(this._input, this._extractor, this._header, this._bytesPerMs);

  final RandomAccessFile _input;
  final sherpa.SpeakerEmbeddingExtractor _extractor;
  final WavHeader _header;
  final double _bytesPerMs;

  /// Opens [wavPath] and the embedding model. Throws when the audio is not the
  /// 16kHz mono 16-bit the extractor requires.
  static _EmbeddingSession open(String wavPath, String embeddingModelPath) {
    // FFI bindings are per-isolate state, so this is required here even though
    // diarization already called it on another isolate.
    sherpa.initBindings();

    final input = File(wavPath).openSync();
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
      final extractor = sherpa.SpeakerEmbeddingExtractor(
        config: sherpa.SpeakerEmbeddingExtractorConfig(
          model: embeddingModelPath,
          numThreads: 1,
          // Defaults to true and dumps an onnxruntime session log per call.
          debug: false,
        ),
      );
      return _EmbeddingSession._(
        input,
        extractor,
        header,
        header.sampleRate * (header.bitsPerSample ~/ 8) / 1000,
      );
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  /// Unit-length embedding of one region, or null when it cannot be computed.
  Float32List? embed(int startMs, int endMs) {
    var from = (startMs * _bytesPerMs).floor();
    var to = (endMs * _bytesPerMs).ceil();
    if (from < 0) from = 0;
    if (to > _header.dataBytes) to = _header.dataBytes;
    if (to <= from) return null;

    // Only the region is read, never the whole file: a 1.5s window is 48KB of
    // PCM against however many minutes the recording runs to.
    _input.setPositionSync(_header.dataOffset + from);
    final bytes = _input.readSync(to - from);
    if (bytes.isEmpty) return null;

    final stream = _extractor.createStream();
    try {
      stream.acceptWaveform(
        samples: pcm16ToFloat32(bytes),
        sampleRate: _header.sampleRate,
      );
      stream.inputFinished();
      // Not enough audio to characterise a voice. Treated the same as a failed
      // computation: skip the region, change nothing.
      if (!_extractor.isReady(stream)) return null;
      final embedding = _extractor.compute(stream);
      return embedding.isEmpty ? null : embedding;
    } finally {
      stream.free();
    }
  }

  /// One averaged voice print per speaker.
  ///
  /// Each proposed reference is split in half and both halves embedded. If they
  /// do not sound like each other, the span holds more than one voice -- a turn
  /// segmentation never reported -- and learning from it would fold the wrong
  /// person into this speaker's print. Testing that acoustically is what
  /// replaced guessing at it from span length and sentence count, which
  /// depended on how whisper happened to segment and so changed with the
  /// transcription model.
  Map<int, Float32List> voicePrints(
    Map<int, List<EmbedRegion>> references,
    SpeakerRefinement config,
  ) {
    final prints = <int, Float32List>{};
    references.forEach((speaker, regions) {
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
    return prints;
  }

  void close() {
    _extractor.free();
    _input.closeSync();
  }
}

List<RefinementDecision> _runRefinement({
  required String wavPath,
  required String embeddingModelPath,
  required RefinementPlan plan,
  required SpeakerRefinement config,
}) {
  final session = _EmbeddingSession.open(wavPath, embeddingModelPath);

  try {
    // Voice prints first. A speaker without one cannot win a reassignment, and
    // cannot lose one either.
    final prints = session.voicePrints(plan.references, config);
    if (prints.length < 2) return const [];

    final decisions = <RefinementDecision>[];
    for (final candidate in plan.candidates) {
      final vector = unitVector(session.embed(candidate.startMs, candidate.endMs));
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
    session.close();
  }
}

List<Map<int, double>> _runSimilarities({
  required String wavPath,
  required String embeddingModelPath,
  required Map<int, List<({int startMs, int endMs})>> references,
  required List<({int startMs, int endMs})> regions,
  required SpeakerRefinement config,
}) {
  final session = _EmbeddingSession.open(wavPath, embeddingModelPath);

  try {
    final prints = session.voicePrints(references, config);
    // Fewer than two voices to compare against makes every similarity
    // meaningless rather than merely weak, so say nothing at all.
    if (prints.length < 2) {
      return List<Map<int, double>>.filled(regions.length, const {});
    }

    return [
      for (final region in regions)
        () {
          final vector = unitVector(session.embed(region.startMs, region.endMs));
          if (vector == null) return const <int, double>{};
          return <int, double>{
            for (final entry in prints.entries)
              entry.key: cosineSimilarity(vector, entry.value),
          };
        }(),
    ];
  } finally {
    session.close();
  }
}

@Riverpod(keepAlive: true)
SpeakerRefiner speakerRefiner(Ref ref) => SpeakerRefiner();
