import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/audio/waveform_service.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/database/database.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/media/media_converter.dart';
import '../../core/transcript/edit_event.dart';
import '../../core/transcript/sentence_edit.dart';
import '../../core/timeline/audio_window.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/layer_drag.dart';
import '../../core/timeline/timeline_event.dart';
import '../../core/timeline/timeline_items.dart';
import '../../core/timeline/timeline_selection.dart';
import 'timeline_history.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/timeline/timeline_sentences.dart';
import '../../core/transcript/speaker_names.dart';
import '../../core/transcript/translation_sentences.dart';
import '../../core/timeline/translation_texts.dart';
import '../../core/translation/translator.dart';
import '../../core/whisper/transcription_language_controller.dart';
import 'editor_mode_controller.dart';

part 'transcript_repository.g.dart';

/// The `Settings` key holding where playback last stopped in [clipId].
///
/// Namespaced like every other per-entity key because `Settings` is one shared
/// key/value table -- the same reason `whisper_model_controller.dart`
/// namespaces its own.
///
/// **Keyed by media path**, having been keyed by clip and, before that, by
/// project. The decoder is shared by file now, because splitting a clip must
/// not reload the picture, and a position belongs to whatever owns the
/// decoder. Two clips over one file therefore share where you were in it.
///
/// Keys written under the old `clip.<id>.positionMs` shape are simply never
/// read again. They are soft-deletable settings rows, not worth a migration.
String playbackPositionKey(String mediaPath) => 'media.\$mediaPath.positionMs';

/// All persistence for projects and their transcripts.
///
/// Widgets never touch Drift directly (CLAUDE.md 4) -- they read the streams
/// and call the methods exposed here through Riverpod.
///
/// It also owns the [MediaConverter] for the one operation where the database
/// and the filesystem have to agree: deleting a project must remove both its
/// rows and its media, and splitting that across two callers is how one of them
/// gets forgotten.
class TranscriptRepository {
  TranscriptRepository(this._db, this._media);

  final AppDatabase _db;
  final MediaConverter _media;
  static const _uuid = Uuid();

  /// UUIDs are generated on-device, never delegated to the database
  /// (CLAUDE.md 5 -- no auto-increment IDs).
  String newId() => _uuid.v4();

  Stream<List<Project>> watchProjects() => _db.watchProjects();

  Stream<List<LibraryHit>> watchLibrarySearch(String query) =>
      _db.watchLibrarySearch(query);

  Future<Project?> findProject(String id) => _db.findProject(id);

  Future<List<Transcript>> transcriptsForClip(String clipId) =>
      _db.transcriptsForClip(clipId);

  Stream<List<Transcript>> watchTranscriptsForClip(String clipId) =>
      _db.watchTranscriptsForClip(clipId);

  Stream<List<TranscribeLayer>> watchLayers(String projectId) =>
      _db.watchLayers(projectId);

  Future<List<TranscribeLayer>> layersForProject(String projectId) =>
      _db.layersForProject(projectId);

  Future<TranscribeLayer?> findLayer(String layerId) => _db.findLayer(layerId);

  Future<List<Transcript>> transcriptsForLayer(String layerId) =>
      _db.transcriptsForLayer(layerId);

  Future<Transcript?> findTranscript(String id) => _db.findTranscript(id);

  /// Adds a layer covering [startMs]–[endMs] on the project timeline.
  ///
  /// Returns null when the range would overlap a layer already on that track.
  /// **Layers on one track may not overlap**, which is what makes "which layer
  /// owns this audio" a question with one answer — and the check lives here so
  /// both drawing a new layer and dragging an existing one are held to it.
  Future<String?> addLayer({
    required String projectId,
    required int startMs,
    required int endMs,
    int trackIndex = 0,
  }) async {
    if (endMs <= startMs) return null;

    final existing = await _db.layersForProject(projectId);
    if (_overlaps(existing, startMs: startMs, endMs: endMs, trackIndex: trackIndex)) {
      return null;
    }

    final layerId = newId();
    await _db.insertLayer(
      layerId: layerId,
      projectId: projectId,
      startMs: startMs,
      endMs: endMs,
      trackIndex: trackIndex,
      trackId: await _layerTrack(projectId),
    );

    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.layerAdd,
      payload: layerAddPayload(layerId: layerId),
    );

