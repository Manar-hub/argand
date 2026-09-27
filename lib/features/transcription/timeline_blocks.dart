import 'dart:math' as math;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/timeline/audio_window.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/timeline/timeline_items.dart';
import '../../core/timeline/timeline_selection.dart';
import '../../core/timeline/timeline_sentences.dart';
import 'transcript_repository.dart';

part 'timeline_blocks.g.dart';

/// Everything on a project's timeline, as the tracks draw it and the move
/// rules see it: the tracks, one [TimelineBlock] per item, and the row behind
/// each block for drawing it.
typedef TimelineContents = ({
  List<Track> tracks,
  List<TimelineBlock> blocks,
  Map<String, MediaClip> clips,
  Map<String, TranscribeLayer> layers,
  Map<TimelineItem, TimelineSentence> sentences,
  Map<String, TextLayer> texts,
  Map<String, ProjectTranslationLine> translations,
  Map<String, ImageLayer> images,
});

/// The project's timeline as blocks on tracks.
///
/// **One list for every kind**, which is what lets one set of gestures move,
/// resize and select any of them: the tracks draw from it, the drag plans on
/// it (`planMove`), and a long press on a track selects what it lists there.
@riverpod
TimelineContents timelineContents(Ref ref, String projectId) {
  final tracks = ref.watch(projectTracksProvider(projectId)).value ?? const [];
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
  final timeline = ref.watch(projectTimelineProvider(projectId));
  final layers = ref.watch(projectLayersProvider(projectId)).value ?? const [];
  final sentences = ref.watch(projectSentencesProvider(projectId));
  final texts =
      ref.watch(projectTextLayersProvider(projectId)).value ?? const [];
  final lines = ref.watch(projectTranslationLinesProvider(projectId));
  final images =
      ref.watch(projectImageLayersProvider(projectId)).value ?? const [];

  return timelineContentsOf(
    tracks: tracks,
    clips: clips,
    timeline: timeline,
    layers: layers,
    sentences: sentences,
    texts: texts,
    lines: lines,
    images: images,
  );
}

/// [timelineContents] without the providers, for tests.
TimelineContents timelineContentsOf({
  required List<Track> tracks,
  required List<MediaClip> clips,
  required ProjectTimeline timeline,
  required List<TranscribeLayer> layers,
  required List<TimelineSentence> sentences,
  required List<TextLayer> texts,
  required List<ProjectTranslationLine> lines,
  required List<ImageLayer> images,
}) {
  final total = timeline.totalMs;
  final known = {for (final track in tracks) track.id};
  String? trackOf(TrackKind kind) => tracks
      .where((t) => TrackKind.fromCode(t.kind) == kind)
      .firstOrNull
      ?.id;
  final video = trackOf(TrackKind.video) ?? '';
  final audio = trackOf(TrackKind.audio) ?? '';
  // Anything whose track is not (yet) known is drawn on the first media
  // track rather than dropped; `ensureTracks` places it properly.
  final fallback = trackOf(TrackKind.media) ?? video;
  String placed(String? trackId) =>
      trackId != null && known.contains(trackId) ? trackId : fallback;

  final blocks = <TimelineBlock>[];
  TimelineBlock block(
    TimelineItem item,
    String trackId,
    int start,
    int end, {
    int? minStart,
    int? maxEnd,
    bool canChangeTrack = true,
    String? layerId,
    bool follows = false,
  }) =>
      (
        item: item,
        trackId: trackId,
        startMs: start,
        endMs: end,
        minStartMs: minStart ?? 0,
        maxEndMs: maxEnd ?? math.max(total, end),
        canChangeTrack: canChangeTrack,
        layerId: layerId,
        follows: follows,
      );

  for (final clip in clips) {
    final placement = timeline.placementOf(clip.id);
    if (placement == null) continue;
    final end = placement.startMs + placement.durationMs;
    blocks.add(block(
      (kind: TimelineItemKind.clip, id: clip.id),
      video,
      placement.startMs,
      end,
      minStart: placement.startMs,
      maxEnd: end,
      canChangeTrack: false,
    ));
    final span = audioSpan(timeline, clip);
    if (span != null) {
      // A sound slides against its picture no further than its file holds.
      final mediaEnd = span.mediaStartMs + (span.endMs - span.startMs);
      final fileEnd = clip.durationMs ?? mediaEnd;
      blocks.add(block(
        (kind: TimelineItemKind.audio, id: clip.id),
        audio,
        span.startMs,
        span.endMs,
        minStart: math.max(0, span.startMs - span.mediaStartMs),
        maxEnd: math.min(total, span.endMs + (fileEnd - mediaEnd)),
        canChangeTrack: false,
      ));
    }
  }

  final layerTrack = <String, String>{};
  for (final layer in layers) {
    final trackId = placed(layer.trackId);
    layerTrack[layer.id] = trackId;
    blocks.add(block(
      (kind: TimelineItemKind.layer, id: layer.id),
      trackId,
      layer.startMs,
      layer.endMs,
      layerId: layer.id,
    ));
  }

  // A sentence may not cross its neighbours in its own transcript: the words
  // would come out of order.
  final byTranscript = <String, List<TimelineSentence>>{};
  for (final sentence in sentences) {
    (byTranscript[sentence.transcriptId] ??= []).add(sentence);
  }
  final sentenceRows = <TimelineItem, TimelineSentence>{};
  for (final list in byTranscript.values) {
    list.sort((a, b) => a.projectStartMs - b.projectStartMs);
    for (final (i, sentence) in list.indexed) {
      final item = sentenceItem(
        transcriptId: sentence.transcriptId,
        fromPosition: sentence.fromPosition,
        toPosition: sentence.toPosition,
      );
      sentenceRows[item] = sentence;
      final ownTrack = layerTrack[sentence.layerId] ?? fallback;
      final moved = sentence.trackId != null &&
          known.contains(sentence.trackId) &&
          sentence.trackId != ownTrack;
      blocks.add(block(
        item,
        moved ? sentence.trackId! : ownTrack,
        sentence.projectStartMs,
        sentence.projectEndMs,
        minStart: i == 0 ? 0 : list[i - 1].projectEndMs,
        maxEnd: i == list.length - 1 ? total : list[i + 1].projectStartMs,
        layerId: sentence.layerId,
        follows: !moved,
      ));
    }
  }

  for (final text in texts) {
    blocks.add(block(
      (kind: TimelineItemKind.text, id: text.id),
      placed(text.trackId),
      text.startMs,
      text.endMs,
    ));
  }
  for (final line in lines) {
    blocks.add(block(
      (kind: TimelineItemKind.translation, id: line.line.id),
      placed(line.line.trackId),
      line.projectStartMs,
      line.projectEndMs,
    ));
  }
  for (final image in images) {
    blocks.add(block(
      (kind: TimelineItemKind.image, id: image.id),
      placed(image.trackId),
      image.startMs,
      image.endMs,
    ));
  }

  return (
    tracks: tracks,
    blocks: blocks,
    clips: {for (final clip in clips) clip.id: clip},
    layers: {for (final layer in layers) layer.id: layer},
    sentences: sentenceRows,
    texts: {for (final text in texts) text.id: text},
    translations: {for (final line in lines) line.line.id: line},
    images: {for (final image in images) image.id: image},
  );
}
