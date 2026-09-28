import 'caption_cue.dart';

/// A subtitle container this app can write.
enum SubtitleFormat {
  srt(
    extension: 'srt',
    // The de-facto type for SubRip. There is no registered IANA type, and
    // `text/plain` makes Android offer the file to text editors rather than to
    // players, so the specific one is worth using even though it is informal.
    mimeType: 'application/x-subrip',
  ),
  vtt(extension: 'vtt', mimeType: 'text/vtt'),

  /// Advanced SubStation Alpha: styled, speaker-coloured subtitles for
  /// editing tools. A Pro format.
  ass(extension: 'ass', mimeType: 'text/x-ssa');

  const SubtitleFormat({required this.extension, required this.mimeType});

  final String extension;
  final String mimeType;
}

/// How long a subtitle line may run before it wraps.
enum SubtitleLineLength {
  standard(42),
  short(32);

  const SubtitleLineLength(this.maxCharacters);

  final int maxCharacters;
}

/// Knobs for turning cues into a subtitle file.
class SubtitleOptions {
  const SubtitleOptions({
    this.minCueMs = 100,
    this.gapMs = 1,
    this.maxLineCharacters = 42,
    this.maxLines = 2,
  });

  /// Shortest cue the file may contain.
  final int minCueMs;

  /// Separation forced between one cue's end and the next cue's start.
  final int gapMs;

  /// Conventional readable line length, about half of
  /// [CaptionStyle.maxCharacters].
  final int maxLineCharacters;

  /// Two lines is the subtitling convention; a third starts covering the shot.
  /// Text that will not fit stays on the last line rather than being dropped —
  /// losing a word from a transcript is never the right trade.
  final int maxLines;
}

/// Serialises [cues] into [format].
String formatSubtitles(
  List<CaptionCue> cues, {
  required SubtitleFormat format,
  String Function(CaptionCue cue)? speakerLabel,
  SubtitleOptions options = const SubtitleOptions(),
  String? Function(CaptionCue cue)? translation,
  int Function(CaptionCue cue)? colorOf,
}) {
  if (format == SubtitleFormat.ass) {
    return _formatAss(
      cues,
      speakerLabel: speakerLabel,
      options: options,
      translation: translation,
      colorOf: colorOf ?? (_) => 0xFFFFFFFF,
    );
  }
  final buffer = StringBuffer();
  if (format == SubtitleFormat.vtt) buffer.writeln('WEBVTT\n');

  final timings = _normalise(cues, options);

  for (final (index, cue) in cues.indexed) {
    final (start, end) = timings[index];
    final body = _body(cue, format: format, speakerLabel: speakerLabel, options: options);

    // SubRip requires a sequential counter from 1. WebVTT allows an optional
    // identifier in the same position; omitted, because nothing reads it and
    // its absence is the more common shape in the wild.
    if (format == SubtitleFormat.srt) buffer.writeln('${index + 1}');

    final separator = format == SubtitleFormat.srt ? ',' : '.';
    buffer.writeln(
      '${_timestamp(start, separator)} --> ${_timestamp(end, separator)}',
    );
    buffer.writeln(body);
    // A translation goes on the line under the cue's own words: the usual
    // shape of a bilingual subtitle, and one every player can show.
    if (translation?.call(cue) case final line? when line.trim().isNotEmpty) {
      buffer.writeln(line.trim());
    }
    buffer.writeln();
  }

  return buffer.toString();
}

/// Forces the cue list into timings a player will accept: strictly increasing,
/// never overlapping, never zero-length.
List<(int, int)> _normalise(List<CaptionCue> cues, SubtitleOptions options) {
  final result = <(int, int)>[];
  var cursor = 0;

  for (final cue in cues) {
    final start = cue.startMs < cursor ? cursor : cue.startMs;
    var end = cue.endMs;
    if (end < start + options.minCueMs) end = start + options.minCueMs;

    result.add((start, end));
    cursor = end + options.gapMs;
  }

  return result;
}

/// The visible text of one cue, wrapped and attributed.
String _body(
  CaptionCue cue, {
  required SubtitleFormat format,
  required String Function(CaptionCue cue)? speakerLabel,
  required SubtitleOptions options,
}) {
  final label =
      cue.speaker == null || speakerLabel == null ? null : speakerLabel(cue);

  final text = format == SubtitleFormat.vtt ? _escapeVtt(cue.text) : cue.text;
  final lines = _wrap(text, options).join('\n');

  if (label == null) return lines;

  return switch (format) {
    // WebVTT's own voice span. Players that understand it can style per
    // speaker; players that do not render the text and drop the tag, which is
    // why the name is not also duplicated into the body.
    SubtitleFormat.vtt => '<v ${_escapeVtt(label)}>$lines</v>',
    // SubRip has no speaker concept, so the long-standing convention is a
    // prefix. It counts against the line length, but re-wrapping around it
    // would push the first line short for every cue.
    SubtitleFormat.srt => '$label: $lines',
    SubtitleFormat.ass => lines,
  };
}