    return layerId;
  }

  /// Cuts a layer in two at [atProjectMs].
  ///
  /// Returns the new layer's id, or null when the split was refused -- either
  /// half would be under [minimumLayerMs], or the playhead is outside the
  /// layer entirely.
  ///
  /// **Shrinks the original before adding the tail.** Adding it first would be
  /// rejected by the very overlap rule the two halves are about to satisfy,
  /// because the original still covers that range at that moment. If the add
  /// fails anyway the shrink is undone, so a refused split leaves the layer as
  /// it was rather than silently shortened.
  Future<String?> splitLayer({
    required String layerId,
    required int atProjectMs,
  }) async {
    final layer = await _db.findLayer(layerId);
    if (layer == null) return null;

    if (atProjectMs - layer.startMs < minimumLayerMs) return null;
    if (layer.endMs - atProjectMs < minimumLayerMs) return null;

    final originalEnd = layer.endMs;

    final shrank = await moveLayer(
      layerId: layerId,
      startMs: layer.startMs,
      endMs: atProjectMs,
    );
    if (!shrank) return null;

    final tail = await addLayer(
      projectId: layer.projectId,
      startMs: atProjectMs,
      endMs: originalEnd,
      trackIndex: layer.trackIndex,
    );

    if (tail == null) {
      await moveLayer(
        layerId: layerId,
        startMs: layer.startMs,
        endMs: originalEnd,
      );
    }
    return tail;
  }

  /// Moves or resizes a layer, refusing a range that would overlap another.
  Future<bool> moveLayer({
    required String layerId,
    required int startMs,
    required int endMs,
  }) async {
    if (endMs <= startMs) return false;

    final layer = await _db.findLayer(layerId);
    if (layer == null) return false;

    final existing = await _db.layersForProject(layer.projectId);
    if (_overlaps(
      existing,
      startMs: startMs,
      endMs: endMs,
      trackIndex: layer.trackIndex,
      ignoring: layerId,
    )) {
      return false;
    }

    await _db.moveLayer(layerId: layerId, startMs: startMs, endMs: endMs);

    await recordTimelineEvent(
      projectId: layer.projectId,
      kind: TimelineEventKind.layerMove,
      payload: layerMovePayload(
        layerId: layerId,
        fromStartMs: layer.startMs,
        fromEndMs: layer.endMs,
        toStartMs: startMs,
        toEndMs: endMs,
      ),
    );

    return true;
  }

  Future<void> removeLayer(String layerId) => _db.softDeleteLayer(layerId);

  /// Commits one gesture: writes every item's new placement and records the
  /// whole set as one undoable step.
  Future<void> applyPlacements({
    required String projectId,
    required List<PlacementChange> changes,
  }) async {
    final moved = [
      for (final change in changes)
        if (change.before != change.after) change,
    ];
    if (moved.isEmpty) return;

    await _db.transaction(() async {
      for (final change in moved) {
        await writePlacement(
          _db,
          kind: change.kind,
          id: change.id,
          transform: change.after,
        );
      }
    });
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.transformBatch,
      payload: transformBatchPayload(moved),
    );
  }

  /// Restyles everything in [changes] as one undoable step.
  ///
  /// [resetSentencesIn] names transcripts whose sentences styled on their own
  /// should go back to following their layer -- what "all captions" means, so
  /// the whole transcription ends up matching.
  Future<void> applyLooks({
    required String projectId,
    required List<LookChange> changes,
    List<String> resetSentencesIn = const [],
  }) async {
    final wordLooks = <String, String?>{
      for (final word in await _db.wordsWithOwnLook(resetSentencesIn))
        word.id: word.captionLook,
    };
    final changed = [
      for (final change in changes)
        if (change.before != change.after) change,
    ];
    if (changed.isEmpty && wordLooks.isEmpty) return;

    await _db.transaction(() async {
      if (wordLooks.isNotEmpty) {
        await _db.setWordLooks({for (final id in wordLooks.keys) id: null});
      }
      for (final change in changed) {
        await writeLook(_db, kind: change.kind, id: change.id, look: change.after);
      }
    });
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.lookBatch,
      payload: lookBatchPayload(changed, wordLooks: wordLooks),
    );
  }

  /// The look of the layer a transcript came from, or null for the default.
  Future<ItemLook?> layerLookOfTranscript(String transcriptId) async {
    final transcript = await _db.findTranscript(transcriptId);
    final layerId = transcript?.layerId;
    if (layerId == null) return null;
    return (await _db.findLayer(layerId))?.look;
  }

  /// The look a sentence has of its own, or null while it follows its layer.
  Future<ItemLook?> sentenceLook({
    required String transcriptId,
    required int fromPosition,
  }) async =>
      (await _db.wordAt(transcriptId: transcriptId, position: fromPosition))
          ?.ownLook;

  /// A project's text layers, in timeline order.
  Stream<List<TextLayer>> watchTextLayers(String projectId) =>
      _db.watchTextLayers(projectId);

  Future<List<TextLayer>> textLayersForProject(String projectId) =>
      _db.textLayersForProject(projectId);

  /// Puts [content] on the picture for [startMs]–[endMs], centred.
  Future<String?> addTextLayer({
    required String projectId,
    required int startMs,
    required int endMs,
    required String content,
  }) async {
    final words = content.trim();
    if (endMs <= startMs || words.isEmpty) return null;

    // **The first track it fits on.** Two texts at the same moment on one
    // track would draw one block over the other, and the one underneath could
    // not be reached to select it.
    final trackId = await _freeTrack(projectId, startMs, endMs);

    final id = newId();
    await _db.insertTextLayer(
      id: id,
      projectId: projectId,
      startMs: startMs,
      endMs: endMs,
      content: words,
      trackId: trackId,
    );
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.textAdd,
      payload: textAddPayload(id: id),
    );
    return id;
  }

  /// Changes a text's words or timing; what is not given stays as it is.
  Future<void> editTextLayer({
    required String id,
    String? content,
    int? startMs,
    int? endMs,
  }) async {
    final before = await _db.findTextLayer(id);
    if (before == null) return;

    final words = content?.trim();
    final nextContent = (words == null || words.isEmpty) ? before.content : words;
    final nextStart = startMs ?? before.startMs;
    final nextEnd = endMs ?? before.endMs;
    if (nextEnd <= nextStart) return;
    if (nextContent == before.content &&
        nextStart == before.startMs &&
        nextEnd == before.endMs) {
      return;
    }

    await _db.updateTextLayer(
      id: id,
      content: nextContent,
      startMs: nextStart,
      endMs: nextEnd,
    );
    await recordTimelineEvent(
      projectId: before.projectId,
      kind: TimelineEventKind.textEdit,
      payload: textEditPayload(
        before: before,
        content: nextContent,
        startMs: nextStart,
        endMs: nextEnd,
      ),
    );
  }

  Future<void> removeTextLayer(String id) async {
    final text = await _db.findTextLayer(id);
    if (text == null || text.deletedAt != null) return;

    await _db.setTextLayerRetired(id: id, retired: true);
    await recordTimelineEvent(
      projectId: text.projectId,
      kind: TimelineEventKind.textRemove,
      payload: textRemovePayload(id: id),
    );
  }

  // ---------------------------------------------------------------------------
  // Tracks, and moving things between them.

  Stream<List<Track>> watchTracks(String projectId) =>
      _db.watchTracks(projectId);

  /// The project's tracks, placing anything not yet on one. See
  /// [AppDatabase.ensureTracks].
  Future<List<Track>> ensureTracks(String projectId) =>
      _db.ensureTracks(projectId);

  /// Where on each track something already sits, in project time.
  Future<Map<String, List<(int, int)>>> _occupied(String projectId) async {
    final taken = <String, List<(int, int)>>{};
    void add(String? trackId, int start, int end) {
      if (trackId == null) return;
      (taken[trackId] ??= []).add((start, end));
    }

    final clips = await _db.clipsForProject(projectId);
    final timeline = ProjectTimeline.fromClips(clips);
    for (final layer in await _db.layersForProject(projectId)) {
      add(layer.trackId, layer.startMs, layer.endMs);
    }
    for (final text in await _db.textLayersForProject(projectId)) {
      add(text.trackId, text.startMs, text.endMs);
    }
    for (final image in await _db.imageLayersForProject(projectId)) {
      add(image.trackId, image.startMs, image.endMs);
    }
    for (final clip in clips) {
      for (final transcript in await _db.transcriptsForClip(clip.id)) {
        for (final line in await _db.translationLinesFor(transcript.id)) {
          final start =
              timeline.projectMsOf(clipId: clip.id, clipMs: line.startMs);
          final end = timeline.projectMsOf(clipId: clip.id, clipMs: line.endMs);
          if (start != null && end != null) add(line.trackId, start, end);
        }
        for (final word in await _db.wordsMovedOffTheirLayer(transcript.id)) {
          final start =
              timeline.projectMsOf(clipId: clip.id, clipMs: word.startMs);
          final end = timeline.projectMsOf(clipId: clip.id, clipMs: word.endMs);
          if (start != null && end != null) {
            add(word.captionTrackId, start, end);
          }
        }
      }
    }
    return taken;
  }

  /// The first media track, from the top, with nothing on it over
  /// [startMs]..[endMs] -- or a new one at the top when every track is taken.
  Future<String> _freeTrack(String projectId, int startMs, int endMs) async {
    final tracks = await ensureTracks(projectId);
    final taken = await _occupied(projectId);
    for (final track in tracks) {
      if (TrackKind.fromCode(track.kind) != TrackKind.media) continue;
      final busy = (taken[track.id] ?? const [])
          .any((span) => span.$1 < endMs && startMs < span.$2);
      if (!busy) return track.id;
    }
    final id = newId();
    await _db.insertTrack(id: id, projectId: projectId, position: 0);
    return id;
  }

  /// The track a new transcription goes on: wherever the project's
  /// transcriptions already are, else a new one just above the video.
  Future<String> _layerTrack(String projectId) async {
    final tracks = await ensureTracks(projectId);
    final live = {for (final track in tracks) track.id};
    for (final layer in await _db.layersForProject(projectId)) {
      if (live.contains(layer.trackId)) return layer.trackId!;
    }
    final video =
        tracks.indexWhere((t) => TrackKind.fromCode(t.kind) == TrackKind.video);
    final id = newId();
    await _db.insertTrack(
      id: id,
      projectId: projectId,
      position: video < 0 ? 0 : video,
    );
    return id;
  }

  /// The track a transcript's new translation goes on: where its translation
  /// already was, else where the project's translations are, else a new one
  /// just above its transcription.
  Future<String> _translationTrack(Transcript transcript) async {
    final projectId = transcript.projectId;
    final tracks = await ensureTracks(projectId);
    final live = {for (final track in tracks) track.id};
    for (final line in await _db.translationLinesFor(transcript.id)) {
      if (live.contains(line.trackId)) return line.trackId!;
    }
    for (final line in await _db.translationLinesForProject(projectId)) {
      if (live.contains(line.trackId)) return line.trackId!;
    }
    final layer = transcript.layerId == null
        ? null
        : await _db.findLayer(transcript.layerId!);
    final below = tracks.indexWhere((t) => t.id == layer?.trackId);
    final id = newId();
    await _db.insertTrack(
      id: id,
      projectId: projectId,
      position: below < 0 ? 0 : below,
    );
    return id;
  }

  /// Commits one drag or resize on the timeline -- everything it moved, the
  /// tracks it made, the clip order it changed -- as one undoable step.
  ///
  /// **Times arrive in project time, and are written as each row keeps
  /// them.** A transcription, a text and an image are stored in project time;
  /// a translation line and a sentence's words in their clip's; a sound as
  /// offsets from its picture. Each is moved by how far its edges moved, so
  /// the conversion needs nothing but the difference.
  Future<void> placeItems({
    required String projectId,
    required List<ItemPlacement> placements,
    int newTracks = 0,
    List<String>? clipOrder,
  }) async {
    final beforeItems = <Map<String, Object?>>[];
    final afterItems = <Map<String, Object?>>[];
    final beforeWords = <Map<String, Object?>>[];
    final afterWords = <Map<String, Object?>>[];
    final beforeAudio = <Map<String, Object?>>[];
    final afterAudio = <Map<String, Object?>>[];
    final created = <String>[];
    List<String>? orderBefore;

    await _db.transaction(() async {
      for (var i = 0; i < newTracks; i++) {
        final id = newId();
        await _db.insertTrack(id: id, projectId: projectId);
        created.add(id);
      }

      for (final placement in placements) {
        final item = placement.item;
        final id = item.id;
        final dStart = placement.toStartMs - placement.fromStartMs;
        final dEnd = placement.toEndMs - placement.fromEndMs;
        final track = placement.newTrack != null
            ? created[placement.newTrack!]
            : placement.trackId;
        Map<String, Object?> entry(int start, int end, String? trackId) => {
              'kind': item.kind.name,
              'id': id,
              'startMs': start,
              'endMs': end,
              'trackId': trackId,
            };

        switch (item.kind) {
          case TimelineItemKind.layer:
            final row = await _db.findLayer(id);
            if (row == null) continue;
            beforeItems.add(entry(row.startMs, row.endMs, row.trackId));
            await _db.moveLayer(
              layerId: id,
              startMs: placement.toStartMs,
              endMs: placement.toEndMs,
            );
            if (track != null) {
              await _db.setLayerTrack(layerId: id, trackId: track);
            }
            afterItems.add(entry(
              placement.toStartMs,
              placement.toEndMs,
              track ?? row.trackId,
            ));

          case TimelineItemKind.text:
            final row = await _db.findTextLayer(id);
            if (row == null) continue;
            beforeItems.add(entry(row.startMs, row.endMs, row.trackId));
            await _db.updateTextLayer(
              id: id,
              startMs: placement.toStartMs,
              endMs: placement.toEndMs,
              trackId: track,
            );
            afterItems.add(entry(
              placement.toStartMs,
              placement.toEndMs,
              track ?? row.trackId,
            ));

          case TimelineItemKind.image:
            final row = await _db.findImageLayer(id);
            if (row == null) continue;
            beforeItems.add(entry(row.startMs, row.endMs, row.trackId));
            await _db.updateImageLayer(
              id: id,
              startMs: placement.toStartMs,
              endMs: placement.toEndMs,
              trackId: track,
            );
            afterItems.add(entry(
              placement.toStartMs,
              placement.toEndMs,
              track ?? row.trackId,
            ));

          case TimelineItemKind.translation:
            final row = await _db.findTranslationLine(id);
            if (row == null) continue;
            beforeItems.add(entry(row.startMs, row.endMs, row.trackId));
            final start = row.startMs + dStart;
            final end = row.endMs + dEnd;
            await _db.updateTranslationLine(
              id: id,
              startMs: start,
              endMs: end,
              trackId: track,
            );
            afterItems.add(entry(start, end, track ?? row.trackId));

          case TimelineItemKind.sentence:
            final sentence = sentenceOf(item);
            if (sentence == null) continue;
            final words = await _db.wordsInPositionRange(
              transcriptId: sentence.transcriptId,
              from: sentence.fromPosition,
              to: sentence.toPosition,
            );
            if (words.isEmpty) continue;
            // On its transcription's own track it follows the transcription
            // again, rather than being pinned to where that track is now.
            final transcript = await _db.findTranscript(sentence.transcriptId);
            final layer = transcript?.layerId == null
                ? null
                : await _db.findLayer(transcript!.layerId!);
            final from = words.map((w) => w.startMs).reduce(math.min);
            final to = words.map((w) => w.endMs).reduce(math.max);
            final retimed = retimeWords(
              [for (final w in words) (id: w.id, startMs: w.startMs, endMs: w.endMs)],
              startMs: from + dStart,
              endMs: to + dEnd,
            );
            final onTrack = track == null
                ? words.first.captionTrackId
                : (track == layer?.trackId ? null : track);
            for (final word in words) {
              beforeWords.add({
                'id': word.id,
                'startMs': word.startMs,
                'endMs': word.endMs,
                'trackId': word.captionTrackId,
              });
            }
            final placed = [
              for (final word in retimed)
                (
                  id: word.id,
                  startMs: word.startMs,
                  endMs: word.endMs,
                  trackId: onTrack,
                ),
            ];
            await _db.setWordPlacements(placed);
            for (final word in placed) {
              afterWords.add({
                'id': word.id,
                'startMs': word.startMs,
                'endMs': word.endMs,
                'trackId': word.trackId,
              });
            }

          case TimelineItemKind.audio:
            final clip = await _db.findClip(id);
            if (clip == null) continue;
            final start = clip.audioStartOffsetMs + dStart;
            final end = clip.audioEndOffsetMs + dEnd;
            beforeAudio.add({
              'clipId': id,
              'startOffsetMs': clip.audioStartOffsetMs,
              'endOffsetMs': clip.audioEndOffsetMs,
            });
            await _db.setAudioOffsets(
              clipId: id,
              startOffsetMs: start,
              endOffsetMs: end,
            );
            afterAudio.add({
              'clipId': id,
              'startOffsetMs': start,
              'endOffsetMs': end,
            });

          case TimelineItemKind.clip:
            // A clip moves by the order below; its trims have their own path.
            break;
        }
      }

      if (clipOrder != null) {
        orderBefore = [
          for (final clip in await _db.clipsForProject(projectId)) clip.id,
        ];
        await _db.reorderClips(projectId: projectId, orderedIds: clipOrder);
      }
    });

    final orderChanged = clipOrder != null &&
        orderBefore != null &&
        !listEquals(orderBefore, clipOrder);
    if (beforeItems.isEmpty &&
        beforeWords.isEmpty &&
        beforeAudio.isEmpty &&
        created.isEmpty &&
        !orderChanged) {
      return;
    }

    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.itemsPlace,
      payload: TimelineEventPayload(
        before: {
          'projectId': projectId,
          'items': beforeItems,
          'words': beforeWords,
          'audio': beforeAudio,
          'tracks': [for (final id in created) {'id': id, 'retired': true}],
          if (orderChanged) 'clipOrder': orderBefore,
        },
        after: {
          'projectId': projectId,
          'items': afterItems,
          'words': afterWords,
          'audio': afterAudio,
          'tracks': [for (final id in created) {'id': id, 'retired': false}],
          if (orderChanged) 'clipOrder': clipOrder,
        },
      ),
    );
  }

  /// Puts the project's tracks in [order], top to bottom, as one undoable
  /// step -- the gutter's move handle.
  Future<void> reorderTracks({
    required String projectId,
    required List<String> order,
  }) async {
    final before = [
      for (final track in await _db.tracksForProject(projectId)) track.id,
    ];
    if (listEquals(before, order)) return;
    await _db.setTrackOrder(order);
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.itemsPlace,
      payload: TimelineEventPayload(
        before: {'trackOrder': before},
        after: {'trackOrder': order},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Images.

  Stream<List<ImageLayer>> watchImageLayers(String projectId) =>
      _db.watchImageLayers(projectId);

  Future<List<ImageLayer>> imageLayersForProject(String projectId) =>
      _db.imageLayersForProject(projectId);

  /// Copies [fileName] into the project as a picture over [startMs]..[endMs],
  /// on the first track free there, and returns its id.
  Future<String> addImage({
    required String projectId,
    required String fileName,
    required Stream<List<int>> bytes,
    required int startMs,
    required int endMs,
  }) async {
    final id = newId();
    final media = await _media.importToAppStorage(
      projectId: projectId,
      clipId: id,
      fileName: fileName,
      bytes: bytes,
    );
    final size = await _imageSize(media.path);
    final trackId = await _freeTrack(projectId, startMs, endMs);
    final now = DateTime.now();
    await _db.insertImageLayer(ImageLayersCompanion.insert(
      id: id,
      createdAt: now,
      updatedAt: now,
      projectId: projectId,
      trackId: trackId,
      startMs: startMs,
      endMs: endMs,
      path: media.path,
      widthPx: size.width,
      heightPx: size.height,
    ));
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.imageAdd,
      payload: TimelineEventPayload(
        before: {'id': id, 'retired': true},
        after: {'id': id, 'retired': false},
      ),
    );
    return id;
  }

  /// The pixel size of the picture at [path]; 1x1 when it cannot be read,
  /// which draws square rather than failing the add.
  Future<({int width, int height})> _imageSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (width: descriptor.width, height: descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return size;
    } on Exception {
      return (width: 1, height: 1);
    }
  }

  Future<void> removeImages(String projectId, List<String> ids) async {
    for (final id in ids) {
      final image = await _db.findImageLayer(id);
      if (image == null || image.deletedAt != null) continue;
      await _db.setImageLayerRetired(id: id, retired: true);
      await recordTimelineEvent(
        projectId: projectId,
        kind: TimelineEventKind.imageRemove,
        payload: TimelineEventPayload(
          before: {'id': id, 'retired': false},
          after: {'id': id, 'retired': true},
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Translation lines, one at a time.

  Future<TranslationLine?> findTranslationLine(String id) =>
      _db.findTranslationLine(id);

  /// Retypes one translation line, as one undoable step.
  Future<void> editTranslationLine({
    required String projectId,
    required String id,
    required String content,
  }) async {
    final line = await _db.findTranslationLine(id);
    final typed = content.trim();
    if (line == null || typed.isEmpty || typed == line.content) return;
    await _db.updateTranslationLine(id: id, content: typed);
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.translationEdit,
      payload: TimelineEventPayload(
        before: {'id': id, 'content': line.content},
        after: {'id': id, 'content': typed},
      ),
    );
  }

  /// Sets one caption line's translation to [content], as one undoable step
  /// -- Script mode's edit, independent of the transcript's own words.
  ///
  /// [lineIds] are the lines shown under that caption line: the first takes
  /// the text and any others are retired, so it reads as one line again. With
  /// none, a line is added over the caption's words and time, in the
  /// transcript's translation language, on its translation track. Empty
  /// [content] retires them all.
  Future<void> setCueTranslation({
    required String transcriptId,
    required List<String> lineIds,
    required int firstWord,
    required int lastWord,
    required int startMs,
    required int endMs,
    required String content,
  }) async {
    final transcript = await _db.findTranscript(transcriptId);
    if (transcript == null) return;
    final typed = content.trim();
    final lines = [
      for (final id in lineIds) ?await _db.findTranslationLine(id),
    ];
    final before = <Map<String, Object?>>[];
    final after = <Map<String, Object?>>[];

    if (lines.isEmpty) {
      if (typed.isEmpty) return;
      final language = (await _db.translationLinesFor(transcriptId))
              .firstOrNull
              ?.language ??
          (await _db.translationLinesForProject(transcript.projectId))
              .firstOrNull
              ?.language ??
          'und';
      final trackId = await _translationTrack(transcript);
      final id = newId();
      final now = DateTime.now();
      await _db.into(_db.translationLines).insert(
            TranslationLinesCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              transcriptId: transcriptId,
              language: language,
              position: 0,
              firstWord: firstWord,
              lastWord: lastWord,
              startMs: startMs,
              endMs: endMs,
              content: typed,
              trackId: Value(trackId),
            ),
          );
      before.add({'id': id, 'content': typed, 'retired': true});
      after.add({'id': id, 'content': typed, 'retired': false});
    } else {
      final first = lines.first;
      if (lines.length == 1 && typed == first.content) return;
      await _db.transaction(() async {
        for (final (i, line) in lines.indexed) {
          final keeps = i == 0 && typed.isNotEmpty;
          before.add({'id': line.id, 'content': line.content, 'retired': false});
          after.add({
            'id': line.id,
            'content': keeps ? typed : line.content,
            'retired': !keeps,
          });
          if (keeps) {
            await _db.updateTranslationLine(id: line.id, content: typed);
          } else {
            await _db.setTranslationLineRetired(id: line.id, retired: true);
          }
        }
      });
    }

    await recordTimelineEvent(
      projectId: transcript.projectId,
      kind: TimelineEventKind.translationSet,
      payload: TimelineEventPayload(
        before: {'lines': before},
        after: {'lines': after},
      ),
    );
  }

  /// Removes translation lines, as one undoable step.
  Future<void> removeTranslationLines({
    required String projectId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      await _db.setTranslationLineRetired(id: id, retired: true);
    }
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.translationRemove,
      payload: TimelineEventPayload(
        before: {'ids': ids, 'retired': false},
        after: {'ids': ids, 'retired': true},
      ),
    );
  }

  /// Removes a sentence's words from its transcript, through the same undo
  /// log a retype in the script uses.
  Future<void> removeSentence({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
  }) async {
    await _db.transaction(() async {
      final existing = await _db.wordsInPositionRange(
        transcriptId: transcriptId,
        from: fromPosition,
        to: toPosition,
      );
      if (existing.isEmpty) return;
      await _db.spliceWords(
        transcriptId: transcriptId,
        fromPosition: fromPosition,
        toPosition: toPosition,
        replacements: const [],
      );
      await _db.appendEditEvent(
        transcriptId: transcriptId,
        kind: EditEventKind.sentence.code,
        payload: SentenceEdit(
          fromPosition: fromPosition,
          before: [
            for (final word in existing)
              WordSnapshot(
                id: word.id,
                text: word.word,
                startMs: word.startMs,
                endMs: word.endMs,
                speakerId: word.speakerId,
              ),
          ],
          after: const [],
        ).encode(),
      );
    });
  }

  /// Discards what a layer produced, keeping the layer itself.
  ///
  /// For re-running: the request stands, only its answer is being replaced.
  /// Soft, like every other delete here, so a future sync has the tombstones.
  Future<void> discardLayerTranscripts(String layerId) =>
      _db.softDeleteTranscriptsForLayer(layerId);

  /// Half-open overlap, matching [ProjectTimeline]'s convention: two layers
  /// meeting exactly at a boundary are adjacent, not overlapping.
  bool _overlaps(
    List<TranscribeLayer> layers, {
    required int startMs,
    required int endMs,
    required int trackIndex,
    String? ignoring,
  }) {
    for (final layer in layers) {
      if (layer.id == ignoring) continue;
      if (layer.trackIndex != trackIndex) continue;
      if (startMs < layer.endMs && layer.startMs < endMs) return true;
    }
    return false;
  }

  Stream<List<Word>> watchWords(String transcriptId) => _db.watchWords(transcriptId);

  Stream<List<TranslationLine>> watchTranslation(String transcriptId) =>
      _db.watchTranslationLines(transcriptId);

  /// Translates [transcriptId] into [to], sentence by sentence, and keeps the
  /// result beside the transcript -- replacing any translation it had. The
  /// transcript itself is not touched.
  ///
  /// The language packs must already be on the device (the sheet fetches
  /// them). Throws [TranslationException] when the transcript's language is
  /// not one [translator] knows, or the engine fails.
  ///
  /// With [words], only the sentences in those word positions are translated
  /// -- a selection -- and only the translation over them is replaced.
  Future<void> translateTranscript({
    required String transcriptId,
    required String to,
    required Translator translator,
    ({int from, int to})? words,
  }) async {
    final transcript = await _db.findTranscript(transcriptId);
    if (transcript == null) return;

    final from = transcript.language;
    if (!translator.languages.any((language) => language.code == from)) {
      throw const TranslationException(TranslationFailure.unsupportedSource);
    }

    final all = await _db.watchWords(transcriptId).first;
    // **One line per caption line**, the rows Script mode shows and the
    // captions the video shows -- cut exactly as they are (`captionCues`),
    // so each has its translation and none has two. A selection takes the
    // captions its words fall in, whole.
    final cues = [
      for (final cue in groupIntoCues(all))
        if (words == null ||
            (cue.words.last.position >= words.from &&
                cue.words.first.position <= words.to))
          cue,
    ];
    if (cues.isEmpty) return;
    final range = words == null
        ? null
        : (
            from: cues.first.words.first.position,
            to: cues.last.words.last.position,
          );
    final sentences = <TranslatableSentence>[
      for (final cue in cues)
        (
          text: cue.text,
          startMs: cue.startMs,
          endMs: cue.endMs,
          firstWord: cue.words.first.position,
          lastWord: cue.words.last.position,
        ),
    ];
    // Running text, not sentence by sentence: see `translation_sentences.dart`.
    final batches = translationBatches(sentences);
    final translated = await translator.translate(
      [
        for (final batch in batches)
          [for (final sentence in batch) sentence.text].join(' '),
      ],
      from: from,
      to: to,
    );
    final placed = [
      for (final (i, batch) in batches.indexed)
        ...alignTranslation(source: batch, translated: translated[i]),
    ];

    final trackId = await _translationTrack(transcript);
    final now = DateTime.now();
    await _db.replaceTranslation(words: range, transcriptId, [
      for (final (i, sentence) in placed.indexed)
        TranslationLinesCompanion.insert(
          id: newId(),
          createdAt: now,
          updatedAt: now,
          transcriptId: transcriptId,
          language: to,
          position: i,
          firstWord: sentence.firstWord,
          lastWord: sentence.lastWord,
          startMs: sentence.startMs,
          endMs: sentence.endMs,
          content: sentence.text,
          trackId: Value(trackId),
        ),
    ]);
  }

  /// Translates each of [transcriptIds] into [to], fetching any language
  /// pack missing at either end first. Returns why it stopped, or null when
  /// every transcript was translated.
  ///
  /// A transcript listed in [ranges] has only those word ranges translated --
  /// the sentences that were selected -- each on its own; the rest of its
  /// translation is left as it was.
  Future<TranslationFailure?> translateAll({
    required List<String> transcriptIds,
    required String to,
    required Translator translator,
    Map<String, List<({int from, int to})>> ranges = const {},
  }) async {
    try {
      if (!await translator.isDownloaded(to)) await translator.download(to);
      for (final id in transcriptIds) {
        final from = (await findTranscript(id))?.language;
        if (from != null &&
            translator.languages.any((language) => language.code == from) &&
            !await translator.isDownloaded(from)) {
          await translator.download(from);
        }
        final only = ranges[id];
        if (only == null) {
          await translateTranscript(
            transcriptId: id,
            to: to,
            translator: translator,
          );
        } else {
          for (final range in only) {
            await translateTranscript(
              transcriptId: id,
              to: to,
              translator: translator,
              words: range,
            );
          }
        }
      }
      return null;
    } on TranslationException catch (error) {
      return error.failure;
    }
  }

  /// Retires [transcriptId]'s translation, or just the part over [words].
  /// The transcript is untouched.
  Future<void> removeTranslation(
    String transcriptId, {
    ({int from, int to})? words,
  }) =>
      _db.removeTranslation(transcriptId, words: words);

  /// Every translation line in the project as a text over the picture, for
  /// the export -- the same rows [projectTranslationTexts] gives the stage,
  /// read straight from the database for the reason `_run` explains.
  Future<List<TextLayer>> translationTextsForProject({
    required String projectId,
    required ProjectTimeline timeline,
    required List<MediaClip> clips,
  }) async {
    final layers = await _db.layersForProject(projectId);
    return [
      for (final clip in clips)
        for (final transcript in await _db.transcriptsForClip(clip.id))
          ...translationTextsFor(
            timeline: timeline,
            projectId: projectId,
            clipId: clip.id,
            lines: await _db.translationLinesFor(transcript.id),
            layer: layers.where((l) => l.id == transcript.layerId).firstOrNull,
          ),
    ];
  }

  Stream<List<MediaClip>> watchClips(String projectId) =>
      _db.watchClips(projectId);

  Future<List<MediaClip>> clipsForProject(String projectId) =>
      _db.clipsForProject(projectId);

  Future<MediaClip?> findClip(String clipId) => _db.findClip(clipId);

  /// Stores a clip's amplitude readings for the timeline's audio lane.
  Future<void> storeClipWaveform(String clipId, Uint8List peaks) =>
      _db.fillMissingClipWaveform(clipId, peaks);

  /// Creates an empty project, with no media and nothing transcribed.
  ///
  /// The shape "Create project" produces: a named shell the user then adds
  /// clips to. Import still creates a project and its first clip together, so
  /// this is an alternative entry rather than a stage every project passes
  /// through.
  Future<String> createEmptyProject({required String title}) async {
    final projectId = newId();
    await _db.createEmptyProject(projectId: projectId, title: title);
    return projectId;
  }

  /// Copies [fileName]'s bytes in as a new clip at the end of the timeline.
  ///
  /// **No transcription happens here.** Adding media and transcribing it are
  /// separate events: a project can carry several clips and only some are worth
  /// the minutes whisper and diarization cost, so the engine runs only when the
  /// user asks for it on a specific clip.
  ///
  /// The duration probe is best-effort by design ([MediaConverter.probeDuration]
  /// returns null rather than throwing), so a container the prober dislikes
  /// still yields a usable clip.
  Future<MediaClip> addClip({
    required String projectId,
    required String fileName,
    required Stream<List<int>> bytes,
  }) async {
    final clipId = newId();
    final media = await _media.importToAppStorage(
      projectId: projectId,
      clipId: clipId,
      fileName: fileName,
      bytes: bytes,
    );
    return _registerClip(
      clipId: clipId,
      projectId: projectId,
      mediaPath: media.path,
      fileName: fileName,
    );
  }

  /// Adopts a file already on disk as a new clip. See
  /// [MediaConverter.adoptIntoAppStorage] for why this moves rather than copies.
  Future<MediaClip> adoptClip({
    required String projectId,
    required String fileName,
    required File source,
  }) async {
    final clipId = newId();
    final media = await _media.adoptIntoAppStorage(
      projectId: projectId,
      clipId: clipId,
      fileName: fileName,
      source: source,
    );
    return _registerClip(
      clipId: clipId,
      projectId: projectId,
      mediaPath: media.path,
      fileName: fileName,
    );
  }

  Future<MediaClip> _registerClip({
    required String clipId,
    required String projectId,
    required String mediaPath,
    required String fileName,
  }) async {
    final duration = await _media.probeDuration(mediaPath);
    await _db.appendClip(
      clipId: clipId,
      projectId: projectId,
      mediaPath: mediaPath,
      duration: duration,
      title: p.basenameWithoutExtension(fileName),
    );

    final clip = await _db.findClip(clipId);
    if (clip == null) {
      throw StateError('Clip $clipId vanished immediately after being written');
    }
    return clip;
  }

  /// Removes one clip and its media, leaving the rest of the project intact.
  ///
  /// Same ordering and the same guard as [deleteProject]: rows first so the
  /// clip disappears from the timeline even if the filesystem step fails, and
  /// the filesystem step is best-effort because by then the removal has already
  /// succeeded as far as the user is concerned.
  Future<void> removeClip(String clipId) async {
    final clip = await _db.findClip(clipId);
    if (clip == null) return;

    await _db.softDeleteClip(clipId);
    // Only once nothing else plays this file -- the position belongs to the
    // media now, and another clip or another project may still want it.
    await _db.softDeleteSetting(playbackPositionKey(clip.mediaPath));

    // A duplicated project points a clip of its own at the same file, so the
    // bytes only go when nothing else still needs them.
    final stillNeeded = await _db.projectsSharingMedia(
      clip.mediaPath,
      excluding: clip.projectId,
    );
    if (stillNeeded > 0) return;

    try {
      await _media.discardClipMedia(clipId: clipId, mediaPath: clip.mediaPath);
    } catch (error) {
      debugPrint('Removed clip $clipId but could not remove its media: $error');
    }
  }

  /// Writes a new clip order for one project. See [AppDatabase.reorderClips].
  /// Trims a clip to [window], which must already be a legal one.
  ///
  /// The window comes from `applyTrim`, which is pure and clamps against the
  /// media and the minimum length; re-deriving those limits here would be a
  /// second copy of the rule and the two would drift.
  Future<void> trimClip({
    required String clipId,
    required ClipWindow window,
  }) =>
      _db.trimClip(
        clipId: clipId,
        startMs: window.startMs,
        endMs: window.endMs,
      );

  /// Moves [clipId]'s sound against its picture -- a trim, or a J/L cut --
  /// as one undoable step. The offsets are already clamped (`applyAudioTrim`).
  Future<void> trimAudio({
    required String clipId,
    required AudioOffsets offsets,
  }) async {
    final clip = await _db.findClip(clipId);
    if (clip == null) return;
    final from = (
      startOffsetMs: clip.audioStartOffsetMs,
      endOffsetMs: clip.audioEndOffsetMs,
    );
    if (from == offsets) return;

    await _db.setAudioOffsets(
      clipId: clipId,
      startOffsetMs: offsets.startOffsetMs,
      endOffsetMs: offsets.endOffsetMs,
    );
    await recordTimelineEvent(
      projectId: clip.projectId,
      kind: TimelineEventKind.audioTrim,
      payload: audioTrimPayload(clipId: clipId, from: from, to: offsets),
    );
  }

  /// Removes the sound of [clipIds] from the timeline ([muted]) or puts it
  /// back, as one undoable step. The pictures stay.
  Future<void> setAudioMuted({
    required String projectId,
    required List<String> clipIds,
    required bool muted,
  }) async {
    if (clipIds.isEmpty) return;
    for (final id in clipIds) {
      await _db.setAudioMuted(id, muted);
    }
    await recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.audioMute,
      payload: audioMutePayload(clipIds: clipIds, muted: muted),
    );
  }

  /// Moves the cut between two clips, writing both sides together.
  ///
  /// Separate from [trimClip] because it is a different operation, not a
  /// convenience: trimming changes how long the project is, rolling never
  /// does. Written in one transaction so the pair cannot be caught with a gap
  /// or an overlap between them.
  Future<void> rollCut({
    required String leftClipId,
    required String rightClipId,
    required RolledCut cut,
  }) async {
    await _db.transaction(() async {
      await _db.trimClip(
        clipId: leftClipId,
        startMs: cut.left.startMs,
        endMs: cut.left.endMs,
      );
      await _db.trimClip(
        clipId: rightClipId,
        startMs: cut.right.startMs,
        endMs: cut.right.endMs,
      );
    });
  }

  /// Splits the clip at [atClipMs], measured from the start of what it plays.
  ///
  /// Returns the new clip's id, or null when the split was refused -- which
  /// happens when either side would fall below [minimumClipMs]. Refusing is
  /// better than making a sliver that cannot be played, and null lets the
  /// caller say so.
  Future<String?> splitClip({
    required String clipId,
    required int atClipMs,
  }) async {
    final clip = await _db.findClip(clipId);
    if (clip == null) return null;

    // The playhead knows where it is in what the clip plays; the rows have to
    // store where that falls in the file.
    final at = splitPointFor(clip, atClipMs);
    if (at == null) return null;

    // Captured before the split, because afterwards the clip no longer knows
    // how far it used to reach.
    final whole = clipWindow(clip);

    final newClipId =
        await _db.splitClip(clipId: clipId, atMediaMs: at, newId: newId);
    if (newClipId == null) return null;

    await recordTimelineEvent(
      projectId: clip.projectId,
      kind: TimelineEventKind.clipSplit,
      payload: splitPayload(
        leftClipId: clipId,
        rightClipId: newClipId,
        wholeStartMs: whole.startMs,
        wholeEndMs: whole.endMs,
        atMs: at,
      ),
    );

    return newClipId;
  }

  Future<void> reorderClips({
    required String projectId,
    required List<String> orderedIds,
  }) =>
      _db.reorderClips(projectId: projectId, orderedIds: orderedIds);

  /// Removes a project: its row, its per-project settings, and its media.
  ///
  /// **The row is soft-deleted and the media is not.** A tombstone row costs a
  /// few hundred bytes and is what a future sync will need to propagate the
  /// deletion; the media directory holds the imported video plus the extracted
  /// WAV, which is hundreds of megabytes that nothing else would ever reclaim.
  /// It lives in app-internal storage, so the user cannot clear it from the
  /// Files app either -- only by wiping the whole app's data.
  ///
  /// Database first, filesystem second. If the media deletion fails, the
  /// project is gone from the library and some bytes leak; the other order
  /// would leave a visible project whose video no longer opens.
  ///
  /// The filesystem step is guarded for the same reason the import rollback
  /// guards it: by the time it runs the deletion has already succeeded from the
  /// user's point of view, and turning a leaked file into a thrown error would
  /// report a failure that did not happen.
  Future<void> deleteProject(String id) async {
    final project = await _db.findProject(id);
    // Read before the soft delete, which retires them along with the project.
    final clips = await _db.clipsForProject(id);
    final images = await _db.imageLayersForProject(id);

    await _db.softDeleteProject(id);
    await _db.softDeleteSetting(editorModeKey(id));
    for (final clip in clips) {
      await _db.softDeleteSetting(playbackPositionKey(clip.mediaPath));
    }
    if (project == null) return;

    // Duplicates share their files, so the media only goes when nothing else
    // can still open it. Asked per clip and *after* the soft delete, excluding
    // this project, so the answer is exactly "does anyone else still need
    // this" -- and asked of the database rather than the filesystem, so the
    // decision needs no path lookup.
    //
    // Conservative on purpose: one shared file spares the whole directory.
    // Duplicates share every clip in practice, and leaking a file is a cost
    // the user can recover from while deleting another project's video is not.
    //
    // **Only files in this project's own directory decide it.** A duplicate's
    // clips live in the original's directory, which this never deletes; they
    // spared the duplicate's own directory anyway, and an image added to the
    // duplicate -- the only thing in it -- was left behind for good.
    bool ownFile(String path) => p.split(path).contains(id);
    for (final path in [
      for (final clip in clips) clip.mediaPath,
      for (final image in images) image.path,
    ]) {
      if (!ownFile(path)) continue;
      if (await _db.projectsSharingMedia(path, excluding: id) > 0) return;
    }

    try {
      await _media.discardProjectMedia(id);
    } catch (error) {
      debugPrint('Deleted project $id but could not remove its media: $error');
    }
  }

  /// Copies a project so a second edit can diverge from the same source.
  ///
  /// **The media is shared, not copied.** A phone cannot afford a second copy
  /// of a several-hundred-megabyte video, and re-transcribing would cost
  /// minutes of whisper and diarization to arrive at the same words. What is
  /// copied is the cheap part -- the transcript rows -- which is what lets each
  /// duplicate carry its own corrections.
  ///
  /// [title] comes from the caller because the "copy" wording is interface text
  /// (CLAUDE.md 4).
  Future<String> duplicateProject({
    required String projectId,
    required String title,
  }) {
    return _db.duplicateProject(
      sourceProjectId: projectId,
      newProjectId: newId(),
      title: title,
      newId: newId,
    );
  }

  /// Corrects one word's text, leaving its timing alone. See
  /// [AppDatabase.updateWordText] for why that separation matters.
  ///
  /// Records an undo event in the same transaction as the write, so the two
  /// cannot come apart.
  Future<void> updateWordText(String wordId, String text) async {
    final trimmed = text.trim();

    await _db.transaction(() async {
      final word = await _db.findWord(wordId);
      // Nothing to record when the word is gone or the text is unchanged. The
      // UI guards the second case too, but an event whose before and after
      // match would spend a slot in the history undoing nothing visible.
      if (word == null || word.word == trimmed) return;

      await _db.updateWordText(wordId, trimmed);
      await _db.appendEditEvent(
        transcriptId: word.transcriptId,
        kind: EditEventKind.wordText.code,
        payload: WordTextEdit(
          wordId: wordId,
          before: word.word,
          after: trimmed,
        ).encode(),
      );
    });
  }

  /// Moves a whole turn onto [speaker], correcting a diarization mistake.
  ///
  /// Diarization is right most of the time and never right always: the models
  /// resolve some regions confidently and others not at all, and the person
  /// listening is the only real authority. This is how they say so.
  Future<void> reassignSpeaker({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required int speaker,
  }) async {
    final speakerId = speakerIdFor(speaker);

    await _db.transaction(() async {
      final affected = await _db.wordsInPositionRange(
        transcriptId: transcriptId,
        from: fromPosition,
        to: toPosition,
      );
      if (affected.isEmpty) return;

      // Captured per position rather than as one value. A turn is uniform
      // today, but an undiarized run carries nulls, and undo has to put back
      // exactly what was there.
      final before = {
        for (final word in affected) word.position: word.speakerId,
      };
      if (before.values.every((id) => id == speakerId)) return;

      await _db.reassignSpeaker(
        transcriptId: transcriptId,
        fromPosition: fromPosition,
        toPosition: toPosition,
        speakerId: speakerId,
      );
      await _db.appendEditEvent(
        transcriptId: transcriptId,
        kind: EditEventKind.speaker.code,
        payload: SpeakerEdit(
          fromPosition: fromPosition,
          toPosition: toPosition,
          after: speakerId,
          before: before,
        ).encode(),
      );
    });
  }

  /// Applies a retyped sentence to the words at [fromPosition]..[toPosition].
  ///
  /// The correction the user actually makes is rarely one word for one word:
  /// "brainbeats" heard for "praying beads" is a single mishearing that spans a
  /// word boundary, and there is no way to express it one word at a time. So
  /// the unit of editing is the sentence, and the word count is allowed to
  /// change.
  ///
  /// [planSentenceEdit] decides the timings — the sentence keeps its own span,
  /// untouched words keep their exact timestamps, and a changed run divides the
  /// span it replaces. See that function for why none of that may move.
  ///
  /// Returns false when nothing changed, so the caller can tell a real edit
  /// from a dialog dismissed with the text as it was.
  Future<bool> replaceSentence({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required String text,
  }) async {
    var applied = false;

    await _db.transaction(() async {
      final existing = await _db.wordsInPositionRange(
        transcriptId: transcriptId,
        from: fromPosition,
        to: toPosition,
      );
      if (existing.isEmpty) return;

      final plan = planSentenceEdit(
        original: [
          for (final word in existing)
            (
              id: word.id,
              text: word.word,
              startMs: word.startMs,
              endMs: word.endMs,
            ),
        ],
        text: text,
      );
      if (plan == null || !plan.changed) return;

      // Every word in the run already shares a speaker -- the editable unit is
      // a sentence *within a turn*, and a turn is by definition one voice. New
      // words therefore inherit it with no ambiguity about whose they are.
      final speakerId = existing.first.speakerId;

      // Ids for the new words are minted **here**, not left to `spliceWords`.
      // The event has to record the id a word was actually given, or a redo
      // would insert a second row for the same word and strand the first as a
      // soft-deleted orphan.
      final after = [
        for (final word in plan.words)
          (
            id: word.id ?? newId(),
            text: word.text,
            startMs: word.startMs,
            endMs: word.endMs,
            speakerId: speakerId,
          ),
      ];

      await _db.spliceWords(
        transcriptId: transcriptId,
        fromPosition: fromPosition,
        toPosition: toPosition,
        replacements: after,
      );

      await _db.appendEditEvent(
        transcriptId: transcriptId,
        kind: EditEventKind.sentence.code,
        payload: SentenceEdit(
          fromPosition: fromPosition,
          before: [
            for (final word in existing)
              WordSnapshot(
                id: word.id,
                text: word.word,
                startMs: word.startMs,
                endMs: word.endMs,
                speakerId: word.speakerId,
              ),
          ],
          after: [
            for (final word in after)
              WordSnapshot(
                id: word.id,
                text: word.text,
                startMs: word.startMs,
                endMs: word.endMs,
                speakerId: word.speakerId,
              ),
          ],
        ).encode(),
      );

      applied = true;
    });

    return applied;
  }

  /// Gives [speaker] a custom name, or clears it when [name] is blank.
  ///
  /// **Deliberately not in the undo log.** The log is keyed on word rows and
  /// replays edits to them; a name lives on the transcript and is its own undo
  /// — retype it. An event kind for this would be machinery for nothing, and it
  /// would put a rename in the same history as a text correction, where undoing
  /// a typo would first have to step back through a renaming.
  Future<void> renameSpeaker({
    required String transcriptId,
    required int speaker,
    required String? name,
  }) async {
    await _db.transaction(() async {
      final transcript = await _db.findTranscript(transcriptId);
      if (transcript == null) return;

      final names = SpeakerNames.decode(transcript.speakerNames)
          .withName(speaker, name);

      await _db.writeSpeakerNames(transcriptId, names.encode());
    });
  }

  /// Whether undo and redo have anything to do on [transcriptId].
  Stream<({bool canUndo, bool canRedo})> watchEditHistory(String transcriptId) =>
      _db.watchEditHistory(transcriptId);

  /// Reverses the most recent edit that is still in effect.
  Future<void> undo(String transcriptId) =>
      _step(transcriptId, forward: false);

  /// Everything that has happened to this project, oldest first.
  ///
  /// **Both logs, ordered by when things happened.** Which table an event
  /// lives in is storage, not history: a word edit and a split are the same
  /// kind of fact to someone pressing undo.
  Future<({List<HistoryStep> steps, Set<String> undone})> projectHistory(
    String projectId,
  ) async {
    final edits = await _db.editEventsForProject(projectId);
    final timeline = await _db.timelineEventsFor(projectId);

    return (
      steps: mergeHistory(
        transcript: edits.map(stepOfEdit).toList(),
        timeline: timeline.map(stepOf).toList(),
      ),
      undone: {
        for (final event in edits)
          if (event.undoneAt != null) event.id,
        for (final event in timeline)
          if (event.undoneAt != null) event.id,
      },
    );
  }

  /// Undoes the last thing that happened, whichever log it came from.
  Future<void> undoProject(String projectId) =>
      _stepProject(projectId, forward: false);

  /// Redoes the oldest thing that was undone.
  Future<void> redoProject(String projectId) =>
      _stepProject(projectId, forward: true);

  Future<void> _stepProject(String projectId, {required bool forward}) async {
    final history = await projectHistory(projectId);
    final step = forward
        ? nextRedo(history.steps, history.undone)
        : nextUndo(history.steps, history.undone);
    if (step == null) return;

    switch (step.log) {
      // Delegated rather than reimplemented: word edits already know how to
      // walk themselves, and duplicating that here is how the two would drift.
      case HistoryLog.transcript:
        final event = await _db.findEditEvent(step.id);
        if (event != null) {
          await _step(event.transcriptId, forward: forward);
        }

      case HistoryLog.timeline:
        await _stepTimeline(step.id, forward: forward);
    }
  }

  /// Applies one timeline event in the given direction.
  ///
  /// Wrapped in a transaction for the same reason [_step] is: applying the
  /// change and marking the event cannot come apart, or the log would claim a
  /// state the project is not in and every later undo would be wrong.
  Future<void> _stepTimeline(String eventId, {required bool forward}) async {
    await _db.transaction(() async {
      final event = await _db.findTimelineEvent(eventId);
      if (event == null) return;

      final kind = TimelineEventKind.fromCode(event.kind);
      final payload = TimelineEventPayload.decode(event.payload);
      final inverse = kind == null ? null : timelineInverses[kind];

      if (payload == null || inverse == null) {
        // Written by a newer build, or corrupt. Dropped rather than letting
        // one unreadable row wedge the button for good.
        await _db.discardTimelineEvent(event.id);
        return;
      }

      await inverse(_db, payload.side(forward: forward));
      await _db.setTimelineEventUndone(event.id, undone: !forward);
    });
  }

  /// Records something that happened, so it can be taken back.
  ///
  /// Called by the actions themselves rather than wrapped around them: only
  /// the action knows what the state was before it ran.
  Future<void> recordTimelineEvent({
    required String projectId,
    required TimelineEventKind kind,
    required TimelineEventPayload payload,
  }) =>
      _db.appendTimelineEvent(
        projectId: projectId,
        kind: kind.code,
        payload: payload.encode(),
      );

  /// Re-applies the oldest edit that has been undone.
  Future<void> redo(String transcriptId) => _step(transcriptId, forward: true);

  /// One move along the history, in either direction.
  ///
  /// Wrapped in a transaction so applying the change and marking the event
  /// cannot come apart -- a crash between them would leave the log claiming a
  /// state the transcript is not in, and every later undo would be wrong.
  Future<void> _step(String transcriptId, {required bool forward}) async {
    await _db.transaction(() async {
      final event = forward
          ? await _db.nextRedoEvent(transcriptId)
          : await _db.nextUndoEvent(transcriptId);
      if (event == null) return;

      final payload = EditEventPayload.decode(event.kind, event.payload);
      if (payload == null) {
        // Written by a newer build, or corrupt. Drop it rather than letting one
        // unreadable row wedge the button for good.
        await _db.discardEditEvent(event.id);
        return;
      }

      switch (payload) {
        case WordTextEdit(:final wordId, :final before, :final after):
          await _db.updateWordText(wordId, forward ? after : before);
        case SpeakerEdit(
            :final fromPosition,
            :final toPosition,
            :final after,
            :final before
          ):
          if (forward) {
            await _db.reassignSpeaker(
              transcriptId: transcriptId,
              fromPosition: fromPosition,
              toPosition: toPosition,
              speakerId: after,
            );
          } else {
            await _db.restoreSpeakerIds(
              transcriptId: transcriptId,
              speakerIds: before,
            );
          }
        case SentenceEdit(:final fromPosition, :final before, :final after):
          // The run in place right now is whichever side was last applied, so
          // each direction computes its own end rather than trusting a stored
          // one -- the sentence gets longer or shorter as this is applied and
          // reversed.
          final current = forward ? before : after;
          final target = forward ? after : before;

          await _db.spliceWords(
            transcriptId: transcriptId,
            fromPosition: fromPosition,
            toPosition: fromPosition + current.length - 1,
            replacements: [
              for (final word in target)
                (
                  id: word.id,
                  text: word.text,
                  startMs: word.startMs,
                  endMs: word.endMs,
                  speakerId: word.speakerId,
                ),
            ],
          );
      }

      // Note the database methods above, not the logging ones on this class:
      // replaying history must not append to it.
      await _db.markEditEventUndone(event.id, undone: !forward);
    });
  }

  /// Persists a finished import: the project row, its transcript, and one
  /// [Word] row per engine segment.
  ///
  /// Written in a single transaction so a failure part-way through cannot
  /// leave a project with a half-populated transcript.
  ///
  /// [language] is what the engine was *asked* for. What gets stored is what it
  /// actually used: `result.detectedLanguage` when the fork reports one, and the
  /// request otherwise.
  ///
  /// The two differ precisely when the request was [TranscriptionLanguage.auto],
  /// which is the case worth recording — storing the literal string `auto`
  /// tells nobody what the transcript is in, so an export cannot label it. A
  /// pinned request gets its own code back, so the value is right either way.
  ///
  /// The fallback exists for platforms whose native entrypoint is unpatched —
  /// iOS today — where the field is absent and the request is the best
  /// available answer.
  /// [speakerSpans] comes from diarization and may be empty — the setting is
  /// off, the file was too long, or no speech was found. Empty simply leaves
  /// every `speakerId` null, which is the same state every transcript was in
  /// before diarization existed.
  Future<void> saveImport({
    required String projectId,
    required String clipId,
    required String title,
    required String mediaPath,
    required Duration? duration,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
  }) async {
    final now = DateTime.now();

    await _db.transaction(() async {
      await _db.into(_db.projects).insert(
            ProjectsCompanion.insert(
              id: projectId,
              createdAt: now,
              updatedAt: now,
              title: title,
              // Vestigial since schema 5 -- the clip below carries the media.
              mediaPath: '',
            ),
          );

      await _db.into(_db.mediaClips).insert(
            MediaClipsCompanion.insert(
              id: clipId,
              createdAt: now,
              updatedAt: now,
              projectId: projectId,
              position: 0,
              mediaPath: mediaPath,
              durationMs: Value(duration?.inMilliseconds),
              title: title,
            ),
          );

      // Import transcribes the whole clip, so it gets a layer spanning it --
      // the same shape the schema-6 migration gave every older transcript, so
      // an imported project and an upgraded one are indistinguishable.
      final layerId = newId();
      await _db.into(_db.transcribeLayers).insert(
            TranscribeLayersCompanion.insert(
              id: layerId,
              createdAt: now,
              updatedAt: now,
              projectId: projectId,
              startMs: 0,
              endMs: duration?.inMilliseconds ?? 0,
            ),
          );

      await _writeTranscript(
        projectId: projectId,
        clipId: clipId,
        language: language,
        speakerSpans: speakerSpans,
        result: result,
        now: now,
        layerId: layerId,
        rangeEndMs: duration?.inMilliseconds,
      );
    });
  }

  /// Saves a transcript for a clip that already exists.
  ///
  /// The on-demand half of the split: [saveImport] creates a project, its first
  /// clip and its transcript together, while this attaches words to a clip the
  /// user added earlier and has now asked to transcribe.
  ///
  /// Replacing an existing transcript is not handled here — the caller checks
  /// first, because re-transcribing would discard corrections the user has
  /// already made and that is a decision to surface, not to take silently.
  /// Returns the id of the transcript written, so the caller can record what
  /// its run produced and take exactly that back later.
  Future<String> saveClipTranscript({
    required String projectId,
    required String clipId,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
    String? layerId,
    int offsetMs = 0,
    int? rangeStartMs,
    int? rangeEndMs,
  }) async {
    final now = DateTime.now();
    return _db.transaction(() async {
      return _writeTranscript(
        projectId: projectId,
        clipId: clipId,
        language: language,
        speakerSpans: speakerSpans,
        result: result,
        now: now,
        layerId: layerId,
        offsetMs: offsetMs,
        rangeStartMs: rangeStartMs,
        rangeEndMs: rangeEndMs,
      );
    });
  }

  /// Writes one transcript and its words. **Caller supplies the transaction.**
  ///
  /// [offsetMs] is where in the clip the audio the engine saw began. Whisper
  /// reports times relative to whatever WAV it was handed, so a range starting
  /// ten seconds into a clip comes back starting at zero — **this is the one
  /// place that offset is applied.** Putting it anywhere else as well is how a
  /// double-offset bug appears only for ranges that do not start at zero.
  Future<String> _writeTranscript({
    required String projectId,
    required String clipId,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
    required DateTime now,
    String? layerId,
    int offsetMs = 0,
    int? rangeStartMs,
    int? rangeEndMs,
  }) async {
    final transcriptId = newId();

    {
      await _db.into(_db.transcripts).insert(
            TranscriptsCompanion.insert(
              id: transcriptId,
              createdAt: now,
              updatedAt: now,
              projectId: projectId,
              clipId: Value(clipId),
              layerId: Value(layerId),
              // **Not always [offsetMs].** They are the same whenever one
              // run produced one transcript, but a run spanning several
              // contiguous clips shifts every word by the *run's* start while
              // each clip records only its own share of it.
              clipStartMs: Value(rangeStartMs ?? offsetMs),
              clipEndMs: Value(rangeEndMs),
              language: Value(result.detectedLanguage ?? language.code),
              fullText: result.text.trim(),
            ),
          );

      // With `splitOnWord: true` the engine returns one word per segment as a
      // flat list, rather than a nested words array.
      //
      // Whitespace-only segments are dropped rather than stored. whisper.cpp
      // emits them for pauses and around hallucinated output, and an empty
      // word is not a word: it would inflate the displayed word count, render
      // as an invisible but tappable gap in the transcript, and later emit a
      // blank SRT cue. Position is assigned after filtering so it stays a
      // contiguous 0..n-1 run.
      final segments = (result.segments ?? const <WhisperTranscribeSegment>[])
          .map((segment) => (segment: segment, text: segment.text.trim()))
          .where((entry) => entry.text.isNotEmpty)
          .toList();

      // Assigned in one pass over the whole transcript rather than per row,
      // because turn-boundary smoothing needs neighbouring words as context.
      final speakers = assignSpeakers(wordTimingsOf(result), speakerSpans);

      await _db.batch((batch) {
        batch.insertAll(
          _db.words,
          [
            for (final (index, entry) in segments.indexed)
              WordsCompanion.insert(
                id: newId(),
                createdAt: now,
                updatedAt: now,
                transcriptId: transcriptId,
                position: index,
                // The engine pads each token with a leading space; that is a
                // rendering detail, and keeping it would break word matching
                // for the editor and export phases.
                word: entry.text,
                // Shifted back into clip time. Speaker assignment above ran in
                // the engine's own space, where the spans already agree with
                // these times, so it needs no offsetting of its own.
                startMs: entry.segment.fromTs.inMilliseconds + offsetMs,
                endMs: entry.segment.toTs.inMilliseconds + offsetMs,
                // Diarization's boundaries are independent of whisper's; see
                // speaker_assignment.dart for how disagreements are settled.
                speakerId: Value(
                  switch (speakers[index]) {
                    final int speaker => speakerIdFor(speaker),
                    null => null,
                  },
                ),
              ),
          ],
        );
      });
    }

    return transcriptId;
  }
}

