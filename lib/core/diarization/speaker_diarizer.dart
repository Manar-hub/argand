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
class DiarizationException implements Exception {
  const DiarizationException(this.message);

  final String message;

  @override
  String toString() => 'DiarizationException: $message';
}

/// Assigns speaker labels to stretches of an extracted 16kHz mono WAV.
class SpeakerDiarizer {
  static const String segmentationModelFile = 'pyannote-segmentation-3.0.onnx';
  static const String embeddingModelFile = 'campplus-speaker-embedding.onnx';
  static const String _assetDirectory = 'assets/models/';

  /// Both models are trained at 16kHz, the rate the whole pipeline already
  /// uses, so nothing here resamples.
  static const int requiredSampleRate = 16000;

  /// Longest recording this will attempt.
  static const Duration maxDuration = Duration(minutes: 30);

  /// How readily two stretches of speech are called the same person.
  static const double defaultClusteringThreshold = 0.75;

  /// How many speakers to find, or -1 to work it out.
  static const int defaultNumClusters = -1;

  /// Shortest turn the engine will keep, in seconds.
  static const double defaultMinDurationOn = 0.2;

  /// Largest same-speaker gap that gets bridged, in seconds.
  static const double defaultMinDurationOff = 0.5;

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
  Future<List<SpeakerSpan>?> diarize(
    String wavPath, {
    void Function(int percent)? onProgress,
    double clusteringThreshold = defaultClusteringThreshold,
    double minDurationOn = defaultMinDurationOn,
    double minDurationOff = defaultMinDurationOff,
    int numClusters = defaultNumClusters,
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

    try {
      return await _spawn(
        wavPath: wavPath,
        segmentationModelPath: segmentation,
        embeddingModelPath: embedding,
        clusteringThreshold: clusteringThreshold,
        minDurationOn: minDurationOn,
        minDurationOff: minDurationOff,
        numClusters: numClusters,
        progress: progress.sendPort,
      );
    } finally {
      progress.close();
    }
  }

  /// Spawns the worker.
  static Future<List<SpeakerSpan>?> _spawn({
    required String wavPath,
    required String segmentationModelPath,
    required String embeddingModelPath,
    required double clusteringThreshold,
    required double minDurationOn,
    required double minDurationOff,
    required int numClusters,
    required SendPort progress,
  }) {
    return Isolate.run(
      () => _runDiarization(
        wavPath: wavPath,
        segmentationModelPath: segmentationModelPath,
        embeddingModelPath: embeddingModelPath,
        clusteringThreshold: clusteringThreshold,
        minDurationOn: minDurationOn,
        minDurationOff: minDurationOff,
        numClusters: numClusters,
        progress: progress,
      ),
    );
  }
}

List<SpeakerSpan>? _runDiarization({
  required String wavPath,
  required String segmentationModelPath,
  required String embeddingModelPath,
  required double clusteringThreshold,
  required double minDurationOn,
  required double minDurationOff,
  required int numClusters,
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
        // numClusters -1 means "work out how many speakers there are", which is
        // the only honest setting for arbitrary imported media -- the count is
        // exactly what we do not know.
        clustering: sherpa.FastClusteringConfig(
          numClusters: numClusters,
          threshold: clusteringThreshold,
        ),
        minDurationOn: minDurationOn,
        minDurationOff: minDurationOff,
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