/// [cues] as an ASS script: one style per speaker colour, the speaker's name
/// in each line's Name field, sized for a 1080p frame.
String _formatAss(
  List<CaptionCue> cues, {
  required String Function(CaptionCue cue)? speakerLabel,
  required SubtitleOptions options,
  required String? Function(CaptionCue cue)? translation,
  required int Function(CaptionCue cue) colorOf,
}) {
  final styles = <int, String>{};
  for (final cue in cues) {
    styles.putIfAbsent(colorOf(cue), () => 'Speaker${styles.length + 1}');
  }

  final buffer = StringBuffer()
    ..writeln('[Script Info]')
    ..writeln('; Written by Argand')
    ..writeln('ScriptType: v4.00+')
    ..writeln('PlayResX: 1920')
    ..writeln('PlayResY: 1080')
    ..writeln('WrapStyle: 0')
    ..writeln('ScaledBorderAndShadow: yes')
    ..writeln()
    ..writeln('[V4+ Styles]')
    ..writeln(
      'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
      'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, '
      'ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, '
      'MarginL, MarginR, MarginV, Encoding',
    );
  for (final MapEntry(key: argb, value: name) in styles.entries) {
    buffer.writeln(
      'Style: $name,Arial,54,${_assColor(argb)},&H000000FF,&H00000000,'
      '&H80000000,-1,0,0,0,100,100,0,0,1,3,1,2,60,60,90,1',
    );
  }
  buffer
    ..writeln()
    ..writeln('[Events]')
    ..writeln(
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
      'Effect, Text',
    );

  final timings = _normalise(cues, options);
  for (final (index, cue) in cues.indexed) {
    final (start, end) = timings[index];
    final name = cue.speaker == null || speakerLabel == null
        ? ''
        : _escapeAss(speakerLabel(cue)).replaceAll(',', ' ');
    var text = _wrap(_escapeAss(cue.text), options).join(r'\N');
    if (translation?.call(cue) case final line? when line.trim().isNotEmpty) {
      text = '$text\\N${_escapeAss(line.trim())}';
    }
    buffer.writeln(
      'Dialogue: 0,${_assTime(start)},${_assTime(end)},'
      '${styles[colorOf(cue)]},$name,0,0,0,,$text',
    );
  }
  return buffer.toString();
}

/// ASS colours are `&HAABBGGRR`, with 00 as opaque.
String _assColor(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '&H00${hex(b)}${hex(g)}${hex(r)}';
}

/// `H:MM:SS.cc`, in centiseconds as ASS counts them.
String _assTime(int totalMs) {
  final ms = totalMs < 0 ? 0 : totalMs;
  final hours = ms ~/ 3600000;
  final minutes = '${(ms % 3600000) ~/ 60000}'.padLeft(2, '0');
  final seconds = '${(ms % 60000) ~/ 1000}'.padLeft(2, '0');
  final centis = '${(ms % 1000) ~/ 10}'.padLeft(2, '0');
  return '$hours:$minutes:$seconds.$centis';
}

/// Braces open override tags in ASS, and a line break is `\N`.
String _escapeAss(String text) => text
    .replaceAll('{', '(')
    .replaceAll('}', ')')
    .replaceAll('\n', ' ');

/// Breaks [text] into at most [SubtitleOptions.maxLines] readable lines.
List<String> _wrap(String text, SubtitleOptions options) {
  if (text.length <= options.maxLineCharacters) return [text];

  final lines = <String>[];
  var remaining = text;

  while (lines.length < options.maxLines - 1 &&
      remaining.length > options.maxLineCharacters) {
    final split = _balancedSplit(remaining, options.maxLineCharacters);
    if (split == null) break;

    lines.add(remaining.substring(0, split).trimRight());
    remaining = remaining.substring(split).trimLeft();
  }

  // Whatever is left goes on the final line even if it overruns. A player
  // wrapping a long line is a cosmetic problem; dropping the words is a
  // correctness one.
  lines.add(remaining);
  return lines;
}

/// Index of the space to break at, or null when there is none to use.
int? _balancedSplit(String text, int maxLineCharacters) {
  final target = text.length ~/ 2;
  final limit = text.length < maxLineCharacters * 2
      ? text.length
      : maxLineCharacters * 2;

  int? best;
  var bestDistance = 1 << 30;

  for (var i = 0; i < limit; i++) {
    if (text.codeUnitAt(i) != 0x20) continue;
    // Never produce a first line longer than the limit, however balanced.
    if (i > maxLineCharacters) break;

    final distance = (i - target).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }

  return best;
}

/// `HH:MM:SS` plus milliseconds after [separator].
String _timestamp(int totalMs, String separator) {
  final ms = totalMs < 0 ? 0 : totalMs;
  final hours = ms ~/ 3600000;
  final minutes = (ms % 3600000) ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final millis = ms % 1000;

  final hh = '$hours'.padLeft(2, '0');
  final mm = '$minutes'.padLeft(2, '0');
  final ss = '$seconds'.padLeft(2, '0');
  final mmm = '$millis'.padLeft(3, '0');

  return '$hh:$mm:$ss$separator$mmm';
}

/// WebVTT reads `<`, `>` and `&` as markup, so a transcript containing them
/// would silently lose text or produce a malformed cue.
String _escapeVtt(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