@Riverpod(keepAlive: true)
TranscriptRepository transcriptRepository(Ref ref) => TranscriptRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(mediaConverterProvider),
    );

/// Custom speaker labels for [transcriptId], empty when nobody has renamed one.
///
/// Keyed by transcript id rather than project so the caption overlay and the
/// transcript view read the same instance. Synchronous, with an empty map while
/// the row loads — the fallback `Speaker N` label is correct in that moment
/// anyway, so there is nothing to wait for and no spinner to show.
@riverpod
SpeakerNames speakerNames(Ref ref, String transcriptId) {
  final transcript = ref.watch(transcriptByIdProvider(transcriptId)).value;
  return SpeakerNames.decode(transcript?.speakerNames);
}

@riverpod
Stream<Transcript?> transcriptById(Ref ref, String transcriptId) =>
    ref.watch(appDatabaseProvider).watchTranscript(transcriptId);

/// Whether the undo and redo controls are live for [transcriptId].
/// Whether the project has anything to undo or redo.
///
/// **One history behind one pair of buttons.** Both modes read this, because
/// splitting a clip and correcting a word are the same kind of fact to someone
/// pressing undo -- which table they were stored in is not something the
/// control should have an opinion about.
@riverpod
Stream<({bool canUndo, bool canRedo})> projectHistoryState(
  Ref ref,
  String projectId,
) =>
    ref.watch(appDatabaseProvider).watchProjectHistory(projectId);

