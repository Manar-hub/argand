import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/database/database.dart';
import '../../core/diarization/speaker_assignment.dart';
import '../../core/diarization/speaker_span.dart';
import '../../core/whisper/transcription_language_controller.dart';

part 'transcript_repository.g.dart';

/// All database access for projects and their transcripts.
///
/// Widgets never touch Drift directly (CLAUDE.md 4) -- they read the streams
/// and call the methods exposed here through Riverpod.
class TranscriptRepository {
  TranscriptRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// UUIDs are generated on-device, never delegated to the database
  /// (CLAUDE.md 5 -- no auto-increment IDs).
  String newId() => _uuid.v4();

  Stream<List<Project>> watchProjects() => _db.watchProjects();

  Future<Project?> findProject(String id) => _db.findProject(id);

  Future<Transcript?> findTranscriptForProject(String projectId) =>
      _db.findTranscriptForProject(projectId);

  Stream<List<Word>> watchWords(String transcriptId) => _db.watchWords(transcriptId);

  Future<void> softDeleteProject(String id) => _db.softDeleteProject(id);

  /// Corrects one word's text, leaving its timing alone. See
  /// [AppDatabase.updateWordText] for why that separation matters.
  Future<void> updateWordText(String wordId, String text) =>
      _db.updateWordText(wordId, text.trim());

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
  }) =>
      _db.reassignSpeaker(
        transcriptId: transcriptId,
        fromPosition: fromPosition,
        toPosition: toPosition,
        speakerId: speakerIdFor(speaker),
      );

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
    required String title,
    required String mediaPath,
    required Duration? duration,
    required TranscriptionLanguage language,
    required List<SpeakerSpan> speakerSpans,
    required WhisperTranscribeResponse result,
  }) async {
    final now = DateTime.now();
    final transcriptId = newId();

    await _db.transaction(() async {
      await _db.into(_db.projects).insert(
            ProjectsCompanion.insert(
              id: projectId,
              createdAt: now,
              updatedAt: now,
              title: title,
              mediaPath: mediaPath,
              durationMs: Value(duration?.inMilliseconds),
            ),
          );

      await _db.into(_db.transcripts).insert(
            TranscriptsCompanion.insert(
              id: transcriptId,
              createdAt: now,
              updatedAt: now,
              projectId: projectId,
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
    });
  }
}

@Riverpod(keepAlive: true)
TranscriptRepository transcriptRepository(Ref ref) =>
    TranscriptRepository(ref.watch(appDatabaseProvider));

@riverpod
Stream<List<Project>> projectList(Ref ref) =>
    ref.watch(transcriptRepositoryProvider).watchProjects();

@riverpod
Future<Project?> projectById(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).findProject(projectId);

@riverpod
Stream<List<Word>> transcriptWords(Ref ref, String transcriptId) =>
    ref.watch(transcriptRepositoryProvider).watchWords(transcriptId);

@riverpod
Future<Transcript?> projectTranscript(Ref ref, String projectId) =>
    ref.watch(transcriptRepositoryProvider).findTranscriptForProject(projectId);

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
