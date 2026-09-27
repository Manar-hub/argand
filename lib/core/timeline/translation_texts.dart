/// A translation as the picture shows it: each line a text over the video for
/// as long as its sentence is said, just above the captions it translates.
///
/// **Text layers, not a new kind of overlay.** The stage already draws text
/// layers and the export already burns them in, so a translation line handed
/// over as one is shown and exported with nothing new in either. The rows are
/// made up here and never stored as text layers: the text track does not list
/// them and they cannot be picked, moved or retyped there.
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
///
/// **At caption size, and in caption-sized pieces.** A whole translated
/// sentence can run to several lines, and grown from its centre it would sit
/// on top of the captions; cut like captions are, each piece is at most two
/// lines and is shown for its share of the sentence's time.
///
/// Lines whose sentence falls outside what the timeline plays -- trimmed
/// away -- are left out, as their captions are.
List<TextLayer> translationTextsFor({
  required ProjectTimeline timeline,
  required String projectId,
  required String clipId,
  required List<TranslationLine> lines,
  TranscribeLayer? layer,
}) {
  final x = layer?.captionX ?? 0.0;
  final y = (layer?.captionY ?? -0.82) + translationLift;
  // Text layers are drawn at `textLayerFraction` of the frame, captions at
  // `captionTextFraction`; this brings a translation down to caption size.
  final scale = (layer?.captionScale ?? 1.0) * (0.045 / 0.06);

  final texts = <TextLayer>[];
  for (final line in lines) {
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
        // The captions' own look -- font, colour, background, shadow -- so a
        // translation reads as part of them and follows the Style panel.
        look: layer?.captionLook,
      ));
    }
  }
  return texts;
}
