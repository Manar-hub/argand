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
  ass(extension: 'ass', mimeType: 'text/x-ssa'),

  /// Timed Text Markup Language, the W3C's XML subtitles. A Pro format.
  ttml(extension: 'ttml', mimeType: 'application/ttml+xml'),

  /// Final Cut Pro's interchange file, captions on a timeline. A Pro format.
  fcpxml(extension: 'fcpxml', mimeType: 'application/x-fcpxml'),

  /// Premiere Pro's (Final Cut 7) XML, captions as text clips. A Pro format.
  premiereXml(extension: 'xml', mimeType: 'text/xml');

  /// Formats that only Pro exports.
  bool get isPro => this != srt && this != vtt;

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
  String title = '',
  String language = '',
}) {
  final pro = _ProWriter(
    cues,
    speakerLabel: speakerLabel,
    options: options,
    translation: translation,
    colorOf: colorOf ?? (_) => 0xFFFFFFFF,
  );
  switch (format) {
    case SubtitleFormat.ass:
      return _formatAss(pro);
    case SubtitleFormat.ttml:
      return _formatTtml(pro, language: language);
    case SubtitleFormat.fcpxml:
      return _formatFcpxml(pro, title: title, language: language);
    case SubtitleFormat.premiereXml:
      return _formatPremiereXml(pro, title: title);
    case SubtitleFormat.srt || SubtitleFormat.vtt:
      break;
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
    _ => lines,
  };
}

/// What every Pro format reads from a cue: its lines, times, speaker name,
/// colour and translation.
class _ProWriter {
  _ProWriter(
    this.cues, {
    required this.speakerLabel,
    required this.options,
    required this.translation,
    required this.colorOf,
  }) : timings = _normalise(cues, options);

  final List<CaptionCue> cues;
  final String Function(CaptionCue cue)? speakerLabel;
  final SubtitleOptions options;
  final String? Function(CaptionCue cue)? translation;
  final int Function(CaptionCue cue) colorOf;
  final List<(int, int)> timings;

  String? nameOf(CaptionCue cue) =>
      cue.speaker == null || speakerLabel == null ? null : speakerLabel!(cue);

  /// The cue's wrapped lines, then its translation on a line of its own.
  List<String> linesOf(CaptionCue cue) => [
        ..._wrap(cue.text.replaceAll('\n', ' '), options),
        if (translation?.call(cue) case final line? when line.trim().isNotEmpty)
          line.trim(),
      ];

  /// One id per colour, in order of first use.
  Map<int, int> get colorIds {
    final ids = <int, int>{};
    for (final cue in cues) {
      ids.putIfAbsent(colorOf(cue), () => ids.length + 1);
    }
    return ids;
  }
}

