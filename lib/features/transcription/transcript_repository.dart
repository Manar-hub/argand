import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/audio/waveform_service.dart';
import '../../core/database/database.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/media/media_converter.dart';
import '../../core/transcript/edit_event.dart';
import '../../core/transcript/sentence_edit.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/layer_drag.dart';
import '../../core/timeline/timeline_event.dart';
import 'timeline_history.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/timeline/timeline_sentences.dart';
import '../../core/transcript/speaker_names.dart';
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
    // Conservative on purpose: one shared clip spares the whole directory.
    // Duplicates share every clip in practice, and leaking a file is a cost
    // the user can recover from while deleting another project's video is not.
    for (final clip in clips) {
      final stillNeeded = await _db.projectsSharingMedia(
        clip.mediaPath,
        excluding: id,
      );
      if (stillNeeded > 0) return;
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
        words: [
          for (final word in words)
            (
              text: word.word,
              startMs: word.startMs,
              endMs: word.endMs,
              speakerId: word.speakerId,
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