@riverpod
Stream<({bool canUndo, bool canRedo})> editHistory(
  Ref ref,
  String transcriptId,
) =>
    ref.watch(transcriptRepositoryProvider).watchEditHistory(transcriptId);

/// Total bytes [projectId] occupies on disk: its imported media plus the
/// extracted WAV.
///
/// Surfaced in the library so consumed space is visible and attributable to a
/// project, rather than showing up only as an unexplained rise in the app's
/// size in Android settings.
@riverpod
Future<int> projectMediaBytes(Ref ref, String projectId) =>
    ref.watch(mediaConverterProvider).projectMediaBytes(projectId);

@riverpod
Stream<List<Project>> projectList(Ref ref) =>
    ref.watch(transcriptRepositoryProvider).watchProjects();

/// The library's search results for [query]: projects by title or by what
/// their transcripts say. See `AppDatabase.searchLibrary`.
@riverpod
Stream<List<LibraryHit>> librarySearch(Ref ref, String query) =>
    ref.watch(transcriptRepositoryProvider).watchLibrarySearch(query);

@riverpod
Future<Project?> projectById(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).findProject(projectId);

@riverpod
Stream<List<Word>> transcriptWords(Ref ref, String transcriptId) =>
    ref.watch(transcriptRepositoryProvider).watchWords(transcriptId);

