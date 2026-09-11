import 'dart:io';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_refiner.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/sentence_boundaries.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/diarization_truth.dart';

/// The diarization regression gate.
///
/// **Why this exists.** `test/fixtures/diarization/*.truth.json` were committed
/// as the permanent scoring set, but nothing read them — the 24/24 and 14/16
/// figures were tallied by hand from probe dumps. That made every engine
/// parameter change unanswerable without a manual re-count, which is exactly
/// the question the repetition-loop and flash-attention work had to answer.
///
/// This runs the **real pipeline** — the same calls `import_controller.dart`
/// makes, in the same order — and scores the result against the committed
/// labels with [scoreAgainstTruth].
///
/// **What it scores, and why that changed.** The primary number is now
/// *word-level*: each word's speaker against the time-anchored turns derived
/// from the labels. Sentence indices belong to one segmentation — the fixtures
/// say so themselves — so any decoder change re-cut the transcript and made the
/// old score unscoreable. Time cannot be re-cut, so beam search, a different
/// model and a different VAD setting are all measurable against the same
/// labels, without the re-labelling that had blocked them.
///
/// **What a pass means.** The word error rate is at or under the floor the
/// fixture records, and — when the sentence counts still line up — no *new*
/// sentence is wrong. Documented failures are the measured status quo of this
/// toolchain; failing anything else is damage.
///
/// **A gate that cannot fail is not a gate.** This used to return early when
/// the sentence count disagreed, which meant `alberta.mp4` passed without being
/// scored at all for as long as its labels had been stale. Now an unmeasured
/// clip fails and tells you to record its floor.
///
/// Fixtures, all pushed to a world-readable path the app sandbox can open:
///
/// ```
/// adb push alberta.mp4      /data/local/tmp/alberta.mp4
/// adb push two_speakers.wav /data/local/tmp/two_speakers.wav
/// adb push test/fixtures/diarization/alberta.truth.json      /data/local/tmp/
/// adb push test/fixtures/diarization/two_speakers.truth.json /data/local/tmp/
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('GATE $message');

  /// Runs the full import pipeline and returns everything scoring needs.
  ///
  /// Mirrors `import_controller.dart`: diarize, assign, refine, re-assign. The
  /// refinement step is included because it is what actually produces the
  /// committed scores — grading the unrefined spans would measure a pipeline
  /// the app does not run.
  ///
  /// Returns words and their per-word assignment alongside the per-sentence
  /// roll-up, because the two answer different questions: words are scoreable
  /// against any segmentation, sentences only against the one they were
  /// labelled on.
  Future<({
    List<TruthWord> words,
    List<int?> assigned,
    List<int?> perSentence,
    List<({String text, List<int?> speakers})> rendered,
  })> attributionOf(
    String wavPath,
    List<SpeakerSpan> baseSpans,
    WhisperModelDescriptor model,
  ) async {
    final result = await WhisperService().transcribeWav(
      wavPath,
      model: model,
      language: TranscriptionLanguage.auto,
      skipSilence: true,
    );
    final words = wordTimingsOf(result);

    // Diarization never sees whisper, so the spans are supplied rather than
    // recomputed: holding them fixed is what isolates the model's effect, which
    // is entirely on word timings and therefore on refinement regions.
    var spans = baseSpans;
    if (spans.isNotEmpty) {
      // Mirrors `import_controller.dart`: spurious short spans are challenged
      // before anything reads them, because a bad span edge cannot be repaired
      // downstream. Takes no transcript, so it runs identically per model.
      spans = await SpeakerRefiner()
          .validateSpans(wavPath: wavPath, spans: spans);
    }
    if (spans.isNotEmpty) {
      final refined = await SpeakerRefiner().refine(
        wavPath: wavPath,
        spans: spans,
        words: words,
        assigned: assignSpeakers(words, spans),
      );
      spans = refined.spans;
      log('refinement moved ${refined.movedCount} of '
          '${refined.decisions.length} candidates');
      // Why each doubtful region was or was not moved. This is what makes the
      // per-model divergence readable: a region present under one model and
      // absent under the other was never planned, i.e. a gate refused it.
      for (final d in refined.decisions) {
        final sims = d.similarities.entries
            .map((e) => 'spk${e.key}:${e.value.toStringAsFixed(3)}')
            .join(' ');
        log('  DEC ${d.candidate.startMs}-${d.candidate.endMs} '
            'was=spk${d.candidate.currentSpeaker} '
            '${d.outcome.name}${d.newSpeaker == null ? '' : ' ->spk${d.newSpeaker}'}'
            '${sims.isEmpty ? '' : '  $sims'}');
      }
    }
    final assigned = assignSpeakers(words, spans);

    // One speaker per sentence, by majority of its words. Sentences are cut the
    // same way the caption grouper and speaker smoothing cut them, so the
    // indices line up with how the labels were produced.
    final perSentence = <int?>[];
    // What the transcript actually renders: a sentence read by a human is
    // "one speaker" only if EVERY word in it agrees. A majority vote cannot
    // see a two-word sentence split one word each -- the vote ties and scores
    // the sentence correct either way, while the screen shows two blocks.
    final rendered = <({String text, List<int?> speakers})>[];
    var start = 0;
    for (var i = 0; i < words.length; i++) {
      final isLast = i == words.length - 1;
      if (!endsSentence(words[i].text) && !isLast) continue;

      final votes = <int, int>{};
      for (var j = start; j <= i; j++) {
        final speaker = assigned[j];
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
      perSentence.add(winner);
      rendered.add((
        text: [for (var j = start; j <= i; j++) words[j].text].join(' '),
        speakers: [for (var j = start; j <= i; j++) assigned[j]],
      ));
      start = i + 1;
    }

    return (
      words: [
        for (final word in words) (startMs: word.startMs, endMs: word.endMs),
      ],
      assigned: assigned,
      perSentence: perSentence,
      rendered: rendered,
    );
  }

  /// The gate itself, applied per model.
  ///
  /// A word-level floor is checked on every run rather than only when sentence
  /// counts happen to line up. This previously returned early on an
  /// incomparable sentence count, so `alberta.mp4` — 25 sentences against 24
  /// labels since long before this work — passed without being scored at all.
  /// A gate that cannot fail is not a gate, so an unmeasured case is an
  /// explicit failure telling you to record a floor.
  ///
  /// The floor is per fixture, not per model, and that is deliberate: the
  /// requirement is that **no** bundled model regresses, so the weakest one has
  /// to clear the same bar.
  void checkGate(
    String tag,
    DiarizationTruth truth,
    WordTruthScore words,
    TruthScore score,
  ) {
    final floor = truth.maxWordErrorRate;
    if (floor == null) {
      fail('$tag has no maxWordErrorRate in its labels, so nothing here can '
          'fail. Observed word error rate is '
          '${(words.errorRate * 100).toStringAsFixed(2)}% -- record it in '
          "${truth.clip}'s fixture to arm the gate.");
    }

    expect(
      words.errorRate,
      lessThanOrEqualTo(floor),
      reason: 'word-level speaker attribution regressed against the committed '
          'floor, on $tag',
    );

    if (score.comparable) {
      expect(
        score.newMismatches,
        isEmpty,
        reason: 'new sentences are misattributed on $tag that the committed '
            'labels do not document as known failures',
      );
    }
  }

  for (final (clip, truthFile) in const [
    ('alberta.mp4', 'alberta.truth.json'),
    ('two_speakers.wav', 'two_speakers.truth.json'),
  ]) {
    testWidgets(
      'gate: $clip scores against its committed labels',
      (tester) async {
        final media = File('$tmp/$clip');
        final labels = File('$tmp/$truthFile');
        expect(await media.exists(), isTrue, reason: 'adb push $clip first');
        expect(await labels.exists(), isTrue,
            reason: 'adb push $truthFile first');

        final truth = parseDiarizationTruth(await labels.readAsString());

        // Converted and diarized once, then held fixed across models. Spans do
        // not depend on whisper, so recomputing them per model would only add
        // cost and noise.
        final imported = await converter.importToAppStorage(
          projectId: 'attribution-gate',
          fileName: clip,
          bytes: media.openRead(),
        );
        final wav = clip.toLowerCase().endsWith('.wav')
            ? imported
            : await converter.extractWavForTranscription(imported.path);
        final baseSpans =
            await SpeakerDiarizer().diarize(wav.path) ?? const <SpeakerSpan>[];

        // **Every bundled model, not just the default.** This gate previously
        // called `resolve(null)`, which resolves to `base`, and reported its
        // result as if it were general -- while `small-q5_1` was failing two
        // sentences on this very clip. A single-model gate manufactures false
        // passes, because refinement regions are sentence extents and the
        // models cut sentences differently.
        final models = await const WhisperModelCatalog().available();
        expect(models, isNotEmpty, reason: 'no model bundled in this build');

        for (final model in models) {
          final tag = '$clip/${model.id}';
          final run = await attributionOf(wav.path, baseSpans, model);

          // The primary number. Anchored to time, so it survives any decoder
          // change that re-cuts the transcript into different sentences.
          final words = scoreWordsAgainstTruth(
            words: run.words,
            assigned: run.assigned,
            truth: truth,
          );
          log('$tag WORDS $words  mapping=${words.mapping} '
              'clusters=${words.observedClusters}');

          // The sentence roll-up, kept because every recorded figure in
          // docs/progress.md is in these units and continuity is worth
          // something.
          final score = scoreAgainstTruth(
            observed: run.perSentence,
            truth: truth,
          );
          log('$tag SENTENCES $score');

          if (score.comparable) {
            for (final i in score.mismatched) {
              final sentence = truth.sentences[i];
              final label = score.knownIndices.contains(i) ? 'known' : 'NEW';
              log('$tag  [$label] #$i expected spk${sentence.speaker} '
                  'got ${run.perSentence[i]}  "${sentence.text}"');
            }
          } else {
            log('$tag sentences NOT COMPARABLE -- ${score.incomparableReason}');
            log('$tag that is a segmentation change; the word score above is '
                'unaffected and is what this gate now judges');
          }

          // The user-visible score: intact means every word in the sentence
          // carries one speaker. This is the only metric that can see a split.
          var intact = 0;
          for (final sentence in run.rendered) {
            final distinct = sentence.speakers.toSet();
            if (distinct.length <= 1) {
              intact++;
            } else {
              log('$tag  SPLIT "${sentence.text}" -> ${sentence.speakers}');
            }
          }
          log('$tag RENDERED intact=$intact split=${run.rendered.length - intact}'
              ' of ${run.rendered.length} sentences');

          checkGate(tag, truth, words, score);
        }

      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
