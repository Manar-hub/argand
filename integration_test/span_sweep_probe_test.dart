import 'dart:io';

import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/diarization_truth.dart';

/// How well do diarization's **spans** match the labelled turns, and which
/// segmentation parameters move that?
///
/// **Why score spans directly.** Every previous sweep in this project measured
/// parameters through the whole pipeline — transcribe, assign, refine — which
/// is slow, and which hides where an error came from. Spans are produced from
/// audio alone: whisper is not involved, no model is selected, and the result
/// is identical for every transcription model. So span quality can be scored on
/// its own, in seconds per setting rather than minutes, and a defect found here
/// is a defect no downstream rule can be blamed for.
///
/// This exists because a span dump showed the shipped configuration reporting
/// one 6.3-second block of a single speaker over a stretch the labels say
/// alternates four times, plus an 810ms handover in the middle of a sentence
/// that the labels say never happens. Those two facts explain a model-dependent
/// failure completely: with a spurious edge present, whether a word lands left
/// or right of it decides its speaker, so two models that time the same word
/// differently disagree — and no attribution rule downstream can undo it.
///
/// **The metric is per-millisecond agreement**, after mapping diarization's
/// arbitrary cluster ids onto the labels' by best overlap. Overlapping spans
/// are resolved by preferring the shorter span, matching how attribution breaks
/// that tie. Silence the labels do not cover is not scored.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('SWEEP $message');

  /// Speaker diarization claims at [ms], preferring the shortest covering span
  /// — the more specific claim, which is the tie-break attribution already
  /// uses.
  int? speakerAt(List<SpeakerSpan> spans, int ms) {
    int? best;
    var bestDuration = 1 << 30;
    for (final span in spans) {
      if (ms < span.startMs || ms >= span.endMs) continue;
      if (span.durationMs < bestDuration) {
        bestDuration = span.durationMs;
        best = span.speaker;
      }
    }
    return best;
  }

  /// Per-millisecond agreement with the labelled turns, sampled every 10ms.
  ///
  /// Cluster ids are arbitrary, so every mapping of observed ids onto label
  /// ids is tried and the best kept — the same approach the word scorer uses.
  ({double agreement, int scored, Map<int, int> mapping}) scoreSpans(
    List<SpeakerSpan> spans,
    DiarizationTruth truth,
  ) {
    final observed = {for (final span in spans) span.speaker}.toList()..sort();
    final expected = truth.speakers.toList()..sort();
    if (observed.isEmpty || expected.isEmpty) {
      return (agreement: 0, scored: 0, mapping: const {});
    }

    final samples = <(int, int)>[];
    for (final turn in truth.turns) {
      for (var ms = turn.startMs; ms < turn.endMs; ms += 10) {
        final seen = speakerAt(spans, ms);
        if (seen == null) continue;
        samples.add((seen, turn.speaker));
      }
    }
    if (samples.isEmpty) return (agreement: 0, scored: 0, mapping: const {});

    var bestHits = -1;
    var bestMapping = <int, int>{};
    void tryMapping(int index, Map<int, int> mapping) {
      if (index == observed.length) {
        var hits = 0;
        for (final (seen, want) in samples) {
          if (mapping[seen] == want) hits++;
        }
        if (hits > bestHits) {
          bestHits = hits;
          bestMapping = Map.of(mapping);
        }
        return;
      }
      for (final candidate in expected) {
        mapping[observed[index]] = candidate;
        tryMapping(index + 1, mapping);
      }
      mapping.remove(observed[index]);
    }

    if (observed.length <= 6) tryMapping(0, {});

    return (
      agreement: bestHits / samples.length,
      scored: samples.length,
      mapping: bestMapping,
    );
  }

  for (final (clip, truthFile) in const [
    ('two_speakers.wav', 'two_speakers.truth.json'),
    ('alberta.mp4', 'alberta.truth.json'),
  ]) {
    testWidgets('span parameter sweep on $clip', (tester) async {
      final media = File('$tmp/$clip');
      final labels = File('$tmp/$truthFile');
      expect(await media.exists(), isTrue, reason: 'adb push $clip first');
      expect(await labels.exists(), isTrue, reason: 'adb push $truthFile first');

      final truth = parseDiarizationTruth(await labels.readAsString());

      final imported = await converter.importToAppStorage(
        projectId: 'span-sweep-probe',
        fileName: clip,
        bytes: media.openRead(),
      );
      final wav = clip.toLowerCase().endsWith('.wav')
          ? imported
          : await converter.extractWavForTranscription(imported.path);

      log('');
      log('===== $clip : ${truth.turns.length} labelled turns =====');

      Future<void> run(
        String label, {
        double threshold = SpeakerDiarizer.defaultClusteringThreshold,
        double minOn = SpeakerDiarizer.defaultMinDurationOn,
        double minOff = SpeakerDiarizer.defaultMinDurationOff,
        int clusters = SpeakerDiarizer.defaultNumClusters,
        bool dump = false,
      }) async {
        final spans = await SpeakerDiarizer().diarize(
              wav.path,
              clusteringThreshold: threshold,
              minDurationOn: minOn,
              minDurationOff: minOff,
              numClusters: clusters,
            ) ??
            const <SpeakerSpan>[];
        final score = scoreSpans(spans, truth);
        final speakers = {for (final span in spans) span.speaker}.length;
        log('$clip ${label.padRight(34)} spans=${spans.length.toString().padLeft(2)} '
            'speakers=$speakers '
            'agree=${(score.agreement * 100).toStringAsFixed(1)}% '
            'of ${score.scored} samples  mapping=${score.mapping}');
        if (dump) {
          for (var i = 0; i < spans.length; i++) {
            final s = spans[i];
            log('$clip     span ${i.toString().padLeft(2)} spk${s.speaker} '
                '${s.startMs}-${s.endMs} (${s.durationMs}ms)');
          }
        }
      }

      await run('SHIPPED (0.75/0.2/0.5/-1)', dump: true);

      for (final threshold in const [0.5, 0.6, 0.65, 0.7, 0.8, 0.9]) {
        await run('threshold=$threshold', threshold: threshold);
      }
      for (final minOff in const [0.0, 0.1, 0.25]) {
        await run('minDurationOff=$minOff', minOff: minOff);
      }
      for (final minOn in const [0.0, 0.1, 0.3]) {
        await run('minDurationOn=$minOn', minOn: minOn);
      }
      await run('numClusters=2', clusters: 2);
      await run('numClusters=2 minOff=0.0', clusters: 2, minOff: 0.0);
      await run('numClusters=2 minOff=0.0 minOn=0.0',
          clusters: 2, minOff: 0.0, minOn: 0.0, dump: true);
      await run('minOff=0.0 minOn=0.1 thr=0.6',
          threshold: 0.6, minOff: 0.0, minOn: 0.1, dump: true);
    }, timeout: const Timeout(Duration(minutes: 45)));
  }
}