/// Every transcript covering one clip, earliest range first. Empty when
/// nothing on the clip has been transcribed yet.
///
/// Speaker names live on these rows, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.
@riverpod
Stream<List<Transcript>> clipTranscripts(Ref ref, String clipId) =>
    ref.watch(transcriptRepositoryProvider).watchTranscriptsForClip(clipId);

/// The whole project's script: every word, in timeline order.
///
/// **A transcript belongs to a clip, but a script belongs to the project.**
/// Storage is per clip because word timings are relative to a clip's media and
/// there is no single continuous recording to store them against. That is an
/// implementation detail, and it had been leaking: splitting a clip cut the
/// script in half on screen, and Script mode showed only whichever half the
/// playhead happened to be over.
///
/// [clipOfTranscript] is what lets a word be played. Each word knows which
/// transcript it belongs to; this says which clip that transcript is on, so a
/// tap can be turned into a seek without the view having to care that the
/// script it is showing came from several rows.
typedef ProjectScript = ({
  List<Word> words,
  Map<String, String> clipOfTranscript,
});

@riverpod
ProjectScript projectScript(Ref ref, String projectId) {
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];

  final words = <Word>[];
  final clipOfTranscript = <String, String>{};

  // Clip order is timeline order, and a clip's transcripts come back earliest
  // range first, so reading them in this order is already the order a person
  // would read the script in.
  for (final clip in clips) {
    final transcripts =
        ref.watch(clipTranscriptsProvider(clip.id)).value ?? const [];

    for (final transcript in transcripts) {
      clipOfTranscript[transcript.id] = clip.id;
      words.addAll(
        ref.watch(transcriptWordsProvider(transcript.id)).value ?? const [],
      );
    }
  }

  return (words: words, clipOfTranscript: clipOfTranscript);
}

