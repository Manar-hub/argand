import 'dart:io';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_refinement.dart';
import 'package:argand/core/diarization/speaker_refiner.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/diarization/span_validation.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/sentence_units.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/diarization_truth.dart';

/// Does challenging short spans against the audio fix the model-dependent
/// failures, and does it cost anything anywhere else?
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('SV $message');

  for (final (clip, truthFile) in const [
    ('two_speakers.wav', 'two_speakers.truth.json'),
    ('alberta.mp4', 'alberta.truth.json'),
  ]) {
    testWidgets('span validation on $clip', (tester) async {
      final media = File('$tmp/$clip');
      final labels = File('$tmp/$truthFile');
      expect(await media.exists(), isTrue, reason: 'adb push $clip first');
      expect(await labels.exists(), isTrue, reason: 'adb push $truthFile first');

      final truth = parseDiarizationTruth(await labels.readAsString());

      final imported = await converter.importToAppStorage(
        projectId: 'span-validation-probe',
        clipId: 'clip',
        fileName: clip,
        bytes: media.openRead(),
      );
      final wav = clip.toLowerCase().endsWith('.wav')
          ? imported
          : await converter.extractWavForTranscription(imported.path);
      final spans0 =
          await SpeakerDiarizer().diarize(wav.path) ?? const <SpeakerSpan>[];

      log('');
      log('===== $clip: ${spans0.length} spans (model-independent) =====');
      for (var i = 0; i < spans0.length; i++) {
        final s = spans0[i];
        log('$clip  span ${i.toString().padLeft(2)} spk${s.speaker} '
            '${s.startMs}-${s.endMs} (${s.durationMs}ms)');
      }

      const config = SpanValidation();
      final suspects = suspectSpans(spans0, config: config);
      log('$clip suspects=${suspects.length}');
      for (final suspect in suspects) {
        log('$clip  SUSPECT span ${suspect.index} ${suspect.startMs}-'
            '${suspect.endMs} (${suspect.durationMs}ms) '
            'spk${suspect.incumbent} challenged by spk${suspect.challenger}');
      }

      final models = await const WhisperModelCatalog().available();
      expect(models, isNotEmpty, reason: 'no model bundled in this build');

      for (final model in models) {
        final tag = '$clip/${model.id}';
        log('');
        log('----- $tag -----');

        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );
        final words = wordTimingsOf(result);
        final timings = [
          for (final word in words) (startMs: word.startMs, endMs: word.endMs),
        ];
        final sentences = sentenceUnitsOf(words);

        void transcript(String label, List<int?> assigned, {bool full = false}) {
          final score = scoreWordsAgainstTruth(
            words: timings,
            assigned: assigned,
            truth: truth,
          );
          var intact = 0;
          final bad = <String>[];
          for (var i = 0; i < sentences.length; i++) {
            final s = sentences[i];
            final speakers = [
              for (var j = s.first; j <= s.last; j++) assigned[j],
            ];
            final distinct = speakers.toSet();
            final text = [
              for (var j = s.first; j <= s.last; j++) words[j].text,
            ].join(' ');
            final mid = s.startMs + (s.endMs - s.startMs) ~/ 2;
            final want = speakerAtMs(truth.turns, mid);
            if (distinct.length <= 1) {
              intact++;
              final mapped = score.mapping[speakers.first];
              if (mapped != want) {
                bad.add('${i.toString().padLeft(2)} spk${speakers.first} '
                    'want=spk$want  "$text"');
              }
            } else {
              bad.add('${i.toString().padLeft(2)} SPLIT $speakers '
                  'want=spk$want  "$text"');
            }
            if (full) {
              log('$tag    ${i.toString().padLeft(2)} '
                  '${distinct.length <= 1 ? 'spk${speakers.first}' : 'SPLIT $speakers'}'
                  '  "$text"');
            }
          }
          log('$tag $label  $score  intact=$intact/${sentences.length}');
          for (final line in bad) {
            log('$tag     WRONG $line');
          }
        }

        Future<List<SpeakerSpan>> refined(
          List<SpeakerSpan> spans,
          double margin,
        ) async {
          if (spans.isEmpty) return spans;
          final out = await SpeakerRefiner().refine(
            wavPath: wav.path,
            spans: spans,
            words: words,
            assigned: assignSpeakers(words, spans),
            config: SpeakerRefinement(minMargin: margin),
          );
          return out.spans;
        }

        // Baseline: exactly what ships.
        transcript('CURRENT           ', assignSpeakers(words, await refined(spans0, 0.15)));

        // Margin re-sweep, now against corrected anchors.
        for (final margin in const <double>[0.12, 0.10, 0.08]) {
          transcript(
            'MARGIN=${margin.toStringAsFixed(2)}      ',
            assignSpeakers(words, await refined(spans0, margin)),
          );
        }

        // Span validation, ahead of everything else.
        if (suspects.isNotEmpty) {
          final sims = await SpeakerRefiner().similaritiesFor(
            wavPath: wav.path,
            spans: spans0,
            words: words,
            assigned: assignSpeakers(words, spans0),
            regions: [
              for (final suspect in suspects)
                suspect.embedRegion(config) ??
                    (startMs: suspect.startMs, endMs: suspect.endMs),
            ],
          );
          final won = <SuspectSpan>[];
          for (var i = 0; i < suspects.length; i++) {
            final suspect = suspects[i];
            final sim = sims[i];
            final wins = challengerWins(suspect, sim, config: config);
            final detail = (sim.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
                .map((e) => 'spk${e.key}:${e.value.toStringAsFixed(3)}')
                .join(' ');
            log('$tag  CHALLENGE span ${suspect.index} '
                '${suspect.startMs}-${suspect.endMs} '
                'spk${suspect.incumbent}->spk${suspect.challenger} '
                '$detail  ${wins ? 'REASSIGNED' : 'kept'}');
            if (wins) won.add(suspect);
          }

          final validated = applyValidations(spans0, won);
          transcript(
            'VALIDATED         ',
            assignSpeakers(words, await refined(validated, 0.15)),
            full: true,
          );
          for (final margin in const <double>[0.12, 0.10]) {
            transcript(
              'VALIDATED+M=${margin.toStringAsFixed(2)} ',
              assignSpeakers(words, await refined(validated, margin)),
              full: margin == 0.10,
            );
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 45)));
  }
}
