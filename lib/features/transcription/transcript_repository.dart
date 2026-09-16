import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/database/database.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/media/media_converter.dart';
import '../../core/transcript/edit_event.dart';
import '../../core/transcript/sentence_edit.dart';
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
/// **Keyed by clip since schema 5**, having been keyed by project before that.
/// A project now holds several clips and the preview plays whichever one is
/// selected, so a single per-project position would drop the user somewhere
/// arbitrary in whatever clip they opened next.
String playbackPositionKey(String clipId) => 'clip.$clipId.positionMs';

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

  Future<Transcript?> findTranscriptForClip(String clipId) =>
      _db.findTranscriptForClip(clipId);

  Stream<Transcript?> watchTranscriptForClip(String clipId) =>
      _db.watchTranscriptForClip(clipId);

  Stream<List<Word>> watchWords(String transcriptId) => _db.watchWords(transcriptId);

  Stream<List<MediaClip>> watchClips(String projectId) =>
      _db.watchClips(projectId);

  Future<List<MediaClip>> clipsForProject(String projectId) =>
      _db.clipsForProject(projectId);

  Future<MediaClip?> findClip(String clipId) => _db.findClip(clipId);

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
    await _db.softDeleteSetting(playbackPositionKey(clipId));

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
      await _db.softDeleteSetting(playbackPositionKey(clip.id));
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

      await _writeTranscript(
        projectId: projectId,
        clipId: clipId,
        language: language,
        speakerSpans: speakerSpans,
        result: result,
        now: now,
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
  Future<void> saveClipTranscript({
    required String projectId,
    required String clipId,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _writeTranscript(
        projectId: projectId,
        clipId: clipId,
        language: language,
        speakerSpans: speakerSpans,
        result: result,
        now: now,
      );
    });
  }

  /// Writes one transcript and its words. **Caller supplies the transaction.**
  Future<void> _writeTranscript({
    required String projectId,
    required String clipId,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
    required DateTime now,
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
                startMs: entry.segment.fromTs.inMilliseconds,
                endMs: entry.segment.toTs.inMilliseconds,
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

/// One clip's transcript, watched rather than fetched, or null when it has not
/// been transcribed yet.
///
/// Speaker names live on this row, so a rename has to reach the transcript
/// view, the caption overlay and the export button with nothing being told to
/// refresh.
@riverpod
Stream<Transcript?> clipTranscript(Ref ref, String clipId) =>
    ref.watch(transcriptRepositoryProvider).watchTranscriptForClip(clipId);

/// A project's clips in timeline order. Empty for a project nobody has added
/// media to yet, which is the state "Create project" leaves behind.
@riverpod
Stream<List<MediaClip>> projectClips(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).watchClips(projectId);

/// A project's running time: the sum of its clips' durations.
///
/// Clips whose duration could not be probed contribute nothing rather than
/// making the whole total unknown — a slightly short number reads better in the
/// library than a blank one.
@riverpod
Duration projectDuration(Ref ref, String projectId) {
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
  var total = 0;
  for (final clip in clips) {
    total += clip.durationMs ?? 0;
  }
  return Duration(milliseconds: total);
}

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
