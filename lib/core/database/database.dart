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

@DriftDatabase(tables: [Projects, Transcripts, Words, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  /// First migration in this project.
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

  Stream<List<Word>> watchWords(String transcriptId) {
    return (select(words)
          ..where((t) => t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// Soft delete, per CLAUDE.md 5 -- never a hard row delete.
  Future<void> softDeleteProject(String id) {
    return (update(projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
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
