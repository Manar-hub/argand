import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

// Two generators write into this library. Drift emits `database.drift.dart`
// as a standalone part (see build.yaml for why it is not the default shared
// part), and riverpod_generator emits `database.g.dart`.
part 'database.drift.dart';
part 'database.g.dart';

/// Generates the UUID primary keys required by CLAUDE.md 5. Settings rows are
/// created inside this layer, so the generator lives here rather than being
/// threaded in from a repository.
const _uuid = Uuid();

/// Columns every table carries, per CLAUDE.md 5: UUID primary key generated
/// on-device, creation/update timestamps, and soft deletes only.
mixin _RecordColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// One imported media item and its editing state.
class Projects extends Table with _RecordColumns {
  TextColumn get title => text()();

  /// Path to this app's own copy of the media, never the picker's original
  /// URI. Android content:// permissions are revocable, so a project that
  /// referenced one would break the next time the app launched.
  TextColumn get mediaPath => text()();

  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transcripts extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get language => text().withDefault(const Constant('en'))();

  /// Custom speaker labels as JSON, or null when nobody has renamed anyone.
  ///
  /// A column rather than a `Speakers` table, and the reasoning is recorded so
  /// it is not re-litigated: a name only has to outlive the transcript it
  /// belongs to once speaker identity spans *projects* -- cross-project voice
  /// profiles, which is Tier 3. Until then a table buys a join and a migration
  /// for nothing.
  ///
  /// Shape is `{"0": {"name": "Ana"}}`, an object per speaker rather than a
  /// bare string, so a future editable colour is a new key instead of a data
  /// migration. Parsed by `speaker_names.dart`, tolerantly -- a row written by
  /// a newer build must not break an older one.
  ///
  /// Null is the normal state. The derived `Speaker N` label and
  /// `SpeakerPalette` colour remain the default, so a transcript nobody has
  /// touched stores nothing and renders exactly as it always did.
  TextColumn get speakerNames => text().nullable()();

