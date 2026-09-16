import 'dart:io';
import 'dart:math' as math;

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_refinement.dart';
import 'package:argand/core/diarization/speaker_refiner.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/media/wav_codec.dart';
import 'package:argand/core/media/wav_header.dart';
import 'package:argand/core/text/sentence_boundaries.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

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
        clipId: 'clip',
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
        clipId: 'clip',
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
        clipId: 'clip',
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
          clipId: 'clip',
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
        clipId: 'clip',
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

  testWidgets(
    'would CAM++ separate the speakers in the failing regions',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'cam-probe',
        clipId: 'clip',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);

      await SpeakerDiarizer().ensureModelsReady();
      final supportDir = await getApplicationSupportDirectory();
      final embeddingModel = p.join(
        supportDir.path,
        SpeakerDiarizer.embeddingModelFile,
      );

      final bytes = await File(wav.path).readAsBytes();
      final header = WavHeader.parse(bytes);
      final bytesPerMs =
          header.sampleRate * header.channels * (header.bitsPerSample ~/ 8) / 1000;

      /// Float samples for [startMs, endMs), straight out of the WAV.
      Float32List samplesFor(int startMs, int endMs) {
        var from = (startMs * bytesPerMs).floor();
        var to = (endMs * bytesPerMs).ceil();
        if (from < 0) from = 0;
        if (to > header.dataBytes) to = header.dataBytes;
        return pcm16ToFloat32(
          Uint8List.sublistView(
            bytes,
            header.dataOffset + from,
            header.dataOffset + to,
          ),
        );
      }

      sherpa.initBindings();
      final extractor = sherpa.SpeakerEmbeddingExtractor(
        config: sherpa.SpeakerEmbeddingExtractorConfig(
          model: embeddingModel,
          numThreads: 1,
          // Defaults to true and dumps an onnxruntime session log per call.
          debug: false,
        ),
      );
      debugPrint('CAM dim=${extractor.dim}');

      Float32List? embed(int startMs, int endMs) {
        final stream = extractor.createStream();
        try {
          stream.acceptWaveform(
            samples: samplesFor(startMs, endMs),
            sampleRate: header.sampleRate,
          );
          stream.inputFinished();
          if (!extractor.isReady(stream)) return null;
          final e = extractor.compute(stream);
          return e.isEmpty ? null : e;
        } finally {
          stream.free();
        }
      }

      Float32List? unit(Float32List? v) {
        if (v == null || v.isEmpty) return null;
        var sum = 0.0;
        for (final x in v) {
          sum += x * x;
        }
        final n = sum <= 0 ? 0.0 : 1.0 / math.sqrt(sum);
        if (n == 0) return null;
        final out = Float32List(v.length);
        for (var i = 0; i < v.length; i++) {
          out[i] = v[i] * n;
        }
        return out;
      }

      double cosine(Float32List a, Float32List b) {
        var dot = 0.0;
        for (var i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
        }
        return dot;
      }

      // Regions under test, and controls. Truth from the committed fixture.
      const candidates = <(String, int, int, int)>[
        ('Tokens cost money. [FAILING]', 7920, 9400, 1),
        ('Of course..that makes sense [FAILING]', 38650, 39650, 1),
        ('Yeah I know tokens cost money [control]', 9400, 12390, 0),
        ('Okay thats all the tokens [control]', 5120, 7170, 1),
        ('All that Im using AI for [control]', 17050, 19240, 1),
        ('Can we just please tone it down [control]', 15380, 17050, 0),
        // Short regions, to find where CAM++ stops being usable. "What do you
        // mean?" is the other currently-wrong sentence and is only 750ms.
        ('What do you mean? [FAILING 750ms]', 7170, 7920, 0),
        ('Appie? [390ms]', 2390, 2780, 1),
        ('AI is expensive. [890ms]', 12390, 13280, 1),
        ('Yeah, I am sure you do. [1000ms]', 37650, 38650, 1),
      ];

      // Voice prints from spans that overlap no other speaker's span and none
      // of the regions above. The span enclosing "Tokens cost money." is itself
      // mixed-speaker, so including it would put the very voice under test into
      // the reference it is being compared against.
      final prints = <int, Float32List>{};
      for (final speaker in spans!.map((s) => s.speaker).toSet()) {
        final refs = <Float32List>[];
        for (final span in spans.where((s) => s.speaker == speaker)) {
          final overlapsOther = spans.any((o) =>
              o.speaker != speaker && o.overlapWith(span.startMs, span.endMs) > 0);
          final overlapsCandidate = candidates
              .any((c) => span.overlapWith(c.$2, c.$3) > 0);
          if (overlapsOther || overlapsCandidate) continue;
          if (span.durationMs < 1500) continue;
          final e = unit(embed(span.startMs, span.endMs));
          if (e != null) refs.add(e);
          debugPrint('CAM ref spk$speaker ${span.startMs}-${span.endMs}');
        }
        if (refs.isEmpty) {
          debugPrint('CAM spk$speaker: NO CLEAN REFERENCE');
          continue;
        }
        final mean = Float32List(extractor.dim);
        for (final r in refs) {
          for (var i = 0; i < mean.length; i++) {
            mean[i] += r[i];
          }
        }
        final centroid = unit(mean);
        if (centroid != null) prints[speaker] = centroid;
        debugPrint('CAM spk$speaker built from ${refs.length} span(s)');
      }

      for (final (label, startMs, endMs, want) in candidates) {
        final e = unit(embed(startMs, endMs));
        if (e == null) {
          debugPrint('CAM "$label" ${endMs - startMs}ms: NO EMBEDDING');
          continue;
        }
        final scores = <int, double>{};
        prints.forEach((spk, c) => scores[spk] = cosine(e, c));
        final ranked = scores.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final margin = ranked.length > 1 ? ranked[0].value - ranked[1].value : 0.0;
        debugPrint('CAM "$label" ${endMs - startMs}ms want=$want '
            'best=spk${ranked.first.key} '
            'scores=${ranked.map((r) => "spk${r.key}:${r.value.toStringAsFixed(3)}").join(" ")} '
            'margin=${margin.toStringAsFixed(3)} '
            '${ranked.first.key == want ? "CORRECT" : "WRONG"}');
      }

      extractor.free();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'refinement end to end: does it fix the failing sentences',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'refine-e2e',
        clipId: 'clip',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      final model = await const WhisperModelCatalog().resolve(null);
      final result = await WhisperService().transcribeWav(
        wav.path,
        model: model!,
        language: TranscriptionLanguage.auto,
        skipSilence: true,
      );
      final words = wordTimingsOf(result);

      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);

      final before = assignSpeakers(words, spans!);
      final refined = await SpeakerRefiner().refine(
        wavPath: wav.path,
        spans: spans,
        words: words,
        assigned: before,
      );
      final after = assignSpeakers(words, refined.spans);

      debugPrint('E2E embeddings=${refined.embeddedRegions} '
          'candidates=${refined.decisions.length} '
          'moved=${refined.movedCount} ${refined.elapsedMs}ms');
      for (final d in refined.decisions) {
        final scores = d.similarities.entries
            .map((e) => 'spk${e.key}:${e.value.toStringAsFixed(3)}')
            .join(' ');
        debugPrint('E2E cand ${d.candidate.startMs}-${d.candidate.endMs} '
            'was=spk${d.candidate.currentSpeaker} $scores '
            '${d.outcome.name}${d.newSpeaker != null ? " ->spk${d.newSpeaker}" : ""}');
      }

      // Per-sentence, before and after, so a fix and a regression look
      // different rather than both being "something changed".
      var start = 0;
      var index = 0;
      for (var i = 0; i < words.length; i++) {
        final isLast = i == words.length - 1;
        if (!endsSentence(words[i].text) && !isLast) continue;

        String label(List<int?> a) {
          final s = <int?>{};
          for (var j = start; j <= i; j++) {
            s.add(a[j]);
          }
          return s.length == 1 ? '${s.first}' : s.join('/');
        }

        final b = label(before);
        final a = label(after);
        final text = words.sublist(start, i + 1).map((w) => w.text).join(' ');
        debugPrint('E2E [${index.toString().padLeft(2)}] $b->$a '
            '${b == a ? "   " : "CHG"} '
            '${text.length > 56 ? '${text.substring(0, 56)}...' : text}');

        start = i + 1;
        index++;
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets(
    'cross-model agreement: does refinement depend on the whisper model',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'agreement',
        clipId: 'clip',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      // Diarized once and shared. Spans do not depend on whisper, so holding
      // them fixed means any disagreement below is attributable to the
      // transcription model alone -- which is exactly the question.
      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);

      final models = await const WhisperModelCatalog().available();

      /// Speaker at each 10ms tick, or null where no word covers it.
      Future<List<int?>> timelineFor(
        WhisperModelDescriptor model, {
        required bool refine,
      }) async {
        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );
        final words = wordTimingsOf(result);
        var effective = spans!;
        if (refine) {
          effective = (await SpeakerRefiner().refine(
            wavPath: wav.path,
            spans: spans,
            words: words,
            assigned: assignSpeakers(words, spans),
          ))
              .spans;
        }
        final assigned = assignSpeakers(words, effective);

        final lastMs = words.isEmpty ? 0 : words.last.endMs;
        final ticks = List<int?>.filled(lastMs ~/ 10 + 1, null);
        for (var i = 0; i < words.length; i++) {
          for (var t = words[i].startMs ~/ 10; t <= words[i].endMs ~/ 10; t++) {
            if (t < ticks.length) ticks[t] = assigned[i];
          }
        }
        return ticks;
      }

      void report(String label, List<int?> a, List<int?> b) {
        final n = a.length < b.length ? a.length : b.length;
        var shared = 0;
        var same = 0;
        for (var i = 0; i < n; i++) {
          if (a[i] == null || b[i] == null) continue;
          shared++;
          if (a[i] == b[i]) same++;
        }
        final pct = shared == 0 ? 0.0 : same * 100 / shared;
        debugPrint('AGREE $label $same/$shared ticks '
            '${pct.toStringAsFixed(1)}%');
      }

      // Without refinement first: the floor set by whisper's own timing
      // differences, which no attribution rule can remove.
      final rawBase = await timelineFor(models[0], refine: false);
      final rawSmall = await timelineFor(models[1], refine: false);
      report('no-refinement ${models[0].id} vs ${models[1].id}', rawBase, rawSmall);

      final refBase = await timelineFor(models[0], refine: true);
      final refSmall = await timelineFor(models[1], refine: true);
      report('refined       ${models[0].id} vs ${models[1].id}', refBase, refSmall);
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );

  testWidgets(
    'final table: what the app shows now, per model',
    (tester) async {
      final source = File(fixture);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'final-table',
        clipId: 'clip',
        fileName: 'alberta.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);

      for (final model in await const WhisperModelCatalog().available()) {
        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );
        final words = wordTimingsOf(result);

        // Exactly what the import pipeline does, in the same order.
        final baseline = assignSpeakers(words, spans!);
        final refined = await SpeakerRefiner().refine(
          wavPath: wav.path,
          spans: spans,
          words: words,
          assigned: baseline,
        );
        final finalAssignment = assignSpeakers(words, refined.spans);

        debugPrint('TABLE ${model.id} candidates=${refined.decisions.length} '
            'moved=${refined.movedCount} ${refined.elapsedMs}ms');
        for (final d in refined.decisions.where(
            (d) => d.outcome == RefinementOutcome.moved)) {
          debugPrint('TABLE ${model.id} MOVED ${d.candidate.startMs}-'
              '${d.candidate.endMs} spk${d.candidate.currentSpeaker}'
              '->spk${d.newSpeaker}');
        }

        var start = 0;
        var index = 0;
        for (var i = 0; i < words.length; i++) {
          final isLast = i == words.length - 1;
          if (!endsSentence(words[i].text) && !isLast) continue;

          final speakers = <int?>{};
          for (var j = start; j <= i; j++) {
            speakers.add(finalAssignment[j]);
          }
          // Display numbering is cluster + 1, as project_screen renders it.
          final shown = speakers.length == 1 && speakers.first != null
              ? 'Speaker ${speakers.first! + 1}'
              : speakers.map((s) => s == null ? '?' : 'S${s + 1}').join('/');
          final text = words.sublist(start, i + 1).map((w) => w.text).join(' ');

          debugPrint('TABLE ${model.id} [${index.toString().padLeft(2)}] '
              '$shown | ${words[start].startMs}-${words[i].endMs} | '
              '${text.length > 62 ? '${text.substring(0, 62)}...' : text}');

          start = i + 1;
          index++;
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );

  testWidgets(
    'two_speakers: full pipeline with decisions and similarities',
    (tester) async {
      const clip = '/data/local/tmp/two_speakers.wav';
      final source = File(clip);
      expect(await source.exists(), isTrue, reason: 'Missing $clip');

      final media = await converter.importToAppStorage(
        projectId: 'two-spk',
        clipId: 'clip',
        fileName: 'two_speakers.wav',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);

      final spans = await SpeakerDiarizer().diarize(wav.path);
      expect(spans, isNotNull);
      for (var i = 0; i < spans!.length; i += 4) {
        debugPrint('TWO spans[$i] ${spans.skip(i).take(4).map(
              (s) => '${s.speaker}:${s.startMs}-${s.endMs}',
            ).join(' ')}');
      }

      final model = await const WhisperModelCatalog().resolve(null);
      final result = await WhisperService().transcribeWav(
        wav.path,
        model: model!,
        language: TranscriptionLanguage.auto,
        skipSilence: true,
      );
      final words = wordTimingsOf(result);

      final baseline = assignSpeakers(words, spans);
      final refined = await SpeakerRefiner().refine(
        wavPath: wav.path,
        spans: spans,
        words: words,
        assigned: baseline,
      );
      final after = assignSpeakers(words, refined.spans);

      debugPrint('TWO candidates=${refined.decisions.length} '
          'moved=${refined.movedCount} embeddings=${refined.embeddedRegions} '
          '${refined.elapsedMs}ms');

      // Similarities are the number that answers "is this our rules or the
      // models?" -- margins like alberta's mean the voices separate.
      for (final d in refined.decisions) {
        final scores = d.similarities.entries
            .map((e) => 'spk${e.key}:${e.value.toStringAsFixed(3)}')
            .join(' ');
        debugPrint('TWO cand ${d.candidate.startMs}-${d.candidate.endMs} '
            'was=spk${d.candidate.currentSpeaker} $scores ${d.outcome.name}');
      }

      var start = 0;
      var index = 0;
      for (var i = 0; i < words.length; i++) {
        final isLast = i == words.length - 1;
        if (!endsSentence(words[i].text) && !isLast) continue;

        String label(List<int?> a) {
          final s = <int?>{};
          for (var j = start; j <= i; j++) {
            s.add(a[j]);
          }
          return s.length == 1 && s.first != null
              ? 'Speaker ${s.first! + 1}'
              : s.map((x) => x == null ? '?' : 'S${x + 1}').join('/');
        }

        final text = words.sublist(start, i + 1).map((w) => w.text).join(' ');
        debugPrint('TWO [${index.toString().padLeft(2)}] ${label(after)} | '
            '${words[start].startMs}-${words[i].endMs} | '
            '${text.length > 60 ? '${text.substring(0, 60)}...' : text}');

        start = i + 1;
        index++;
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );

  testWidgets(
    'diagnose sentence 8 halves on two_speakers',
    (tester) async {
      const clip = '/data/local/tmp/two_speakers.wav';
      final source = File(clip);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'diag8',
        clipId: 'clip',
        fileName: 'two_speakers.wav',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);
      final spans = await SpeakerDiarizer().diarize(wav.path);

      await SpeakerDiarizer().ensureModelsReady();
      final supportDir = await getApplicationSupportDirectory();
      final modelPath =
          p.join(supportDir.path, SpeakerDiarizer.embeddingModelFile);

      final bytes = await File(wav.path).readAsBytes();
      final header = WavHeader.parse(bytes);
      final bytesPerMs =
          header.sampleRate * header.channels * (header.bitsPerSample ~/ 8) / 1000;

      sherpa.initBindings();
      final extractor = sherpa.SpeakerEmbeddingExtractor(
        config: sherpa.SpeakerEmbeddingExtractorConfig(
          model: modelPath,
          numThreads: 1,
          debug: false,
        ),
      );

      ({Float32List? vec, double rms}) probe(int startMs, int endMs) {
        var from = (startMs * bytesPerMs).floor();
        var to = (endMs * bytesPerMs).ceil();
        if (from < 0) from = 0;
        if (to > header.dataBytes) to = header.dataBytes;
        final slice = Uint8List.sublistView(
            bytes, header.dataOffset + from, header.dataOffset + to);
        final samples = pcm16ToFloat32(slice);

        // Loudness matters: a half that is mostly silence cannot characterise
        // a voice, and would explain halves "disagreeing" without two people.
        var sum = 0.0;
        for (final s in samples) {
          sum += s * s;
        }
        final rms = samples.isEmpty ? 0.0 : math.sqrt(sum / samples.length);

        final stream = extractor.createStream();
        try {
          stream.acceptWaveform(
              samples: samples, sampleRate: header.sampleRate);
          stream.inputFinished();
          if (!extractor.isReady(stream)) return (vec: null, rms: rms);
          final e = extractor.compute(stream);
          return (vec: e.isEmpty ? null : unitVector(e), rms: rms);
        } finally {
          stream.free();
        }
      }

      // Voice prints from the clip's long clean spans.
      final prints = <int, Float32List>{};
      for (final spk in {0, 1}) {
        final refs = <Float32List>[];
        for (final s in spans!.where((s) => s.speaker == spk)) {
          if (s.durationMs < 2000) continue;
          final shared = spans.any((o) =>
              o.speaker != spk && o.overlapWith(s.startMs, s.endMs) > 0);
          if (shared) continue;
          final r = probe(s.startMs, s.endMs);
          if (r.vec != null) refs.add(r.vec!);
        }
        final c = centroidOf(refs);
        if (c != null) prints[spk] = c;
        debugPrint('D8 spk$spk prints from ${refs.length} span(s)');
      }

      void report(String label, int startMs, int endMs) {
        final r = probe(startMs, endMs);
        if (r.vec == null) {
          debugPrint('D8 $label $startMs-$endMs (${endMs - startMs}ms) '
              'rms=${r.rms.toStringAsFixed(4)} NO EMBEDDING');
          return;
        }
        final scores = prints.entries
            .map((e) => 'spk${e.key}:${cosineSimilarity(r.vec!, e.value).toStringAsFixed(3)}')
            .join(' ');
        debugPrint('D8 $label $startMs-$endMs (${endMs - startMs}ms) '
            'rms=${r.rms.toStringAsFixed(4)} $scores');
      }

      // The region, and each side of the cut segmentation reports at 17817.
      report('whole ', 16960, 18410);
      report('before', 16960, 17817);
      report('after ', 17817, 18410);

      final before = probe(16960, 17817).vec;
      final after = probe(17817, 18410).vec;
      if (before != null && after != null) {
        debugPrint('D8 coherence(before,after) = '
            '${cosineSimilarity(before, after).toStringAsFixed(3)}');
      }

      extractor.free();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'window experiment for two_speakers sentence 14',
    (tester) async {
      const clip = '/data/local/tmp/two_speakers.wav';
      final source = File(clip);
      expect(await source.exists(), isTrue);

      final media = await converter.importToAppStorage(
        projectId: 'w14',
        clipId: 'clip',
        fileName: 'two_speakers.wav',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);
      final spans = await SpeakerDiarizer().diarize(wav.path);

      await SpeakerDiarizer().ensureModelsReady();
      final supportDir = await getApplicationSupportDirectory();
      final modelPath =
          p.join(supportDir.path, SpeakerDiarizer.embeddingModelFile);

      final bytes = await File(wav.path).readAsBytes();
      final header = WavHeader.parse(bytes);
      final bytesPerMs =
          header.sampleRate * header.channels * (header.bitsPerSample ~/ 8) / 1000;

      sherpa.initBindings();
      final extractor = sherpa.SpeakerEmbeddingExtractor(
        config: sherpa.SpeakerEmbeddingExtractorConfig(
          model: modelPath,
          numThreads: 1,
          debug: false,
        ),
      );

      ({Float32List? vec, double rms}) probe(int startMs, int endMs) {
        var from = (startMs * bytesPerMs).floor();
        var to = (endMs * bytesPerMs).ceil();
        if (from < 0) from = 0;
        if (to > header.dataBytes) to = header.dataBytes;
        if (to <= from) return (vec: null, rms: 0);
        final samples = pcm16ToFloat32(Uint8List.sublistView(
            bytes, header.dataOffset + from, header.dataOffset + to));
        var sum = 0.0;
        for (final s in samples) {
          sum += s * s;
        }
        final rms = samples.isEmpty ? 0.0 : math.sqrt(sum / samples.length);
        final stream = extractor.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: header.sampleRate);
          stream.inputFinished();
          if (!extractor.isReady(stream)) return (vec: null, rms: rms);
          final e = extractor.compute(stream);
          return (vec: e.isEmpty ? null : unitVector(e), rms: rms);
        } finally {
          stream.free();
        }
      }

      final prints = <int, Float32List>{};
      for (final spk in {0, 1}) {
        final refs = <Float32List>[];
        for (final s in spans!.where((s) => s.speaker == spk)) {
          if (s.durationMs < 2000) continue;
          final shared = spans.any((o) =>
              o.speaker != spk && o.overlapWith(s.startMs, s.endMs) > 0);
          if (shared) continue;
          final r = probe(s.startMs, s.endMs);
          if (r.vec != null) refs.add(r.vec!);
        }
        final c = centroidOf(refs);
        if (c != null) prints[spk] = c;
      }

      // Sentence 14 is 26200-26780. Truth is spk1. Neighbours #13 and #15 are
      // both spk0, so any widening runs into the other speaker -- which the
      // numbers should show as the answer drifting further toward spk0.
      const variants = <(String, int, int)>[
        ('trimmed  480ms', 26250, 26730),
        ('untrimmed 580ms', 26200, 26780),
        ('+100 each  780ms', 26100, 26880),
        ('+200 each  980ms', 26000, 26980),
        ('+350 each 1280ms', 25850, 27040),
        ('left-only  780ms', 26000, 26780),
        ('right-only 780ms', 26200, 26980),
      ];

      for (final (label, from, to) in variants) {
        final r = probe(from, to);
        if (r.vec == null) {
          debugPrint('W14 $label rms=${r.rms.toStringAsFixed(4)} NO EMBEDDING');
          continue;
        }
        final s0 = cosineSimilarity(r.vec!, prints[0]!);
        final s1 = cosineSimilarity(r.vec!, prints[1]!);
        debugPrint('W14 $label rms=${r.rms.toStringAsFixed(4)} '
            'spk0:${s0.toStringAsFixed(3)} spk1:${s1.toStringAsFixed(3)} '
            'margin=${(s1 - s0).toStringAsFixed(3)} '
            '${s1 > s0 ? "CORRECT" : "wrong"}');
      }

      extractor.free();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  testWidgets(
    'collapse: why does guess.mp4 lose speakers',
    (tester) async {
      // On guess.mp4 -- a group talking fast and interrupting each other --
      // several speakers collapse onto one. That has two opposite causes and
      // they need opposite fixes:
      //
      //   * segmentation never sees the interruptions, in which case a second
      //     boundary source (whisper's turn dashes) has something to add; or
      //   * segmentation finds them and *clustering* merges them, in which case
      //     the fix is a parameter and a new mechanism would be working around
      //     a tuning problem.
      //
      // This prints the evidence to tell them apart: the raw span boundaries
      // regardless of label, then what the two clustering levers do to the
      // speaker count. `numClusters` matters because Phase 3.4 measured every
      // other sherpa parameter as inert on alberta while this one moved
      // syria.mp4, where the threshold does nothing.
      //
      // For comparison, whisper's turn dashes on this clip were measured
      // natively at 34 markers (small-q5_1, suppress_nst off, beam or VAD off),
      // and scored 16/16 recall against alberta's labels but only 1/10 against
      // two_speakers -- high precision, unreliable recall.
      const guess = '/data/local/tmp/guess.mp4';
      final source = File(guess);
      expect(await source.exists(), isTrue, reason: 'adb push guess.mp4 first');

      final media = await converter.importToAppStorage(
        projectId: 'collapse-probe',
        clipId: 'clip',
        fileName: 'guess.mp4',
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(media.path);
      debugPrint('COLLAPSE wav=${wav.path}');

      // Where the default configuration reports no speaker change at all, from
      // the first run of this probe. These are the measurement that matters:
      // total span count can move while both dead zones stay empty, which would
      // look like progress and be none.
      const deadZones = [(31, 14543), (50690, 72357)];

      /// Boundaries regardless of which cluster a span was given. This is the
      /// half of the question clustering cannot affect: if a turn time is
      /// absent here, segmentation did not report it at all.
      Future<void> report(String label, List<SpeakerSpan>? spans) async {
        if (spans == null) {
          debugPrint('COLLAPSE $label -> null (over the duration cap)');
          return;
        }
        final speakers = {for (final s in spans) s.speaker};
        final edges = <int>{};
        for (final s in spans) {
          edges..add(s.startMs)..add(s.endMs);
        }
        final sorted = edges.toList()..sort();

        final inDead = [
          for (final (from, to) in deadZones)
            sorted.where((e) => e > from && e < to).length,
        ];

        // Overlapped time: where two spans cover the same instant, that is
        // cross-talk, observable without frame-level posteriors.
        var overlapMs = 0;
        for (var i = 0; i < spans.length; i++) {
          for (var j = i + 1; j < spans.length; j++) {
            final from =
                spans[i].startMs > spans[j].startMs ? spans[i].startMs : spans[j].startMs;
            final to =
                spans[i].endMs < spans[j].endMs ? spans[i].endMs : spans[j].endMs;
            if (to > from) overlapMs += to - from;
          }
        }

        debugPrint('COLLAPSE $label spans=${spans.length} '
            'speakers=${speakers.length} boundaries=${sorted.length} '
            'inDeadZones=${inDead.join("+")} overlapMs=$overlapMs');
        debugPrint('COLLAPSE $label edges=${sorted.join(",")}');
      }

      await report('default', await SpeakerDiarizer().diarize(wav.path));

      for (final threshold in const [0.5, 0.6, 0.7, 0.8, 0.9]) {
        await report(
          'thr=$threshold',
          await SpeakerDiarizer()
              .diarize(wav.path, clusteringThreshold: threshold),
        );
      }

      // Forcing the count is the direct test of "did segmentation find them?".
      // If asking for 4 speakers produces four well-separated clusters, the
      // turns were there and clustering merged them.
      for (final n in const [2, 3, 4, 5]) {
        await report(
          'n=$n',
          await SpeakerDiarizer().diarize(wav.path, numClusters: n),
        );
      }

      // The duration levers, which act *before* clustering and are the only
      // ones that can add a boundary rather than relabel one.
      //
      // minDurationOn discards any segment shorter than itself outright, so at
      // the 0.2 default every turn under 200ms is deleted before clustering
      // ever sees it — exactly the length of an interruption. minDurationOff
      // bridges gaps below itself, per speaker and without regard for who
      // spoke in between, so lowering it should *stop* turns being swallowed.
      //
      // Judge these by inDeadZones, not by span count.
      for (final on in const [0.05, 0.1, 0.2]) {
        for (final off in const [0.0, 0.1, 0.5]) {
          await report(
            'on=$on/off=$off',
            await SpeakerDiarizer()
                .diarize(wav.path, minDurationOn: on, minDurationOff: off),
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
