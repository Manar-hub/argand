import 'dart:io';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:argand/core/text/sentence_boundaries.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Diagnostic, not a pass/fail test.
///
/// **The question it answers.** On `alberta.mp4` the employee's reply "Tokens
/// cost money." (7920-9400ms) is attributed to the boss. pyannote emits one
/// unbroken span `0:7203-12552` there and reports no second-speaker activity
/// anywhere between 7861 and 12468, and every parameter combination tried so
/// far produces byte-identical spans in that region.
///
/// That leaves two very different explanations, which no amount of parameter
/// sweeping can tell apart:
///
///  1. **The model cannot resolve the turn.** Segmentation genuinely does not
///     see a speaker change there, in which case no downstream rule and no
///     tuning will ever recover it.
///  2. **The model resolves it and the pipeline discards it.** sherpa's
///     clustering is global across the whole file; a locally-detected change
///     can be merged away when embeddings from a long region dominate.
///
/// Running the *same audio* twice — once as part of the whole file, once as an
/// isolated slice — separates them. The segmentation model sees a 10-second
/// sliding window either way, so a slice around the boundary gives it the same
/// local acoustic context while removing the global clustering pressure.
///
/// If the boundary appears in the slice, the model can see it and the problem
/// is ours to fix. If it appears in neither, tuning is genuinely exhausted.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const fixture = '/data/local/tmp/alberta.mp4';
  final converter = MediaConverter();

  /// Writes samples [startMs, endMs) of [source] into a new 16kHz mono WAV.
  Future<File> slice(File source, int startMs, int endMs, String label) async {
    final bytes = await source.readAsBytes();
    final header = WavHeader.parse(bytes);

    final bytesPerMs = header.sampleRate * header.channels *
        (header.bitsPerSample ~/ 8) / 1000;
    final blockAlign = header.channels * (header.bitsPerSample ~/ 8);

    // Rounded to whole frames; a partial frame would shift every sample.
    var from = (startMs * bytesPerMs).floor() ~/ blockAlign * blockAlign;
    var to = (endMs * bytesPerMs).ceil() ~/ blockAlign * blockAlign;
    if (from < 0) from = 0;
    if (to > header.dataBytes) to = header.dataBytes;

    final payload = Uint8List.sublistView(
      bytes,
      header.dataOffset + from,
      header.dataOffset + to,
    );

    final dir = await getApplicationSupportDirectory();
    final out = File(p.join(dir.path, 'slice-$label.wav'));
    await out.writeAsBytes([
      ...buildWavHeader(
        sampleRate: header.sampleRate,
        channels: header.channels,
        bitsPerSample: header.bitsPerSample,
        dataBytes: payload.length,
      ),
      ...payload,
    ]);
    return out;
  }

  void dump(String label, List<dynamic>? spans, int offsetMs) {
    if (spans == null) {
      debugPrint('SLICE $label: diarize returned null');
      return;
    }
    debugPrint('SLICE $label: ${spans.length} spans');
    for (var i = 0; i < spans.length; i += 4) {
      final chunk = spans.skip(i).take(4).map((s) =>
          '${s.speaker}:${s.startMs + offsetMs}-${s.endMs + offsetMs}');
      debugPrint('SLICE $label [$i] ${chunk.join(' ')}');
    }
  }

  testWidgets(
    'does pyannote find the turn when the region is diarized alone',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue,
          reason: 'Missing $fixture -- adb push it first');

      final media = await converter.importToAppStorage(
        projectId: 'slice-probe',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      // 1. The whole file, for the baseline every other measurement used.
      dump('whole', await SpeakerDiarizer().diarize(wav.path), 0);

      // 2. The slice already known to resolve the turn. Diarization is
      //    deterministic under fixed input, so if this does not reproduce its
      //    previous boundaries the slicing helper is corrupting the audio and
      //    nothing else below can be trusted.
      final control = await slice(File(wav.path), 5000, 13000, 'control');
      dump('control-5000-13000',
          await SpeakerDiarizer().diarize(control.path), 5000);
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'window sweep: how often does each boundary survive',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue,
          reason: 'Missing $fixture -- adb push it first');

      final media = await converter.importToAppStorage(
        projectId: 'sweep-probe',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);
      final wavFile = File(wav.path);

      /// How close a reported speaker change must be to count as finding the
      /// target. Generous, because diarization boundaries and whisper's word
      /// times are derived independently and never line up exactly.
      const toleranceMs = 400;

      /// Every point where the reported speaker changes, in file time.
      List<int> boundariesOf(List<SpeakerSpan> spans, int offsetMs) {
        final ordered = [...spans]..sort((a, b) => a.startMs.compareTo(b.startMs));
        final points = <int>[];
        for (var i = 1; i < ordered.length; i++) {
          if (ordered[i].speaker == ordered[i - 1].speaker) continue;
          // A change is reported wherever a new speaker's span opens.
          points.add(ordered[i].startMs + offsetMs);
        }
        return points;
      }

      /// One sweep over a region, scored against the boundaries that should
      /// exist there. Returns hits per target so the caller can report rates.
      Future<void> sweepRegion({
        required String label,
        required int fromMs,
        required int toMs,
        required List<int> targets,
        List<int> widths = const [8000, 10000, 12000],
        int stepMs = 750,
      }) async {
        final hits = {for (final t in targets) t: 0};
        var runs = 0;

        for (final width in widths) {
          // 750ms steps rather than a finer grid: each run costs a real
          // diarization pass, and the question is the shape of the hit rate,
          // not its third decimal place.
          for (var start = fromMs; start <= toMs; start += stepMs) {
            final end = start + width;
            final piece =
                await slice(wavFile, start, end, 'sweep-$start-$end');
            final spans = await SpeakerDiarizer().diarize(piece.path);
            await piece.delete();
            if (spans == null) continue;

            runs++;
            final found = boundariesOf(spans, start);
            final matched = <int>[];
            for (final target in targets) {
              final hit = found.any((b) => (b - target).abs() <= toleranceMs);
              if (hit) {
                hits[target] = hits[target]! + 1;
                matched.add(target);
              }
            }
            // Span and speaker counts are reported because a run that
            // collapses to a single speaker produces no boundaries at all,
            // which is indistinguishable from "found nothing near the target"
            // unless the collapse is visible.
            final speakers = spans.map((s) => s.speaker).toSet().length;
            debugPrint('SWEEP $label w=$width s=$start '
                'spans=${spans.length} spk=$speakers '
                'found=${found.join(",")} hit=${matched.join(",")}');
          }
        }

        debugPrint('SWEEP $label RATES over $runs runs:');
        for (final target in targets) {
          final pct = runs == 0 ? 0 : (hits[target]! * 100 / runs).round();
          debugPrint('SWEEP $label   target $target: ${hits[target]}/$runs '
              '($pct%)');
        }
      }

      // Region A -- the "Tokens cost money." interjection.
      //
      // Targets are the boundaries diarization *itself* reports when it does
      // resolve the turn (8642 and 9351 in the control slice), not the
      // sentence's word times. Scoring against whisper's 7920 was wrong: the
      // two passes derive boundaries independently and disagree by ~700ms at
      // the start of this sentence, so a genuine detection was being counted
      // as a miss.
      //
      // Stepped finely, because a 250ms shift of the window start is already
      // known to change the answer: the control at s=5000 finds 8642 and the
      // previous sweep at s=5250 did not.
      await sweepRegion(
        label: 'A',
        fromMs: 4000,
        toMs: 6500,
        targets: [8642, 9351],
        widths: const [8000, 10000],
        stepMs: 250,
      );
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );

  testWidgets(
    'ground truth dump and VAD comparison',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue,
          reason: 'Missing $fixture -- adb push it first');

      final media = await converter.importToAppStorage(
        projectId: 'truth-probe',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      final model = await const WhisperModelCatalog().resolve(null);
      expect(model, isNotNull, reason: 'No model is bundled in this build');

      // Diarized once and reused for both VAD settings. Diarization reads the
      // WAV directly and never sees whisper's parameters, so VAD cannot move a
      // span -- running it once and holding it fixed is what isolates VAD's
      // real effect, which is on word timings alone.
      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);
      debugPrint('TRUTH spans=${spans!.length}');

      for (final skipSilence in [true, false]) {
        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model!,
          language: TranscriptionLanguage.auto,
          skipSilence: skipSilence,
        );

        final words = <WordTiming>[
          for (final segment in result.segments ?? const [])
            if (segment.text.trim().isNotEmpty)
              (
                text: segment.text.trim(),
                startMs: segment.fromTs.inMilliseconds,
                endMs: segment.toTs.inMilliseconds,
              ),
        ];

        final assigned = assignSpeakers(words, spans);
        final tag = skipSilence ? 'VADON' : 'VADOFF';
        debugPrint('TRUTH $tag words=${words.length}');

        // One line per sentence: index, speaker, time range, text. This is the
        // list the user marks up, and it becomes the permanent scoring set.
        var start = 0;
        var index = 0;
        for (var i = 0; i < words.length; i++) {
          final isLast = i == words.length - 1;
          if (!endsSentence(words[i].text) && !isLast) continue;

          final speakers = <int?>{};
          for (var j = start; j <= i; j++) {
            speakers.add(assigned[j]);
          }
          final label = speakers.length == 1
              ? '${speakers.first}'
              : speakers.map((s) => '$s').join('/');
          final text = words.sublist(start, i + 1).map((w) => w.text).join(' ');

          debugPrint('TRUTH $tag [${index.toString().padLeft(2)}] '
              'spk=$label ${words[start].startMs}-${words[i].endMs} '
              '${text.length > 78 ? '${text.substring(0, 78)}...' : text}');

          start = i + 1;
          index++;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets(
    'is the pipeline actually deterministic run to run',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      // Extract the WAV twice from the same mp4, through the same code path.
      // If MediaCodec's output varies at all, every "identical spans" result
      // measured so far is comparing runs that did not share an input, and the
      // conclusion that parameters are inert would be unsound.
      final digests = <String>[];
      final spanDumps = <String>[];

      for (final attempt in [1, 2]) {
        final media = await converter.importToAppStorage(
          projectId: 'determinism-$attempt',
          fileName: 'alberta.mp4',
          bytes: source.openRead(),
        );
        final wav = await converter.extractWavForTranscription(media.path);
        final bytes = await File(wav.path).readAsBytes();

        // Cheap content digest: length plus a rolling sum, enough to catch any
        // sample-level difference without pulling in a hash package.
        var sum = 0;
        for (var i = 0; i < bytes.length; i++) {
          sum = (sum * 31 + bytes[i]) & 0x7fffffff;
        }
        digests.add('${bytes.length}:$sum');

        final spans = await SpeakerDiarizer().diarize(wav.path);
        spanDumps.add(spans!
            .map((s) => '${s.speaker}:${s.startMs}-${s.endMs}')
            .join(' '));
        debugPrint('DET attempt $attempt wav=${digests.last} '
            'spans=${spans.length}');
      }

      debugPrint(digests[0] == digests[1]
          ? 'DET WAV IDENTICAL'
          : 'DET WAV DIFFERS between extractions');
      debugPrint(spanDumps[0] == spanDumps[1]
          ? 'DET SPANS IDENTICAL'
          : 'DET SPANS DIFFER between runs');
      if (spanDumps[0] != spanDumps[1]) {
        debugPrint('DET run1 ${spanDumps[0]}');
        debugPrint('DET run2 ${spanDumps[1]}');
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'every bundled model, scored the same way',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'model-probe',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      // Diarized once. Spans do not depend on which whisper model runs, so
      // holding them fixed isolates the model's effect, which is entirely on
      // word timings and therefore on sentence boundaries.
      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);

      final models = await const WhisperModelCatalog().available();
      debugPrint('MODEL available=${models.map((m) => m.id).join(",")}');

      for (final model in models) {
        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );

        final words = <WordTiming>[
          for (final segment in result.segments ?? const [])
            if (segment.text.trim().isNotEmpty)
              (
                text: segment.text.trim(),
                startMs: segment.fromTs.inMilliseconds,
                endMs: segment.toTs.inMilliseconds,
              ),
        ];
        final assigned = assignSpeakers(words, spans!);

        debugPrint('MODEL ${model.id} words=${words.length}');

        var start = 0;
        var index = 0;
        for (var i = 0; i < words.length; i++) {
          final isLast = i == words.length - 1;
          if (!endsSentence(words[i].text) && !isLast) continue;

          final speakers = <int?>{};
          for (var j = start; j <= i; j++) {
            speakers.add(assigned[j]);
          }
          final label = speakers.length == 1
              ? '${speakers.first}'
              : speakers.map((s) => '$s').join('/');
          final text = words.sublist(start, i + 1).map((w) => w.text).join(' ');

          debugPrint('MODEL ${model.id} [${index.toString().padLeft(2)}] '
              'spk=$label ${words[start].startMs}-${words[i].endMs} '
              '${text.length > 70 ? '${text.substring(0, 70)}...' : text}');

          start = i + 1;
          index++;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