/// A project's transcribe layers, in timeline order.
@riverpod
Stream<List<TranscribeLayer>> projectLayers(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).watchLayers(projectId);

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.
/// A transcript's translation, one line per sentence; empty when it has none.
@riverpod
Stream<List<TranslationLine>> transcriptTranslation(
  Ref ref,
  String transcriptId,
) =>
    ref.watch(transcriptRepositoryProvider).watchTranslation(transcriptId);

/// Every translation line in a project as a text over the picture, for the
/// stage. See `translation_texts.dart`.
@riverpod
List<TextLayer> projectTranslationTexts(Ref ref, String projectId) {
  final timeline = ref.watch(projectTimelineProvider(projectId));
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
  final layers = ref.watch(projectLayersProvider(projectId)).value ?? const [];

  return [
    for (final clip in clips)
      for (final transcript
          in ref.watch(clipTranscriptsProvider(clip.id)).value ?? const [])
        ...translationTextsFor(
          timeline: timeline,
          projectId: projectId,
          clipId: clip.id,
          lines: ref.watch(transcriptTranslationProvider(transcript.id)).value ??
              const [],
          layer: layers.where((l) => l.id == transcript.layerId).firstOrNull,
        ),
  ];
}

/// A project's tracks, top to bottom -- placing anything not yet on one the
/// first time the project is watched.
@riverpod
Stream<List<Track>> projectTracks(Ref ref, String projectId) async* {
  final repository = ref.watch(transcriptRepositoryProvider);
  await repository.ensureTracks(projectId);
  yield* repository.watchTracks(projectId);
}

