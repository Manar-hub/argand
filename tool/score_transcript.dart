// Scores whisper transcript dumps for word accuracy against a reference.
//
// Companion to `tool/score_repetition.dart`. That one answers "did the decoder
// break?"; this one answers "did it hear the right words?" — the failure where
// nothing loops but the app produces "Climidial" where whisper-cli produces
// "Chlamydia".
//
// **The reference is a proxy, not ground truth.** It is normally a `whisper-cli`
// run under a configuration judged better by inspection, so WER here measures
// distance from that configuration rather than distance from what was actually
// said. Read it as "closer to the good result", and always read the printed
// substitutions rather than the rate alone.
//
// Imports `lib/core/text/transcript_diff.dart` rather than reimplementing the
// alignment, so a native measurement and an on-device one cannot disagree for
// reasons unrelated to whisper.
//
// Usage:
//   dart run tool/score_transcript.dart --reference ref.txt run1.txt [run2.txt ...]
//   dart run tool/score_transcript.dart --reference ref.txt --edits 30 run1.txt

import 'dart:io';

import 'package:argand/core/text/transcript_diff.dart';

void main(List<String> args) {
  String? referencePath;
  var maxEdits = 12;
  final candidates = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--reference' || '-r':
        if (++i >= args.length) return _usage('--reference needs a path');
        referencePath = args[i];
      case '--edits' || '-e':
        if (++i >= args.length) return _usage('--edits needs a number');
        maxEdits = int.tryParse(args[i]) ?? maxEdits;
      default:
        candidates.add(args[i]);
    }
  }

  if (referencePath == null || candidates.isEmpty) {
    return _usage('need --reference <path> and at least one candidate');
  }

  final referenceFile = File(referencePath);
  if (!referenceFile.existsSync()) {
    return _usage('reference not found: $referencePath');
  }
  final reference = transcriptWords(referenceFile.readAsStringSync());
  stdout.writeln('reference ${_name(referencePath)}: '
      '${reference.length} words');

  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('${_name(path).padRight(22)} missing');
      continue;
    }

    final candidate = transcriptWords(file.readAsStringSync());
    final result = compareTranscripts(reference, candidate);

    stdout.writeln('${_name(path).padRight(22)} '
        'WER=${(result.wer * 100).toStringAsFixed(1).padLeft(6)}%  '
        'words=${result.candidateWords.toString().padRight(5)} '
        'S=${result.substitutions.toString().padRight(4)} '
        'I=${result.insertions.toString().padRight(4)} '
        'D=${result.deletions}');

    for (final edit in result.edits.take(maxEdits)) {
      stdout.writeln('  ${" " * 20}@${edit.referenceIndex} $edit');
    }
    if (result.edits.length > maxEdits) {
      stdout.writeln('  ${" " * 20}... ${result.edits.length - maxEdits} more');
    }
  }
}

void _usage(String message) {
  stderr.writeln('score_transcript: $message');
  stderr.writeln('usage: dart run tool/score_transcript.dart '
      '--reference <ref.txt> [--edits N] <run.txt> ...');
  exitCode = 64;
}

String _name(String path) => path.split(RegExp(r'[\\/]')).last;
