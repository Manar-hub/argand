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
String playbackPositionKey(String mediaPath) => 'media.\$mediaPath.positionMs';

/// All persistence for projects and their transcripts.
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

  /// Sets one caption line's translation to [content], as one undoable step --
  /// Script mode's edit, independent of the transcript's own words.
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
    // One line per caption line, the rows Script mode shows and the captions
    // the video shows -- cut exactly as they are (`captionCues`), so each has
    // its translation and none has two.
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

  /// Translates each of [transcriptIds] into [to], fetching any language pack
  /// missing at either end first. Returns why it stopped, or null when every
  /// transcript was translated.
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
  Future<String> createEmptyProject({required String title}) async {
    final projectId = newId();
    await _db.createEmptyProject(projectId: projectId, title: title);
    return projectId;
  }

  /// Copies [fileName]'s bytes in as a new clip at the end of the timeline.
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

  /// Takes a clip off the timeline, as one undoable step.
  Future<void> removeClip(String clipId) async {
    final clip = await _db.findClip(clipId);
    if (clip == null || clip.deletedAt != null) return;

    await _db.setClipRetired(clipId: clipId, retired: true);
    await recordTimelineEvent(
      projectId: clip.projectId,
      kind: TimelineEventKind.clipRemove,
      payload: TimelineEventPayload(
        before: {'clipId': clipId, 'retired': false},
        after: {'clipId': clipId, 'retired': true},
      ),
    );
  }

  /// Writes a new clip order for one project. See [AppDatabase.reorderClips].
  /// Trims a clip to [window], which must already be a legal one.
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
    // can still open it.
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

      // Ids for the new words are minted here, not left to `spliceWords`.
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
          // one.
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

  /// Writes one transcript and its words. Caller supplies the transaction.
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
              // Not always [offsetMs].
              clipStartMs: Value(rangeStartMs ?? offsetMs),
              clipEndMs: Value(rangeEndMs),
              language: Value(result.detectedLanguage ?? language.code),
              fullText: result.text.trim(),
            ),
          );

      // With `splitOnWord: true` the engine returns one word per segment as a
      // flat list, rather than a nested words array.
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
@riverpod
SpeakerNames speakerNames(Ref ref, String transcriptId) {
  final transcript = ref.watch(transcriptByIdProvider(transcriptId)).value;
  return SpeakerNames.decode(transcript?.speakerNames);
}

@riverpod
Stream<Transcript?> transcriptById(Ref ref, String transcriptId) =>
    ref.watch(appDatabaseProvider).watchTranscript(transcriptId);

/// Whether the undo and redo controls are live for [transcriptId]. Whether the
/// project has anything to undo or redo.
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

/// Every transcript covering one clip, earliest range first. Empty when nothing
/// on the clip has been transcribed yet.
@riverpod
Stream<List<Transcript>> clipTranscripts(Ref ref, String clipId) =>
    ref.watch(transcriptRepositoryProvider).watchTranscriptsForClip(clipId);

/// The whole project's script: every word, in timeline order.
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
@riverpod
ProjectTimeline projectTimeline(Ref ref, String projectId) {
  final clips = ref.watch(projectClipsProvider(projectId)).value;
  if (clips == null) return ProjectTimeline.empty;
  return ProjectTimeline.fromClips(clips);
}

/// The amplitude readings behind a clip's audio lane, computed on first need.
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
@riverpod
Duration projectDuration(Ref ref, String projectId) => Duration(
      milliseconds: ref.watch(projectTimelineProvider(projectId)).totalMs,
    );

/// The engine's segments as word timings, filtered exactly as [saveImport]
/// filters them before writing rows.
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