/// A project's images in timeline order.
@riverpod
Stream<List<ImageLayer>> projectImageLayers(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).watchImageLayers(projectId);

/// A translation line placed on the project's time axis.
typedef ProjectTranslationLine = ({
  TranslationLine line,
  String clipId,
  String? layerId,
  int projectStartMs,
  int projectEndMs,
});

/// Every translation line in a project, in project time, in order.
@riverpod
List<ProjectTranslationLine> projectTranslationLines(
  Ref ref,
  String projectId,
) {
  final timeline = ref.watch(projectTimelineProvider(projectId));
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
  final lines = <ProjectTranslationLine>[];
  for (final clip in clips) {
    for (final transcript
        in ref.watch(clipTranscriptsProvider(clip.id)).value ?? const []) {
      for (final line
          in ref.watch(transcriptTranslationProvider(transcript.id)).value ??
              const <TranslationLine>[]) {
        final start =
            timeline.projectMsOf(clipId: clip.id, clipMs: line.startMs);
        final end = timeline.projectMsOf(clipId: clip.id, clipMs: line.endMs);
        if (start == null || end == null || end <= start) continue;
        lines.add((
          line: line,
          clipId: clip.id,
          layerId: transcript.layerId,
          projectStartMs: start,
          projectEndMs: end,
        ));
      }
    }
  }
  lines.sort((a, b) => a.projectStartMs - b.projectStartMs);
  return lines;
}