/// [cues] as an ASS script: one style per speaker colour, the speaker's name
/// in each line's Name field, sized for a 1080p frame.
String _formatAss(_ProWriter w) {
  final styles = w.colorIds;
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
  for (final MapEntry(key: argb, value: id) in styles.entries) {
    buffer.writeln(
      'Style: Speaker$id,Arial,54,${_assColor(argb)},&H000000FF,&H00000000,'
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

  for (final (index, cue) in w.cues.indexed) {
    final (start, end) = w.timings[index];
    final name = _escapeAss(w.nameOf(cue) ?? '').replaceAll(',', ' ');
    final text = w.linesOf(cue).map(_escapeAss).join(r'\N');
    buffer.writeln(
      'Dialogue: 0,${_assTime(start)},${_assTime(end)},'
      'Speaker${styles[w.colorOf(cue)]},$name,0,0,0,,$text',
    );
  }
  return buffer.toString();
}

/// [cues] as TTML: a style per speaker colour, and each speaker as an agent,
/// so the name travels without being drawn.
String _formatTtml(_ProWriter w, {required String language}) {
  final styles = w.colorIds;
  final agents = <String, int>{};
  for (final cue in w.cues) {
    if (w.nameOf(cue) case final name?) {
      agents.putIfAbsent(name, () => agents.length + 1);
    }
  }
  final lang = language.trim().isEmpty ? 'und' : language.trim();

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<tt xmlns="http://www.w3.org/ns/ttml" '
      'xmlns:tts="http://www.w3.org/ns/ttml#styling" '
      'xmlns:ttm="http://www.w3.org/ns/ttml#metadata" '
      'xml:lang="${_xml(lang)}">',
    )
    ..writeln('  <head>')
    ..writeln('    <metadata>');
  for (final MapEntry(key: name, value: id) in agents.entries) {
    buffer.writeln(
      '      <ttm:agent xml:id="speaker$id" type="person">'
      '<ttm:name type="full">${_xml(name)}</ttm:name></ttm:agent>',
    );
  }
  buffer
    ..writeln('    </metadata>')
    ..writeln('    <styling>');
  for (final MapEntry(key: argb, value: id) in styles.entries) {
    buffer.writeln(
      '      <style xml:id="s$id" tts:color="${_hexColor(argb)}" '
      'tts:textAlign="center"/>',
    );
  }
  buffer
    ..writeln('    </styling>')
    ..writeln('  </head>')
    ..writeln('  <body>')
    ..writeln('    <div>');
  for (final (index, cue) in w.cues.indexed) {
    final (start, end) = w.timings[index];
    final agent = switch (w.nameOf(cue)) {
      final name? => ' ttm:agent="speaker${agents[name]}"',
      null => '',
    };
    buffer.writeln(
      '      <p begin="${_timestamp(start, '.')}" end="${_timestamp(end, '.')}" '
      'style="s${styles[w.colorOf(cue)]}"$agent>'
      '${w.linesOf(cue).map(_xml).join('<br/>')}</p>',
    );
  }
  buffer
    ..writeln('    </div>')
    ..writeln('  </body>')
    ..writeln('</tt>');
  return buffer.toString();
}

/// Frames per second of the timelines written for editing tools. Cue times
/// land on these frames, as both editors expect.
const int _editFps = 30;

int _frames(int ms) => (ms * _editFps / 1000).round();

/// A frame count as FCPXML's rational seconds.
String _fcpTime(int frames) =>
    frames == 0 ? '0s' : '${frames * 100}/${_editFps * 100}s';

/// [cues] as FCPXML 1.9: a project whose timeline carries each cue as an iTT
/// caption, in the speaker's colour and named after them.
String _formatFcpxml(
  _ProWriter w, {
  required String title,
  required String language,
}) {
  final lang = language.trim().isEmpty ? 'en' : language.trim();
  final name = _xml(title.trim().isEmpty ? 'Argand' : title.trim());
  final total = w.timings.isEmpty ? 1 : _frames(w.timings.last.$2) + 1;

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE fcpxml>')
    ..writeln('<fcpxml version="1.9">')
    ..writeln('  <resources>')
    ..writeln(
      '    <format id="r1" name="FFVideoFormat1080p30" '
      'frameDuration="100/${_editFps * 100}s" width="1920" height="1080"/>',
    )
    ..writeln('  </resources>')
    ..writeln('  <library>')
    ..writeln('    <event name="$name">')
    ..writeln('      <project name="$name">')
    ..writeln(
      '        <sequence format="r1" duration="${_fcpTime(total)}" '
      'tcStart="0s" tcFormat="NDF">',
    )
    ..writeln('          <spine>')
    ..writeln(
      '            <gap name="Gap" offset="0s" start="0s" '
      'duration="${_fcpTime(total)}">',
    );
  for (final (index, cue) in w.cues.indexed) {
    final (start, end) = w.timings[index];
    final from = _frames(start);
    final length = (_frames(end) - from).clamp(1, 1 << 30);
    final style = 'ts${index + 1}';
    buffer
      ..writeln(
        '              <caption lane="1" offset="${_fcpTime(from)}" '
        'duration="${_fcpTime(length)}" '
        'name="${_xml(w.nameOf(cue) ?? cue.text)}" '
        'role="iTT?captionFormat=ITT.${_xml(lang)}">',
      )
      ..writeln(
        '                <text placement="bottom"><text-style ref="$style">'
        '${w.linesOf(cue).map(_xml).join('&#10;')}</text-style></text>',
      )
      ..writeln(
        '                <text-style-def id="$style"><text-style '
        'font=".AppleSystemUIFont" fontSize="13" fontFace="Regular" '
        'fontColor="${_unitColor(w.colorOf(cue))}" '
        'backgroundColor="0 0 0 1"/></text-style-def>',
      )
      ..writeln('              </caption>');
  }
  buffer
    ..writeln('            </gap>')
    ..writeln('          </spine>')
    ..writeln('        </sequence>')
    ..writeln('      </project>')
    ..writeln('    </event>')
    ..writeln('  </library>')
    ..writeln('</fcpxml>');
  return buffer.toString();
}

/// [cues] as Final Cut 7 XML, which Premiere Pro imports: a sequence with a
/// video track of Text clips, one per cue, in the speaker's colour.
String _formatPremiereXml(_ProWriter w, {required String title}) {
  final name = _xml(title.trim().isEmpty ? 'Argand' : title.trim());
  final total = w.timings.isEmpty ? 1 : _frames(w.timings.last.$2) + 1;
  const rate = '<rate><timebase>$_editFps</timebase><ntsc>FALSE</ntsc></rate>';

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE xmeml>')
    ..writeln('<xmeml version="4">')
    ..writeln('  <sequence id="sequence-1">')
    ..writeln('    <name>$name</name>')
    ..writeln('    <duration>$total</duration>')
    ..writeln('    $rate')
    ..writeln(
      '    <timecode>$rate<string>00:00:00:00</string><frame>0</frame>'
      '<displayformat>NDF</displayformat></timecode>',
    )
    ..writeln('    <media>')
    ..writeln('      <video>')
    ..writeln(
      '        <format><samplecharacteristics>$rate<width>1920</width>'
      '<height>1080</height><pixelaspectratio>square</pixelaspectratio>'
      '</samplecharacteristics></format>',
    )
    ..writeln('        <track>');
  for (final (index, cue) in w.cues.indexed) {
    final (startMs, endMs) = w.timings[index];
    final start = _frames(startMs);
    final end = _frames(endMs) > start ? _frames(endMs) : start + 1;
    final argb = w.colorOf(cue);
    final text = w.linesOf(cue).map(_xml).join('&#13;');
    buffer
      ..writeln('          <generatoritem id="caption-${index + 1}">')
      ..writeln('            <name>${_xml(w.nameOf(cue) ?? cue.text)}</name>')
      ..writeln('            <enabled>TRUE</enabled>')
      ..writeln('            <duration>${end - start}</duration>')
      ..writeln('            $rate')
      ..writeln(
        '            <start>$start</start><end>$end</end>'
        '<in>0</in><out>${end - start}</out>',
      )
      ..writeln(
        '            <effect><name>Text</name><effectid>Text</effectid>'
        '<effectcategory>Text</effectcategory>'
        '<effecttype>generator</effecttype><mediatype>video</mediatype>',
      )
      ..writeln(
        '              <parameter><parameterid>str</parameterid>'
        '<name>Text</name><value>$text</value></parameter>',
      )
      ..writeln(
        '              <parameter><parameterid>fontsize</parameterid>'
        '<name>Size</name><valuemin>0</valuemin><valuemax>1000</valuemax>'
        '<value>36</value></parameter>',
      )
      ..writeln(
        '              <parameter><parameterid>origin</parameterid>'
        '<name>Origin</name><value><horiz>0</horiz><vert>0.35</vert>'
        '</value></parameter>',
      )
      ..writeln(
        '              <parameter><parameterid>fontcolor</parameterid>'
        '<name>Font Color</name><value><alpha>255</alpha>'
        '<red>${(argb >> 16) & 0xFF}</red><green>${(argb >> 8) & 0xFF}</green>'
        '<blue>${argb & 0xFF}</blue></value></parameter>',
      )
      ..writeln('            </effect>')
      ..writeln('          </generatoritem>');
  }
  buffer
    ..writeln('        </track>')
    ..writeln('      </video>')
    ..writeln('    </media>')
    ..writeln('  </sequence>')
    ..writeln('</xmeml>');
  return buffer.toString();
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

/// `#RRGGBB`.
String _hexColor(int argb) =>
    '#${_hex2((argb >> 16) & 0xFF)}${_hex2((argb >> 8) & 0xFF)}'
    '${_hex2(argb & 0xFF)}';

/// FCPXML's `r g b a`, each 0 to 1.
String _unitColor(int argb) {
  String unit(int v) => (v / 255).toStringAsFixed(3);
  return '${unit((argb >> 16) & 0xFF)} ${unit((argb >> 8) & 0xFF)} '
      '${unit(argb & 0xFF)} 1';
}

/// ASS colours are `&HAABBGGRR`, with 00 as opaque.
String _assColor(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return '&H00${_hex2(b)}${_hex2(g)}${_hex2(r)}';
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
