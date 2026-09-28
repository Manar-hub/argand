// Scores whisper-cli transcript dumps for decoder repetition loops.

import 'dart:io';

import 'package:argand/core/text/repetition.dart';

final RegExp _timestamp = RegExp(r'\[[^\]]*\]');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/score_repetition.dart <file.txt> ...');
    exitCode = 64;
    return;
  }

  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('${_name(path)}: missing');
      continue;
    }

    final words = file
        .readAsStringSync()
        .replaceAll(_timestamp, ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);

    // Both shapes, always. Scanning only across whitespace once reported a
    // clean score for a transcript whose loop was a single 273-character
    // token, so a one-sided scan here would silently pass a broken run.
    final report = analyzeRepetition(words);

    stdout.writeln('${_name(path).padRight(18)} '
        'words=${words.length.toString().padRight(5)} '
        '${report.hasLoop ? "LOOP " : "clean"} '
        'across=${report.acrossWords.length.toString().padRight(3)} '
        'within=${report.withinWords.length.toString().padRight(3)} '
        'loopedWords=${report.loopedWords.toString().padRight(5)} '
        'ratio=${report.ratio.toStringAsFixed(4)}');

    for (final run in [...report.acrossWords, ...report.withinWords]) {
      final phrase = run.phrase.join(' ');
      stdout.writeln('  ${" " * 16}$run'.replaceFirst(
        phrase,
        phrase.length > 50 ? '${phrase.substring(0, 50)}...' : phrase,
      ));
    }
  }
}

String _name(String path) => path.split(RegExp(r'[\\/]')).last;