/// A project's text layers in timeline order.
@riverpod
Stream<List<TextLayer>> projectTextLayers(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).watchTextLayers(projectId);

@riverpod
Stream<List<MediaClip>> projectClips(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).watchClips(projectId);

/// Where each of a project's clips falls on one shared time axis.
///
/// The single copy of the running sum. The ruler, the track, the playhead and
/// anything turning a drawn range back into per-clip work all measure with
/// this — an earlier pass had the ruler and the track folding their own totals
/// and they drifted apart, which is the bug this exists to make impossible.
@riverpod
ProjectTimeline projectTimeline(Ref ref, String projectId) {
  final clips = ref.watch(projectClipsProvider(projectId)).value;
  if (clips == null) return ProjectTimeline.empty;
  return ProjectTimeline.fromClips(clips);
}

/// The amplitude readings behind a clip's audio lane, computed on first need.
///
/// **Not computed at import.** Deriving these costs a full native decode of
/// the media, and "+" is specified to copy a file in and do nothing else — so
/// the lane fills in once the timeline asks for it, and a clip added a moment
/// ago legitimately draws flat until it does.
///
/// Returns an empty list while computing and for media that has no decodable
/// audio; both cases draw as a flat lane. The result is stored on the clip, so
/// this decodes once per clip ever rather than once per visit.
@riverpod
Future<Uint8List> clipWaveform(Ref ref, String clipId) async {
  final repository = ref.watch(transcriptRepositoryProvider);
  final clip = await repository.findClip(clipId);
  if (clip == null) return Uint8List(0);

  final stored = clip.waveform;
  if (stored != null && stored.isNotEmpty) return stored;

  final peaks = await ref.watch(waveformServiceProvider).peaksFor(clip.mediaPath);
  if (peaks.isNotEmpty) {
    await repository.storeClipWaveform(clipId, peaks);
  }
  return peaks;
}

/// Every transcribed sentence in a project, in timeline order.
///
/// A thin assembly over [sentencesForClip]: this walks the project's clips and
/// their transcripts, and that does the placing. The arithmetic lives there so
/// it can be tested without a database.
@riverpod
List<TimelineSentence> projectSentences(Ref ref, String projectId) {
  final timeline = ref.watch(projectTimelineProvider(projectId));
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];

  final sentences = <TimelineSentence>[];
  for (final clip in clips) {
    final transcripts =
        ref.watch(clipTranscriptsProvider(clip.id)).value ?? const [];

    for (final transcript in transcripts) {
      final words =
          ref.watch(transcriptWordsProvider(transcript.id)).value ?? const [];

      sentences.addAll(sentencesForClip(
        timeline: timeline,
        clipId: clip.id,
        transcriptId: transcript.id,
        layerId: transcript.layerId,
        words: [
          for (final word in words)
            (
              text: word.word,
              startMs: word.startMs,
              endMs: word.endMs,
              speakerId: word.speakerId,
              position: word.position,
              trackId: word.captionTrackId,
            ),
        ],
      ));
    }
  }

  sentences.sort((a, b) => a.projectStartMs - b.projectStartMs);
  return sentences;
}

/// A project's running time, for the library row.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.
@riverpod
Duration projectDuration(Ref ref, String projectId) => Duration(
      milliseconds: ref.watch(projectTimelineProvider(projectId)).totalMs,
    );

/// The engine's segments as word timings, filtered exactly as [saveImport]
/// filters them before writing rows.
///
/// Shared so that anything reasoning about words before the save — speaker
/// refinement, in particular — sees the same list, in the same order, that the
/// stored rows are built from. If the two ever diverged, a refinement decision
/// would be recorded against the wrong word range and would land on the wrong
/// sentence.
///
/// With `splitOnWord: true` the engine returns one word per segment as a flat
/// list. Whitespace-only segments are dropped rather than stored: whisper.cpp
/// emits them for pauses and around hallucinated output, and an empty word is
/// not a word.
List<WordTiming> wordTimingsOf(WhisperTranscribeResponse result) {
  return [
    for (final segment in result.segments ?? const <WhisperTranscribeSegment>[])
      if (segment.text.trim().isNotEmpty)
        (
          text: segment.text.trim(),
          startMs: segment.fromTs.inMilliseconds,
          endMs: segment.toTs.inMilliseconds,
        ),
  ];
}
