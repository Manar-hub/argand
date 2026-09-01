import 'dart:io';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_refiner.dart';
import 'package:argand/core/diarization/speaker_sequence.dart';
import 'package:argand/core/text/sentence_units.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/diarization_truth.dart';

/// Does deciding speakers as a sequence beat deciding them one at a time?
///
/// **Diagnostic, not a pass/fail test.** It runs the real pipeline once per
/// clip and then scores several attribution rules against the same spans and
/// the same words, so the comparison rests on one shared input rather than on
/// separate runs. Nothing here asserts an accuracy number: this exists to
/// decide whether `assignSpeakersBySequence` should replace `assignSpeakers` at
/// all, before any of it is wired into the import path.
///
/// That order is the point. This project has twice built an attribution rule
/// and then discovered it changed nothing — the sentence IoU pass and the
/// straddle-split — and its own notes draw the conclusion: *measure the target,
/// then build*. So the rule exists as pure, host-tested code that this probe
/// scores; whether it ships is decided by the table this prints.
///
/// **What to read.** Every rule is scored word-level against the time-anchored
/// turns in the committed labels, which is decoder-independent — the same
/// labels score a run whose sentences were cut differently, which is exactly
/// what a beam-search or `suppress_nst` change does. The `SEQ` rows should be
/// compared against `CURRENT`, not against each other's absolute values.
///
/// The observed `CURRENT` figure is also what `maxWordErrorRate` in each
/// fixture should be set to, which is what arms the gate.
///
/// ```
/// adb push alberta.mp4      /data/local/tmp/alberta.mp4
/// adb push two_speakers.wav /data/local/tmp/two_speakers.wav
/// adb push test/fixtures/diarization/alberta.truth.json      /data/local/tmp/
/// adb push test/fixtures/diarization/two_speakers.truth.json /data/local/tmp/
/// flutter test integration_test/sequence_probe_test.dart -d <device>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('SEQ $message');

  for (final (clip, truthFile) in const [
    ('alberta.mp4', 'alberta.truth.json'),
    ('two_speakers.wav', 'two_speakers.truth.json'),
  ]) {
    testWidgets(
      'sequence rules scored against $clip',
      (tester) async {
        final media = File('$tmp/$clip');
        final labels = File('$tmp/$truthFile');
        expect(await media.exists(), isTrue, reason: 'adb push $clip first');
        expect(await labels.exists(), isTrue,
            reason: 'adb push $truthFile first');

        final truth = parseDiarizationTruth(await labels.readAsString());

        final isWav = clip.toLowerCase().endsWith('.wav');
        final imported = await converter.importToAppStorage(
          projectId: 'sequence-probe',
          fileName: clip,
          bytes: media.openRead(),
        );
        final wav = isWav
            ? imported
            : await converter.extractWavForTranscription(imported.path);

        final model = await const WhisperModelCatalog().resolve(null);
        expect(model, isNotNull);

        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model!,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );
        final words = wordTimingsOf(result);

        var spans = await SpeakerDiarizer().diarize(wav.path) ?? const [];
        if (spans.isNotEmpty) {
          final refined = await SpeakerRefiner().refine(
            wavPath: wav.path,
            spans: spans,
            words: words,
            assigned: assignSpeakers(words, spans),
          );
          spans = refined.spans;
        }

        final timings = [
          for (final word in words) (startMs: word.startMs, endMs: word.endMs),
        ];

        log('$clip words=${words.length} spans=${spans.length} '
            'speakers=${{for (final s in spans) s.speaker}.length} '
            'units=${speechUnitsOf(words, spans).length} '
            'truthTurns=${truth.turns.length}');

        WordTruthScore score(String label, List<int?> assigned) {
          final s = scoreWordsAgainstTruth(
            words: timings,
            assigned: assigned,
            truth: truth,
          );
          log('$clip ${label.padRight(22)} $s  mapping=${s.mapping}');
          return s;
        }

        // The shipped rule, and the baseline everything else is read against.
        final baseline = score('CURRENT', assignSpeakers(words, spans));

        // Exactly which words the shipped rule gets wrong, and the evidence
        // available at each one. Without this, a new rule is designed against
        // the fixture's prose description of a failure rather than against the
        // geometry actually present in the run — which is how a rule that
        // could not possibly help got built.
        final currentAssigned = assignSpeakers(words, spans);
        final allUnits = speechUnitsOf(words, spans);
        for (final i in baseline.mismatchedIndices) {
          final word = words[i];
          final mid = word.startMs + (word.endMs - word.startMs) ~/ 2;
          final want = speakerAtMs(truth.turns, mid);
          final got = currentAssigned[i];
          final mapped = got == null ? null : baseline.mapping[got];

          final unit = allUnits.firstWhere(
            (u) => i >= u.first && i <= u.last,
            orElse: () => allUnits.last,
          );
          final coverage = coverageOf(unit, spans);

          log('$clip  WRONG @$i "${word.text}" ${word.startMs}-${word.endMs} '
              'got=$mapped want=$want '
              'unit=${unit.first}-${unit.last} '
              '${unit.startsSentence ? 'sentence-start' : 'MID-SENTENCE'} '
              '${unit.durationMs}ms coverage=$coverage');
        }

        // The spans overlapping each wrong word, since a wrong answer with no
        // competing span is a segmentation gap and a wrong answer with one is a
        // reconciliation failure — different problems needing different fixes.
        for (final i in baseline.mismatchedIndices) {
          final word = words[i];
          final touching = [
            for (final span in spans)
              if (span.overlapWith(word.startMs, word.endMs) > 0)
                '${span.speaker}:${span.startMs}-${span.endMs}',
          ];
          log('$clip  SPANS @$i ${touching.isEmpty ? 'NONE' : touching.join(' ')}');
        }

        // Per-word with no sentence smoothing at all, to show how much of the
        // current result the existing smoothing already contributes.
        score(
          'CURRENT no-smoothing',
          assignSpeakers(words, spans, smoothing: SpeakerSmoothing.none),
        );

        // Sentence units with no sequence pressure: every unit takes its own
        // argmax. Isolates "decide whole sentences" from "decide them jointly".
        score(
          'SEQ argmax-only',
          assignSpeakersBySequence(
            words,
            spans,
            tuning: SequenceTuning.none,
          ),
        );

        // The candidate rule, and a sweep either side of its default so the
        // number is not read off a single arbitrary setting.
        for (final cost in const [0.3, 0.6, 1.0, 2.0]) {
          score(
            'SEQ mid-cost=$cost',
            assignSpeakersBySequence(
              words,
              spans,
              tuning: SequenceTuning(midSentenceSwitchCost: cost),
            ),
          );
        }

        // Where the rules disagree, and on which words — the detail that says
        // whether a score moved for the reason claimed rather than by accident.
        final current = assignSpeakers(words, spans);
        final sequence = assignSpeakersBySequence(words, spans);
        var disagreements = 0;
        for (var i = 0; i < words.length; i++) {
          if (current[i] == sequence[i]) continue;
          disagreements++;
          if (disagreements <= 30) {
            log('$clip  DIFF @$i ${current[i]} -> ${sequence[i]}  '
                '"${words[i].text}" ${words[i].startMs}-${words[i].endMs}');
          }
        }
        log('$clip disagreements=$disagreements of ${words.length} words');

        // Mid-sentence units are where the rule can act at all, so their count
        // bounds how much it could possibly change on this clip.
        final units = speechUnitsOf(words, spans);
        final midSentence = units.where((u) => !u.startsSentence).length;
        log('$clip units=${units.length} midSentence=$midSentence');

        // The transcript as this run actually produced it, for re-labelling.
        //
        // Labels go stale silently: word timings and sentence cuts move with the
        // decoder, and a fixture then describes a transcript that no longer
        // exists. Both committed clips are in that state. Scoring against them
        // mixes real attribution errors with drift, so the honest fix is to
        // re-label against a transcript someone can actually listen to — which
        // means printing it.
        //
        // `spk` is what the pipeline currently believes. Where it is right the
        // line needs no edit; the ear only has to settle the ones it got wrong.
        final sentences = sentenceUnitsOf(words);
        final perSentenceSpeaker = <int?>[];
        for (final sentence in sentences) {
          final votes = <int, int>{};
          for (var i = sentence.first; i <= sentence.last; i++) {
            final speaker = currentAssigned[i];
            if (speaker != null) votes[speaker] = (votes[speaker] ?? 0) + 1;
          }
          int? winner;
          var best = 0;
          votes.forEach((speaker, count) {
            if (count > best) {
              best = count;
              winner = speaker;
            }
          });
          perSentenceSpeaker.add(winner);

          final text = [
            for (var i = sentence.first; i <= sentence.last; i++) words[i].text,
          ].join(' ');

          // Whether the transcript would *render* this sentence across more
          // than one speaker. This is the criterion that matters and the one a
          // majority vote hides: `_groupIntoTurns` opens a new coloured turn at
          // every speakerId change, so a single differing word splits the
          // sentence on screen. Scored by majority, a 3-versus-2 split reads as
          // correct while the user is looking straight at the failure.
          final runs = <int?>[];
          for (var i = sentence.first; i <= sentence.last; i++) {
            if (runs.isEmpty || runs.last != currentAssigned[i]) {
              runs.add(currentAssigned[i]);
            }
          }
          final split = runs.length > 1;

          log('$clip  TRUTH [${sentences.indexOf(sentence)}] '
              'spk=$winner ${sentence.startMs}-${sentence.endMs} '
              '${split ? 'SPLIT${runs.join("/")} ' : ''}"$text"');
        }

        // The user-visible score: a sentence counts only when every word in it
        // carries one speaker. Reported separately from the majority figure so
        // the two failure modes -- wrong speaker, and torn sentence -- stay
        // distinguishable rather than averaging into one number.
        var intact = 0;
        var splitCount = 0;
        for (final sentence in sentences) {
          final distinct = <int?>{
            for (var i = sentence.first; i <= sentence.last; i++)
              currentAssigned[i],
          };
          if (distinct.length > 1) {
            splitCount++;
          } else {
            intact++;
          }
        }
        log('$clip RENDERED intact=$intact split=$splitCount '
            'of ${sentences.length} sentences');

        // The same thing as a `turns` array, ready to paste into the fixture
        // once the speakers above are confirmed. Consecutive sentences on one
        // speaker merge, because a turn is the honest unit: it survives the
        // decoder re-cutting sentences underneath it, which is the whole reason
        // the previous labelling scheme kept going stale.
        log('$clip  ---- paste into $truthFile as "turns" ----');
        final buffer = StringBuffer('"turns": [');
        int? openSpeaker;
        var openStart = 0;
        var openEnd = 0;
        var first = true;
        void flush() {
          if (openSpeaker == null) return;
          if (!first) buffer.write(',');
          first = false;
          buffer.write('\n    {"startMs": $openStart, "endMs": $openEnd, '
              '"speaker": $openSpeaker}');
        }

        for (var i = 0; i < sentences.length; i++) {
          final speaker = perSentenceSpeaker[i];
          if (speaker == null) continue;
          if (openSpeaker == speaker) {
            openEnd = sentences[i].endMs;
            continue;
          }
          flush();
          openSpeaker = speaker;
          openStart = sentences[i].startMs;
          openEnd = sentences[i].endMs;
        }
        flush();
        buffer.write('\n  ]');
        for (final line in buffer.toString().split('\n')) {
          log('$clip  $line');
        }
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }
}
