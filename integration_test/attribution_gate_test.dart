import 'dart:io';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_diarizer.dart';
import 'package:argand/core/diarization/speaker_refiner.dart';
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
/// **What a pass means.** Not "the score is high" but "no *new* sentence is
/// wrong". Both fixtures document their known failures, and re-failing those is
/// the measured status quo of this toolchain; failing anything else is damage.
///
/// **What a "not comparable" result means, and why it is not a bug.** Ground
/// truth belongs to one segmentation. The fixtures say so themselves: sentence
/// indices are over whisper's output with silence skipping on and the bundled
/// base model. A configuration that changes how whisper cuts the clip into
/// sentences cannot be scored against these labels at all, and the scorer says
/// so rather than inventing a number by mapping sentences on time overlap —
/// a trap this project already fell into once and recorded.
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

  /// Runs the full import pipeline and returns one speaker id per sentence.
  ///
  /// Mirrors `import_controller.dart`: diarize, assign, refine, re-assign. The
  /// refinement step is included because it is what actually produces the
  /// committed scores — grading the unrefined spans would measure a pipeline
  /// the app does not run.
  Future<List<int?>> attributionBySentence(String mediaPath) async {
    final isWav = mediaPath.toLowerCase().endsWith('.wav');
    final media = await converter.importToAppStorage(
      projectId: 'attribution-gate',
      fileName: mediaPath.split('/').last,
      bytes: File(mediaPath).openRead(),
    );
    final wav = isWav
        ? media
        : await converter.extractWavForTranscription(media.path);

    final model = await const WhisperModelCatalog().resolve(null);
    expect(model, isNotNull, reason: 'no model bundled in this build');

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
      log('refinement moved ${refined.movedCount} of '
          '${refined.decisions.length} candidates');
    }
    final assigned = assignSpeakers(words, spans);

    // One speaker per sentence, by majority of its words. Sentences are cut the
    // same way the caption grouper and speaker smoothing cut them, so the
    // indices line up with how the labels were produced.
    final perSentence = <int?>[];
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
      start = i + 1;
    }
    return perSentence;
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
        final observed = await attributionBySentence(media.path);
        final score = scoreAgainstTruth(observed: observed, truth: truth);

        log('$clip $score');
        log('$clip clusters=${score.observedClusters} '
            'mapping=${score.mapping}');

        if (!score.comparable) {
          log('$clip NOT COMPARABLE -- ${score.incomparableReason}');
          log('$clip this is a segmentation change, not necessarily a '
              'regression; the clip needs re-labelling to be scored');
          return;
        }

        for (final i in score.mismatched) {
          final sentence = truth.sentences[i];
          final tag = score.knownIndices.contains(i) ? 'known' : 'NEW';
          log('$clip  [$tag] #$i expected spk${sentence.speaker} '
              'got ${observed[i]}  "${sentence.text}"');
        }

        // The gate itself. Documented failures are the status quo; anything
        // else is a regression introduced by whatever changed.
        expect(
          score.newMismatches,
          isEmpty,
          reason: 'new sentences are misattributed that the committed labels '
              'do not document as known failures',
        );
      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
