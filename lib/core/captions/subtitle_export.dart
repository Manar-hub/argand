import 'caption_cue.dart';

/// A subtitle container this app can write.
///
/// Both are plain text wrappers around the user's own transcript, so both are
/// free and always will be (CLAUDE.md §2). The paid line falls at professional
/// *interchange* formats — ASS/SSA and similar — which exist to feed another
/// editing tool's pipeline rather than to read or share your captions.
enum SubtitleFormat {
  srt(
    extension: 'srt',
    // The de-facto type for SubRip. There is no registered IANA type, and
    // `text/plain` makes Android offer the file to text editors rather than to
    // players, so the specific one is worth using even though it is informal.
    mimeType: 'application/x-subrip',
  ),
  vtt(extension: 'vtt', mimeType: 'text/vtt');

  const SubtitleFormat({required this.extension, required this.mimeType});

  final String extension;
  final String mimeType;
}

/// How long a subtitle line may run before it wraps.
///
/// **The one layout choice worth handing to the user.** Forty-two characters is
/// the broadcast convention and suits a landscape frame; on a 9:16 video the
/// same line covers most of the picture's width, which is why short-form
/// platforms settle nearer thirty. Everything else about the file is decided
/// by the captions themselves.
enum SubtitleLineLength {
  standard(42),
  short(32);

  const SubtitleLineLength(this.maxCharacters);

  final int maxCharacters;
}

/// Knobs for turning cues into a subtitle file.
///
/// Separate from [CaptionStyle], which decides *where cues break*. These decide
/// how an already-grouped cue is written down, and the two are independent: the
/// same grouping exports identically to both formats.
class SubtitleOptions {
  const SubtitleOptions({
    this.minCueMs = 100,
    this.gapMs = 1,
    this.maxLineCharacters = 42,
    this.maxLines = 2,
  });

  /// Shortest cue the file may contain.
  ///
  /// A **validity** floor, not a readability rule -- subtitling practice wants
  /// closer to a second, but the grouper already decides what a cue contains
  /// and this only exists because a player rejects or skips a cue that ends
  /// where it starts. Word timings come from whisper's DTW alignment, which
  /// occasionally emits a zero-length or inverted span. Kept small so that a
  /// run of degenerate cues cannot push later ones noticeably out of sync.
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
///
/// [speakerLabel] names the speaker of a cue, and is null when the file should
/// carry no attribution. It is given the whole cue rather than a speaker number
/// because names are stored per transcript, and a project's cues come from
/// several: the same number can be two different people in two different runs,
/// so only the cue's own words say whose names to use.
///
/// It is injected rather than built here because "Speaker 1" is interface text
/// and belongs to the localisation layer (CLAUDE.md §4) — this file stays free
/// of strings the user reads.
///
/// The two formats differ only in their timestamp separator, their header, and
/// how they mark a speaker, so they share one pass.
String formatSubtitles(
  List<CaptionCue> cues, {
  required SubtitleFormat format,
  String Function(CaptionCue cue)? speakerLabel,
  SubtitleOptions options = const SubtitleOptions(),
}) {
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
    buffer.writeln();
  }

  return buffer.toString();
}

/// Forces the cue list into timings a player will accept: strictly increasing,
/// never overlapping, never zero-length.
///
/// None of those hold on the way in. `CaptionCue` already takes the *maximum*
/// word end to stop a cue finishing before it starts, and its own documentation
/// notes that DTW timestamps drift — so two cues can overlap, and a cue built
/// from a single clipped word can have no duration at all.
///
/// Cues are pushed later rather than earlier when they collide, so a cue never
/// appears before the word it transcribes. With [SubtitleOptions.minCueMs] at
/// 100ms the accumulated shift stays imperceptible unless a transcript is
/// almost entirely degenerate, in which case its timings were unusable anyway.
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
  };
}

/// Breaks [text] into at most [SubtitleOptions.maxLines] readable lines.
///
/// Splits on the space nearest the middle rather than filling greedily: a
/// greedy fill leaves a long first line and an orphan second, which reads worse
/// than two balanced ones at the same total length.
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
///
/// Hours are always written. WebVTT permits `MM:SS.mmm`, but the long form is
/// valid in both formats and one code path is worth more than three saved
/// characters per line.
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
///
/// Deliberately not applied to SubRip: it has no markup layer, and writing
/// `&amp;` there would put a literal ampersand-a-m-p on screen. Some players
/// do honour a subset of HTML tags in SubRip, which is a real if rare hazard —
/// noted rather than guessed at, since escaping would break the common case to
/// serve the uncommon one.
String _escapeVtt(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
