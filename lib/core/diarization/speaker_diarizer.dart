import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../media/wav_codec.dart';
import '../media/wav_header.dart';
import 'speaker_span.dart';

part 'speaker_diarizer.g.dart';

/// Thrown when diarization could not run at all.
///
/// Distinct from "ran and found nothing": a file with one speaker legitimately
/// yields a single span, and a file too long to process yields null. This is
/// for a genuine failure — a model that would not load, or audio in a format
/// the pipeline should never have produced.
class DiarizationException implements Exception {
  const DiarizationException(this.message);

  final String message;

  @override
  String toString() => 'DiarizationException: $message';
}

/// Assigns speaker labels to stretches of an extracted 16kHz mono WAV.
///
/// **Two models, not one** (see docs/engine-architecture.md): a pyannote
/// segmentation model decides *when* speech changes speaker, and a CAM++
/// embedding model decides *who* each stretch sounds like. Clustering over
/// those embeddings produces the final labels.
///
/// **Why there is no streaming version, unlike the denoiser.** Diarization's
/// last stage is global: clustering compares embeddings across the entire file
/// to decide which stretches are the same person. A speaker label is a cluster
/// index with no meaning outside its own run, so two independently diarized
/// halves of a recording cannot be related to each other — chunking would not
/// cost a little accuracy, it would break the one thing diarization is for.
/// Processing therefore takes the whole waveform, which is what forces
/// [maxDuration] below. Should that limit ever need lifting, the fix is
/// cross-chunk re-identification (sherpa exposes `SpeakerEmbeddingExtractor`
/// and `SpeakerEmbeddingManager` for it), and [SpeakerSpan] exists so that
/// change stays inside this directory.
class SpeakerDiarizer {
  static const String segmentationModelFile = 'pyannote-segmentation-3.0.onnx';
  static const String embeddingModelFile = 'campplus-speaker-embedding.onnx';
  static const String _assetDirectory = 'assets/models/';

  /// Both models are trained at 16kHz, the rate the whole pipeline already
  /// uses, so nothing here resamples.
  static const int requiredSampleRate = 16000;

  /// Longest recording this will attempt.
  ///
  /// Derived from memory, not from taste. `process()` needs every sample as a
  /// `Float32List` and the native layer allocates and copies it again, so peak
  /// is roughly twice the float32 size: ~230MB at 30 minutes of 16kHz mono,
  /// and ~460MB at an hour — past what a mid-range phone will give one process.
  /// Beyond this limit [diarize] returns null and the import still produces a
  /// full transcript, because losing speaker labels is a far smaller harm than
  /// losing the import.
  ///
  /// Not yet validated against a real device; see docs/progress.md open debts.
  static const Duration maxDuration = Duration(minutes: 30);

  /// How readily two stretches of speech are called the same person.
  ///
  /// Higher merges more, yielding *fewer* speakers; lower splits more. Both
  /// failure directions are silent -- two people fused into one, or one
  /// person appearing as two halfway through -- so this is measured rather
  /// than guessed. See docs/engineering-notes.md for the sweep behind the
  /// current value.
  static const double defaultClusteringThreshold = 0.75;

  Future<String> _modelPath(String fileName) async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, fileName);
  }

  /// Copies both models out of the bundle on first use (~33MB total).
  Future<void> ensureModelsReady() async {
    for (final fileName in [segmentationModelFile, embeddingModelFile]) {
      final file = File(await _modelPath(fileName));
      if (await file.exists()) continue;
      final asset = await rootBundle.load('$_assetDirectory$fileName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      );
    }
  }

  /// Labels the speakers in [wavPath].
  ///
  /// Returns null — rather than throwing — when the recording is longer than
  /// [maxDuration]. Callers should treat that as "no speaker information",
  /// which is exactly what they must already handle for a file where
  /// diarization is switched off.
  ///
  /// [onProgress] receives 0-100 as the pass advances.
  Future<List<SpeakerSpan>?> diarize(
    String wavPath, {
    void Function(int percent)? onProgress,
    double clusteringThreshold = defaultClusteringThreshold,
  }) async {
    await ensureModelsReady();
    // Resolved here rather than inside the isolate: path_provider is a
    // platform-channel call, and platform channels exist only on the isolate
    // that owns the Flutter engine.
    final segmentation = await _modelPath(segmentationModelFile);
    final embedding = await _modelPath(embeddingModelFile);

    final progress = ReceivePort();
    progress.listen((message) {
      if (message is int) onProgress?.call(message);
    });

    // Hoisted out of the closure deliberately. Writing `progress.sendPort`
    // inside it would capture `progress` -- the ReceivePort, which is *not*
    // sendable -- and Isolate.run would fail with "object is unsendable"
    // before running a line of the body. Capturing the SendPort alone is fine,
    // and is what lets the native progress callback (which fires on the worker
    // isolate) reach the UI. sherpa's FFI bindings are per-isolate state, so
    // _runDiarization initialises them itself.
    final sendPort = progress.sendPort;

    try {
      return await Isolate.run(
        () => _runDiarization(
          wavPath: wavPath,
          segmentationModelPath: segmentation,
          embeddingModelPath: embedding,
          clusteringThreshold: clusteringThreshold,
          progress: sendPort,
        ),
      );
    } finally {
      progress.close();
    }
  }
}