  /// Whole-transcript text as the engine returned it. Convenient for search
  /// and export; [Words] remains the source of truth for timing.
  TextColumn get fullText => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One word with its timing. Captions, tap-to-seek and grouping modes are all
/// presentation layers over this table -- never separate transcription runs.
@TableIndex(name: 'words_transcript_start', columns: {#transcriptId, #startMs})
class Words extends Table with _RecordColumns {
  TextColumn get transcriptId => text().references(Transcripts, #id)();

  /// Position within the transcript. Kept explicit rather than relying on
  /// timestamps, which can tie or drift.
  IntColumn get position => integer()();

  TextColumn get word => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  /// Populated by diarization in a later phase.
  TextColumn get speakerId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One reversible edit, appended by `TranscriptRepository` as it mutates a
/// transcript. Undo and redo walk this log rather than diffing documents.
///
/// Rows are ordered by [EditEvents.sequence] rather than `createdAt`: two edits
/// made in the same millisecond would tie, and undo order has to be total.
@TableIndex(
    name: 'edit_events_transcript_seq', columns: {#transcriptId, #sequence})
class EditEvents extends Table with _RecordColumns {
  /// References the transcript so the log inherits its lifecycle -- deleting a
  /// project takes its edit history with it, with nothing to clean up
  /// separately.
  TextColumn get transcriptId => text().references(Transcripts, #id)();

  /// Monotonic within one transcript, assigned at append time.
  IntColumn get sequence => integer()();

  /// An `EditEventKind.code`. Stored as text, not an enum index, so inserting a
  /// case into that enum cannot reinterpret rows already on disk.
  TextColumn get kind => text()();

  /// JSON, carrying both the before and after state. See `edit_event.dart`.
  TextColumn get payload => text()();

  /// Null while the edit is in effect and undoable; set once undone, which
  /// makes it redoable. Redo is therefore a query, not a second stack.
  DateTimeColumn get undoneAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small key/value store for app-level choices that are not domain records --
/// currently just which transcription model to use.
///
/// Carries [_RecordColumns] like every other table (CLAUDE.md 5), so the UUID
/// primary key is kept even though [key] is what callers actually look up. A
/// unique index on [key] is what prevents duplicate rows for one setting;
/// making [key] the primary key instead would have been the more obvious
/// design but would break the project-wide UUID convention for no real gain.
@TableIndex(name: 'settings_key', columns: {#key}, unique: true)
class Settings extends Table with _RecordColumns {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Projects, Transcripts, Words, Settings, EditEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  /// Schema history: 1 -> 2 added [Settings], 2 -> 3 added [EditEvents],
  /// 3 -> 4 added [Transcripts.speakerNames].
  ///
  /// `onUpgrade` must stay additive and version-guarded: an installed app
  /// carries real user transcripts, so a migration that recreated tables would
  /// destroy them. Each future step gets its own `if (from < n)` block, and
  /// they run in order for a device that skipped several releases.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(settings);
          }
          if (from < 3) {
            await migrator.createTable(editEvents);
          }
          if (from < 4) {
            await migrator.addColumn(transcripts, transcripts.speakerNames);
          }
        },
      );

  /// Current value of [key], or null if never set.
  Future<String?> readSetting(String key) async {
    final row = await (select(settings)
          ..where((t) => t.key.equals(key) & t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) {
    return (select(settings)
          ..where((t) => t.key.equals(key) & t.deletedAt.isNull())
          ..limit(1))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  /// Inserts or updates [key].
  ///
  /// Written as read-then-write inside a transaction rather than an upsert on
  /// the unique index, because a soft-deleted row still occupies that index --
  /// an upsert would resurrect it with its old `deletedAt` intact.
  Future<void> writeSetting(String key, String value) async {
    final now = DateTime.now();
    await transaction(() async {
      final existing = await (select(settings)
            ..where((t) => t.key.equals(key))
            ..limit(1))
          .getSingleOrNull();

      if (existing == null) {
        await into(settings).insert(
          SettingsCompanion.insert(
            id: _uuid.v4(),
            createdAt: now,
            updatedAt: now,
            key: key,
            value: value,
          ),
        );
      } else {
        await (update(settings)..where((t) => t.id.equals(existing.id))).write(
          SettingsCompanion(
            value: Value(value),
            updatedAt: Value(now),
            deletedAt: const Value(null),
          ),
        );
      }
    });
  }

  /// Replaces a transcript's stored speaker labels.
  ///
  /// Takes the encoded value, null included: `SpeakerNames.encode` returns null
  /// once the last name is cleared, which puts the row back to the state an
  /// untouched transcript is in rather than leaving an empty object behind.
  Future<void> writeSpeakerNames(String transcriptId, String? encoded) {
    final now = DateTime.now();
    return (update(transcripts)..where((t) => t.id.equals(transcriptId))).write(
      TranscriptsCompanion(
        speakerNames: Value(encoded),
        updatedAt: Value(now),
      ),
    );
  }

  /// Retires [key], for per-project settings whose project is being deleted.
  ///
  /// Soft, like every other delete. [writeSetting] already resurrects a
  /// soft-deleted row rather than colliding with it on the unique index, so a
  /// key retired here is reusable if the same id ever comes back.
  Future<void> softDeleteSetting(String key) {
    final now = DateTime.now();
    return (update(settings)..where((t) => t.key.equals(key))).write(
      SettingsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Projects that have not been soft-deleted, newest first.
  Stream<List<Project>> watchProjects() {
    return (select(projects)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<Project?> findProject(String id) {
    return (select(projects)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<Transcript?> findTranscriptForProject(String projectId) {
    return (select(transcripts)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Transcript?> findTranscript(String id) {
    return (select(transcripts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Transcript?> watchTranscript(String id) {
    return (select(transcripts)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// A project's transcript, re-emitted whenever it changes.
  ///
  /// Watched rather than fetched once because speaker names live on this row:
  /// a rename has to reach the transcript view, the caption overlay and the
  /// export button without any of them being told to refresh.
  Stream<Transcript?> watchTranscriptForProject(String projectId) {
    return (select(transcripts)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Stream<List<Word>> watchWords(String transcriptId) {
    return (select(words)
          ..where((t) => t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// Corrects the text of one word, and nothing else.
  ///
  /// **Timings are deliberately untouched.** A correction fixes what the engine
  /// heard, not when it was said, and `startMs`/`endMs` are what tap-to-seek,
  /// caption grouping and the playback highlight are all built on. Moving them
  /// to "fit" a longer or shorter word would desynchronise every one of those
  /// from the audio, which is why this writes `word` alone.
  Future<void> updateWordText(String wordId, String text) {
    return (update(words)..where((t) => t.id.equals(wordId))).write(
      WordsCompanion(
        word: Value(text),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reassigns every word from [fromPosition] to [toPosition] inclusive to
  /// [speaker].
  ///
  /// Addressed by position rather than by id because a turn is a contiguous run
  /// of words, and the caller is correcting the whole run. One transaction, so
  /// a partial rewrite cannot leave a turn split across two speakers -- which
  /// is the very thing being corrected.
  Future<void> reassignSpeaker({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required String speakerId,
  }) {
    return transaction(() async {
      await (update(words)
            ..where((t) =>
                t.transcriptId.equals(transcriptId) &
                t.deletedAt.isNull() &
                t.position.isBetweenValues(fromPosition, toPosition)))
          .write(
        WordsCompanion(
          speakerId: Value(speakerId),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Soft delete, per CLAUDE.md 5 -- never a hard row delete.
  ///
  /// The project's *media* is not soft-deleted: `TranscriptRepository` removes
  /// that directory outright, because a tombstone row costs a few hundred bytes
  /// while an orphaned video costs hundreds of megabytes that nothing would
  /// ever reclaim.
  Future<void> softDeleteProject(String id) {
    return (update(projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// How many undoable edits one transcript keeps.
  ///
  /// Bounded per `docs/engine-architecture.md`, which asks for a window rather
  /// than unbounded growth. The cost is small either way -- an event is a few
  /// hundred bytes, so this window is tens of kilobytes -- but a log nobody
  /// prunes grows for the lifetime of the install.
  static const int editHistoryLimit = 100;

  Future<Word?> findWord(String id) =>
      (select(words)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Words at positions [from]..[to] inclusive, in order.
  Future<List<Word>> wordsInPositionRange({
    required String transcriptId,
    required int from,
    required int to,
  }) {
    return (select(words)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.position.isBetweenValues(from, to))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  /// Writes a different `speakerId` to each listed position, nulls included.
  ///
  /// [reassignSpeaker] writes one value across a whole run, which is what a
  /// correction does. Undoing one has to put back whatever each word held
  /// before -- several speakers, or none at all -- so it cannot reuse that path.
  Future<void> restoreSpeakerIds({
    required String transcriptId,
    required Map<int, String?> speakerIds,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      for (final entry in speakerIds.entries) {
        await (update(words)
              ..where((t) =>
                  t.transcriptId.equals(transcriptId) &
                  t.position.equals(entry.key)))
            .write(
          WordsCompanion(
            speakerId: Value(entry.value),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Replaces the live words at positions [fromPosition]..[toPosition] with
  /// [replacements], keeping `position` contiguous across the whole transcript.
  ///
  /// This is the only operation that changes how many words a transcript has,
  /// and it is deliberately one primitive used in both directions: undoing a
  /// sentence edit is the same call with the two lists swapped.
  ///
  /// Entries carrying an `id` **amend that row**, clearing `deletedAt` if it
  /// was set. That matters for more than tidiness: reusing the row is what
  /// keeps an older [EditEvents] entry that addresses a word by id resolvable
  /// after this edit has been undone. Entries without an id are new rows and
  /// get a fresh UUID (CLAUDE.md 5).
  ///
  /// Live rows in the range that no replacement claims are soft-deleted, never
  /// removed.
  Future<void> spliceWords({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required List<
            ({
              String? id,
              String text,
              int startMs,
              int endMs,
              String? speakerId
            })>
        replacements,
  }) {
    final now = DateTime.now();

    return transaction(() async {
      final existing = await wordsInPositionRange(
        transcriptId: transcriptId,
        from: fromPosition,
        to: toPosition,
      );

      final claimed = {
        for (final row in replacements)
          if (row.id != null) row.id!,
      };

      // Which of those ids are rows that actually exist. An id alone does not
      // imply one: the caller mints ids for brand-new words so the undo event
      // can record them, and a row being restored by an undo is soft-deleted
      // and therefore outside [existing]. Checked against the whole table,
      // ignoring `deletedAt`, so a restore updates rather than duplicates.
      final known = claimed.isEmpty
          ? const <String>{}
          : (await (select(words)..where((t) => t.id.isIn(claimed))).get())
              .map((row) => row.id)
              .toSet();

      for (final row in existing) {
        if (claimed.contains(row.id)) continue;
        await (update(words)..where((t) => t.id.equals(row.id))).write(
          WordsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }

      // Shift the tail before writing the new range, so the two never have to
      // interleave. `position` carries no unique constraint, so a transient
      // overlap inside the transaction is harmless -- only the committed state
      // has to be contiguous.
      final delta = replacements.length - (toPosition - fromPosition + 1);
      if (delta != 0) {
        await customUpdate(
          'UPDATE words SET position = position + ?, updated_at = ? '
          'WHERE transcript_id = ? AND deleted_at IS NULL AND position > ?',
          variables: [
            Variable<int>(delta),
            Variable<DateTime>(now),
            Variable<String>(transcriptId),
            Variable<int>(toPosition),
          ],
          updates: {words},
        );
      }

      for (final (index, row) in replacements.indexed) {
        final position = fromPosition + index;

        if (row.id == null || !known.contains(row.id)) {
          await into(words).insert(
            WordsCompanion.insert(
              // Honours an id the caller minted, so the undo event that
              // recorded it still addresses this row on a later redo.
              id: row.id ?? _uuid.v4(),
              createdAt: now,
              updatedAt: now,
              transcriptId: transcriptId,
              position: position,
              word: row.text,
              startMs: row.startMs,
              endMs: row.endMs,
              speakerId: Value(row.speakerId),
            ),
          );
          continue;
        }

        await (update(words)..where((t) => t.id.equals(row.id!))).write(
          WordsCompanion(
            position: Value(position),
            word: Value(row.text),
            startMs: Value(row.startMs),
            endMs: Value(row.endMs),
            speakerId: Value(row.speakerId),
            // Undo restores rows this edit removed, so clearing the flag is
            // part of the operation rather than an edge case.
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Appends one event to [transcriptId]'s log.
  ///
  /// **Call inside the same transaction as the mutation it records**, so an
  /// edit and its log entry commit or fail together. An edit with no event is
  /// silently un-undoable; an event with no edit undoes something that never
  /// happened.
  ///
  /// Two housekeeping steps run with it. Any *undone* events are discarded
  /// first -- this is linear undo, so editing after undoing abandons the redo
  /// branch rather than trying to reconcile it. Then the log is pruned back to
  /// [editHistoryLimit].
  Future<void> appendEditEvent({
    required String transcriptId,
    required String kind,
    required String payload,
  }) async {
    final now = DateTime.now();

    await (update(editEvents)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.undoneAt.isNotNull()))
        .write(EditEventsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));

    // Over every row, not just the live ones: a sequence number reused after a
    // prune would sort a new event underneath an older one.
    final highest = await (selectOnly(editEvents)
          ..addColumns([editEvents.sequence.max()])
          ..where(editEvents.transcriptId.equals(transcriptId)))
        .getSingle();
    final next = (highest.read(editEvents.sequence.max()) ?? 0) + 1;

    await into(editEvents).insert(
      EditEventsCompanion.insert(
        id: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
        transcriptId: transcriptId,
        sequence: next,
        kind: kind,
        payload: payload,
      ),
    );

    final live = await (select(editEvents)
          ..where(
              (t) => t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.sequence)]))
        .get();
    if (live.length > editHistoryLimit) {
      final stale = live.skip(editHistoryLimit).map((e) => e.id).toList();
      await (update(editEvents)..where((t) => t.id.isIn(stale)))
          .write(EditEventsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
    }
  }

  /// The next event undo would reverse: the newest one still in effect.
  Future<EditEvent?> nextUndoEvent(String transcriptId) {
    return (select(editEvents)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.undoneAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.sequence)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// The next event redo would re-apply: the oldest one already undone.
  ///
  /// Oldest rather than newest, so several undos followed by several redos
  /// retrace the same path in reverse instead of jumping about inside the
  /// undone run.
  Future<EditEvent?> nextRedoEvent(String transcriptId) {
    return (select(editEvents)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.undoneAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> markEditEventUndone(String id, {required bool undone}) {
    final now = DateTime.now();
    return (update(editEvents)..where((t) => t.id.equals(id))).write(
      EditEventsCompanion(
        undoneAt: Value(undone ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Drops an event without applying it -- used when its payload will not
  /// decode, so one corrupt row cannot wedge the undo button permanently.
  Future<void> discardEditEvent(String id) {
    final now = DateTime.now();
    return (update(editEvents)..where((t) => t.id.equals(id))).write(
      EditEventsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Whether undo and redo currently have anything to do.
  ///
  /// Reads only `undoneAt`, and is `distinct` so the buttons rebuild when
  /// availability actually flips rather than on every write to the log.
  Stream<({bool canUndo, bool canRedo})> watchEditHistory(String transcriptId) {
    final query = selectOnly(editEvents)
      ..addColumns([editEvents.undoneAt])
      ..where(editEvents.transcriptId.equals(transcriptId) &
          editEvents.deletedAt.isNull());

    return query.watch().map((rows) {
      var canUndo = false;
      var canRedo = false;
      for (final row in rows) {
        if (row.read(editEvents.undoneAt) == null) {
          canUndo = true;
        } else {
          canRedo = true;
        }
      }
      return (canUndo: canUndo, canRedo: canRedo);
    }).distinct();
  }
}

QueryExecutor _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'argand.sqlite'));
    // Runs the database on its own isolate so queries never block the UI.
    return NativeDatabase.createInBackground(file);
  });
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
