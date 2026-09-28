/// A translation as the picture shows it: each line a text over the video for
/// as long as its sentence is said, just above the captions it translates.
library;

import 'package:flutter/painting.dart' show TextDirection;

import '../database/database.dart';
import 'project_timeline.dart';

/// Which way [text] reads, from its first letter that has a direction: a
/// translation into Arabic, Hebrew, Persian or Urdu is set right to left,
/// whatever the interface's own direction is.
TextDirection translationDirectionOf(String text) {
  final strong = RegExp(r'[A-Za-z\u00C0-\u024F\u0370-\u03FF\u0400-\u04FF'
          r'\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]')
      .firstMatch(text);
  if (strong == null) return TextDirection.ltr;
  final code = strong[0]!.codeUnitAt(0);
  final rtl = (code >= 0x0590 && code <= 0x08FF) ||
      (code >= 0xFB1D && code <= 0xFDFF) ||
      (code >= 0xFE70 && code <= 0xFEFF);
  return rtl ? TextDirection.rtl : TextDirection.ltr;
}

/// Ids of made-up text layers start with this, so a tap handler can tell one
/// from a real text layer.
const String translationTextPrefix = 'translation:';

/// The translation line a made-up text layer shows a piece of, or null for a
/// real text layer.
String? translationLineIdOf(String textId) {
  if (!textId.startsWith(translationTextPrefix)) return null;
  final rest = textId.substring(translationTextPrefix.length);
  final cut = rest.lastIndexOf(':');
  return cut < 0 ? rest : rest.substring(0, cut);
}

/// How far above its captions a translation sits, in shares of the frame's
/// half-height: clear of a two-line caption under a two-line translation.
const double translationLift = 0.26;

/// The most characters one piece of a translation shows at once -- about a
/// caption's two lines. A sentence longer than this is shown in turns.
const int translationChunkCharacters = 40;

/// [text] cut at word boundaries into pieces of at most [maxCharacters] (a
/// single longer word stands alone), each with its share of the characters.
List<(String, int)> translationChunks(
  String text, {
  int maxCharacters = translationChunkCharacters,
}) {
  final chunks = <(String, int)>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final next = current.isEmpty ? word : '$current $word';
    if (current.isNotEmpty && next.length > maxCharacters) {
      chunks.add((current, current.length));
      current = word;
    } else {
      current = next;
    }
  }
  if (current.isNotEmpty) chunks.add((current, current.length));
  return chunks;
}

/// [lines] of a transcript on [clipId], as text layers in project time.
List<TextLayer> translationTextsFor({
  required ProjectTimeline timeline,
  required String projectId,
  required String clipId,
  required List<TranslationLine> lines,
  TranscribeLayer? layer,
}) {
  final texts = <TextLayer>[];
  for (final line in lines) {
    // Its own place and look once it has been given one; until then just
    // above its layer's captions, in their look.
    final x = line.x ?? layer?.captionX ?? 0.0;
    final y = line.y ?? (layer?.captionY ?? -0.82) + translationLift;
    // Text layers are drawn at `textLayerFraction` of the frame, captions at
    // `captionTextFraction`; this brings a translation down to caption size.
    final scale = line.scale ?? (layer?.captionScale ?? 1.0) * (0.045 / 0.06);

    final start = timeline.projectMsOf(clipId: clipId, clipMs: line.startMs);
    final end = timeline.projectMsOf(clipId: clipId, clipMs: line.endMs);
    if (start == null || end == null || end <= start) continue;

    final chunks = translationChunks(line.content);
    final total = chunks.fold<int>(0, (sum, chunk) => sum + chunk.$2);
    var before = 0;
    for (final (i, (content, characters)) in chunks.indexed) {
      final from = start + ((end - start) * before / total).round();
      before += characters;
      final to = i == chunks.length - 1
          ? end
          : start + ((end - start) * before / total).round();
      texts.add(TextLayer(
        id: '$translationTextPrefix${line.id}:$i',
        createdAt: line.createdAt,
        updatedAt: line.updatedAt,
        projectId: projectId,
        startMs: from,
        endMs: to,
        content: content,
        x: x,
        y: y,
        scale: scale,
        rotation: 0,
        trackIndex: 0,
        trackId: line.trackId,
        // The captions' own look -- font, colour, background, shadow -- so a
        // translation reads as part of them and follows the Style panel.
        look: line.look ?? layer?.captionLook,
      ));
    }
  }
  return texts;
}