List<SpeakerSpan>? _runDiarization({
  required String wavPath,
  required String segmentationModelPath,
  required String embeddingModelPath,
  required double clusteringThreshold,
  required SendPort progress,
}) {
  sherpa.initBindings();

  final input = File(wavPath).openSync();
  sherpa.OfflineSpeakerDiarization? diarizer;

  try {
    final WavHeader header;
    try {
      header = WavHeader.parse(input.readSync(4096));
    } on FormatException catch (error) {
      throw DiarizationException(
        'Diarization could not read its input: ${error.message}',
      );
    }

    if (header.sampleRate != SpeakerDiarizer.requiredSampleRate ||
        header.channels != 1 ||
        header.bitsPerSample != 16) {
      throw DiarizationException(
        'Diarization needs ${SpeakerDiarizer.requiredSampleRate}Hz mono 16-bit '
        'audio but was given ${header.sampleRate}Hz/${header.channels}ch/'
        '${header.bitsPerSample}-bit.',
      );
    }

    // Checked before anything is allocated -- the whole point of the limit is
    // to avoid the allocation.
    if (header.duration > SpeakerDiarizer.maxDuration) return null;

    final samples = _readSamples(input, header);
    if (samples.isEmpty) return null;

    diarizer = sherpa.OfflineSpeakerDiarization(
      sherpa.OfflineSpeakerDiarizationConfig(
        segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
          pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
            model: segmentationModelPath,
          ),
          numThreads: 1,
          // Defaults to true and dumps an onnxruntime session log per import.
          debug: false,
        ),
        embedding: sherpa.SpeakerEmbeddingExtractorConfig(
          model: embeddingModelPath,
          numThreads: 1,
          debug: false,
        ),
        // numClusters -1 means "work out how many speakers there are", which
        // is the only honest setting for arbitrary imported media -- the count
        // is exactly what we do not know. The threshold then decides how
        // readily two stretches are called the same person: higher merges more,
        // yielding fewer speakers. 0.5 is sherpa's own default and is
        // untuned here; tune it against real multi-speaker media before
        // changing it, because both failure directions are silent.
        clustering: sherpa.FastClusteringConfig(
          numClusters: -1,
          threshold: clusteringThreshold,
        ),
        minDurationOn: 0.2,
        minDurationOff: 0.5,
      ),
    );

    if (diarizer.sampleRate != header.sampleRate) {
      throw DiarizationException(
        'Model expects ${diarizer.sampleRate}Hz but the audio is '
        '${header.sampleRate}Hz.',
      );
    }

    final segments = diarizer.processWithCallback(
      samples: samples,
      callback: (processed, total) {
        if (total > 0) progress.send((processed * 100) ~/ total);
        // Non-zero would ask the native side to stop.
        return 0;
      },
    );

    return [
      for (final segment in segments)
        SpeakerSpan(
          startMs: (segment.start * 1000).round(),
          endMs: (segment.end * 1000).round(),
          speaker: segment.speaker,
        ),
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
  } finally {
    diarizer?.free();
    input.closeSync();
  }
}

/// Reads the whole `data` chunk as normalised floats.
///
/// Allocated once at the known sample count and filled block by block, rather
/// than reading the file to a byte list and converting. Both forms end up
/// holding the same `Float32List`; this one avoids also holding the raw bytes
/// beside it, which at the 30-minute limit is ~58MB that need not exist.
Float32List _readSamples(RandomAccessFile input, WavHeader header) {
  final totalSamples = header.dataBytes ~/ 2;
  final samples = Float32List(totalSamples);

  input.setPositionSync(header.dataOffset);
  const blockBytes = 1 << 20;
  var written = 0;
  while (written < totalSamples) {
    final block = input.readSync(blockBytes);
    // A `data` size can overstate what the file holds if the writer was
    // interrupted; stop at the real end rather than looping forever.
    if (block.isEmpty) break;
    written += pcm16ToFloat32Into(block, samples, written);
  }

  return written == totalSamples
      ? samples
      : Float32List.sublistView(samples, 0, written);
}

@Riverpod(keepAlive: true)
SpeakerDiarizer speakerDiarizer(Ref ref) => SpeakerDiarizer();
