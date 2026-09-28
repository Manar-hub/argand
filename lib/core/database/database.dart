import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../text/library_search.dart';

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

/// One project: a title, and an ordered list of [MediaClips].
class Projects extends Table with _RecordColumns {
  TextColumn get title => text()();

  /// Vestigial since schema 5. Do not read it.
  TextColumn get mediaPath => text()();

  /// **Vestigial since schema 5**, for the same reason as [mediaPath]. A
  /// project's running time is now the sum of its clips' durations.
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One piece of media inside a project, at a position on the timeline.
@TableIndex(name: 'media_clips_project_position', columns: {#projectId, #position})
class MediaClips extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  /// Order on the timeline, contiguous from zero within a project. No unique
  /// constraint, for the same reason [Words.position] has none: a reorder
  /// rewrites a run of rows and would trip one mid-flight.
  IntColumn get position => integer()();

  /// Path to this app's own copy of the media, never the picker's original URI.
  /// Android content:// permissions are revocable, so a clip that referenced
  /// one would break the next time the app launched.
  TextColumn get mediaPath => text()();

  /// Null when `probeDuration` could not read the container -- the same
  /// tolerance [Projects.durationMs] had, for the same reason.
  IntColumn get durationMs => integer().nullable()();

  /// Where this clip begins and ends inside its media file.
  IntColumn get trimStartMs => integer().nullable()();
  IntColumn get trimEndMs => integer().nullable()();

  /// The source file's name, for accessibility labels and debugging. Clips are
  /// identified visually by their frames rather than by a name, so nothing in
  /// the UI renames this.
  TextColumn get title => text()();

  /// Amplitude readings for the audio lane: one byte per bucket, at
  /// `waveformPeaksPerSecond`. See `lib/core/audio/waveform.dart`.
  BlobColumn get waveform => blob().nullable()();

  /// How the picture sits in the output frame: moved, turned and scaled on top
  /// of the fit the render already does. See `ItemTransform`.
  RealColumn get scale => real().withDefault(const Constant(1.0))();

  /// Degrees, clockwise as seen.
  RealColumn get rotation => real().withDefault(const Constant(0.0))();

  /// The picture's centre, in shares of the frame's half-width and
  /// half-height from the middle; up is positive.
  RealColumn get offsetX => real().withDefault(const Constant(0.0))();
  RealColumn get offsetY => real().withDefault(const Constant(0.0))();

  /// Where this clip's sound begins and ends, relative to its picture: added to
  /// the picture window's start and end (`audio_window.dart`).
  IntColumn get audioStartOffsetMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get audioEndOffsetMs => integer().withDefault(const Constant(0))();

  /// The clip's sound removed from the timeline, its picture left in place.
  BoolColumn get audioMuted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A stretch of the project timeline the user has asked to have transcribed.
@TableIndex(
    name: 'transcribe_layers_project_start', columns: {#projectId, #startMs})
class TranscribeLayers extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  /// Which stacked track the layer sits on. Always 0 today.
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  /// The [Tracks] row this layer sits on. Null only on a row written before
  /// schema 15 that `ensureTracks` has not yet placed.
  TextColumn get trackId => text().nullable()();

  /// Where this layer's captions sit in the frame, and how large.
  RealColumn get captionX => real().withDefault(const Constant(0.0))();
  RealColumn get captionY => real().withDefault(const Constant(-0.82))();
  RealColumn get captionScale => real().withDefault(const Constant(1.0))();

  /// How this layer's captions look, as `ItemLook` JSON. Null is the default
  /// look captions have always had.
  TextColumn get captionLook => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Words the user put on the picture, for a stretch of the project.
@TableIndex(name: 'text_layers_project_start', columns: {#projectId, #startMs})
class TextLayers extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  TextColumn get content => text()();

  /// The text's centre, in shares of the frame's half-size; up is positive.
  RealColumn get x => real().withDefault(const Constant(0.0))();
  RealColumn get y => real().withDefault(const Constant(0.0))();
  RealColumn get scale => real().withDefault(const Constant(1.0))();

  /// Degrees, clockwise as seen.
  RealColumn get rotation => real().withDefault(const Constant(0.0))();

  /// Which row of the old text track it sat on, before schema 15 made tracks
  /// rows of their own. Read only by `ensureTracks`, to give each old row its
  /// own track.
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  /// The [Tracks] row this text sits on; see [TranscribeLayers.trackId].
  TextColumn get trackId => text().nullable()();

  /// Font and colour, as `ItemLook` JSON; null is bold white in the default
  /// face.
  TextColumn get look => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What a [Tracks] row may hold.
///
/// **Stored as its code, never its index**, like `TimelineEventKind`.
enum TrackKind {
  /// The clips, played one after another.
  video('video'),

  /// The clips' sound, and only sound.
  audio('audio'),

  /// Anything else: transcriptions, sentences, translation, texts, images.
  media('media');

  const TrackKind(this.code);

  final String code;

  static TrackKind fromCode(String code) => TrackKind.values
      .firstWhere((kind) => kind.code == code, orElse: () => TrackKind.media);
}

/// One lane of a project's timeline, top to bottom by [position].
@TableIndex(name: 'tracks_project_position', columns: {#projectId, #position})
class Tracks extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  /// Order from the top, contiguous from zero within a project once
  /// `ensureTracks` or a move has written it.
  IntColumn get position => integer()();

  /// A [TrackKind.code].
  TextColumn get kind => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A picture the user put over the video, for a stretch of the project.
@TableIndex(name: 'image_layers_project_start', columns: {#projectId, #startMs})
class ImageLayers extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get trackId => text()();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  /// The app's own copy, in the project's media directory -- never the
  /// picker's URI, for the reason [MediaClips.mediaPath] gives.
  TextColumn get path => text()();

  /// The picture's size in pixels, for its shape; the stage and the export
  /// size it from [scale], not from these.
  IntColumn get widthPx => integer()();
  IntColumn get heightPx => integer()();

  RealColumn get x => real().withDefault(const Constant(0.0))();
  RealColumn get y => real().withDefault(const Constant(0.0))();
  RealColumn get scale => real().withDefault(const Constant(1.0))();
  RealColumn get rotation => real().withDefault(const Constant(0.0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transcripts extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  /// The clip these words were transcribed from.
  TextColumn get clipId => text().nullable().references(MediaClips, #id)();

  /// The layer whose run produced this transcript, or null for one written
  /// before layers existed and back-filled by the schema-6 migration.
  TextColumn get layerId => text().nullable().references(TranscribeLayers, #id)();

  /// The clip-relative range these words actually cover.
  IntColumn get clipStartMs => integer().nullable()();
  IntColumn get clipEndMs => integer().nullable()();

  TextColumn get language => text().withDefault(const Constant('en'))();

  /// Custom speaker labels as JSON, or null when nobody has renamed anyone.
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

  /// Where this word's sentence sits as a caption, when it has been placed on
  /// its own. Null means "wherever its layer puts captions", which is every
  /// word until the user moves its sentence.
  RealColumn get captionX => real().nullable()();
  RealColumn get captionY => real().nullable()();
  RealColumn get captionScale => real().nullable()();

  /// How this word's sentence looks as a caption when styled on its own --
  /// font, colour, karaoke and the like, as `ItemLook` JSON. Null follows the
  /// layer, the same bargain as the placement above.
  TextColumn get captionLook => text().nullable()();

  /// The [Tracks] row this word's sentence was moved onto. **Null follows its
  /// layer's track**, which is every word until its sentence is dragged to
  /// another -- the same bargain as the placement above.
  TextColumn get captionTrackId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A transcript's translation, one line per sentence, kept beside the
/// transcript rather than in it.
@TableIndex(
    name: 'translation_lines_transcript',
    columns: {#transcriptId, #position})
class TranslationLines extends Table with _RecordColumns {
  TextColumn get transcriptId => text().references(Transcripts, #id)();

  /// The language translated into, as its two-letter code.
  TextColumn get language => text()();

  /// Which sentence of the transcript, from 0.
  IntColumn get position => integer()();

  IntColumn get firstWord => integer()();
  IntColumn get lastWord => integer()();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  TextColumn get content => text()();

  /// The [Tracks] row this line sits on; see [TranscribeLayers.trackId].
  TextColumn get trackId => text().nullable()();

  /// Where the line sits and how it looks when placed on its own. **Null
  /// follows its layer's captions**, lifted above them (`translation_texts`).
  RealColumn get x => real().nullable()();
  RealColumn get y => real().nullable()();
  RealColumn get scale => real().nullable()();
  TextColumn get look => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One reversible edit, appended by `TranscriptRepository` as it mutates a
/// transcript. Undo and redo walk this log rather than diffing documents.
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
@TableIndex(name: 'settings_key', columns: {#key}, unique: true)
class Settings extends Table with _RecordColumns {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One reversible thing that happened to a project's arrangement.
class TimelineEvents extends Table with _RecordColumns {
  /// References the project so the log inherits its lifecycle -- deleting a
  /// project takes its history with it, with nothing to clean up separately.
  TextColumn get projectId => text().references(Projects, #id)();

  /// Monotonic within one project, assigned at append time.
  IntColumn get sequence => integer()();

  /// A `TimelineEventKind.code`. **Text, not an enum index**, so inserting a
  /// case into that enum cannot reinterpret rows already on disk.
  TextColumn get kind => text()();

  /// JSON, carrying both the before and after state.
  TextColumn get payload => text()();

  /// Null while the edit is in effect and undoable; set once undone, which
  /// makes it redoable. Redo is therefore a query, not a second stack -- the
  /// same shape [EditEvents] uses.
  DateTimeColumn get undoneAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Projects,
  MediaClips,
  TranscribeLayers,
  Transcripts,
  Words,
  Settings,
  EditEvents,
  TimelineEvents,
  TextLayers,
  TranslationLines,
  Tracks,
  ImageLayers,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 15;

  /// Schema history: 1 -> 2 added [Settings], 2 -> 3 added [EditEvents], 3 -> 4
  /// added [Transcripts.speakerNames], 4 -> 5 added [MediaClips] and
  /// [Transcripts.clipId], moving media off the project row.
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
          if (from < 5) {
            await migrator.createTable(mediaClips);
            await migrator.addColumn(transcripts, transcripts.clipId);
            await _backfillClips();
          }
          if (from < 6) {
            await migrator.createTable(transcribeLayers);
            await migrator.addColumn(transcripts, transcripts.layerId);
            await migrator.addColumn(transcripts, transcripts.clipStartMs);
            await migrator.addColumn(transcripts, transcripts.clipEndMs);
            await _backfillLayers();
          }
          // `from >= 5`, not just `from < 7`.
          if (from >= 5 && from < 7) {
            // No backfill. Null already means "not computed yet", so every
            // existing clip simply fills its lane in the first time the
            // timeline asks -- which is the same path a newly added clip takes.
            await migrator.addColumn(mediaClips, mediaClips.waveform);
          }
          // Paired with 5 for the same reason as the waveform column above:
          // `createTable` builds `media_clips` from its *current* definition,
          // so a database arriving from before schema 5 already has these.
          if (from < 9) {
            // A whole table rather than a column, so no version pairing is
            // needed: `createTable` is correct from any earlier schema.
            await migrator.createTable(timelineEvents);
          }
          if (from >= 5 && from < 8) {
            // No backfill. Null is exactly "never trimmed", which is what
            // every existing clip is.
            await migrator.addColumn(mediaClips, mediaClips.trimStartMs);
            await migrator.addColumn(mediaClips, mediaClips.trimEndMs);
          }
          // Paired with 5, the version that created `media_clips`, and with 6
          // for `transcribe_layers`, for the reason given above.
          if (from >= 5 && from < 10) {
            await migrator.addColumn(mediaClips, mediaClips.scale);
            await migrator.addColumn(mediaClips, mediaClips.rotation);
            await migrator.addColumn(mediaClips, mediaClips.offsetX);
            await migrator.addColumn(mediaClips, mediaClips.offsetY);
          }
          if (from >= 6 && from < 10) {
            await migrator.addColumn(transcribeLayers, transcribeLayers.captionX);
            await migrator.addColumn(transcribeLayers, transcribeLayers.captionY);
            await migrator.addColumn(
              transcribeLayers,
              transcribeLayers.captionScale,
            );
          }
          if (from < 10) {
            await migrator.createTable(textLayers);
          }
          // `words` has existed since schema 1, so every upgrade adds these.
          // Null is "follows its layer", so nothing is back-filled.
          if (from < 11) {
            await migrator.addColumn(words, words.captionX);
            await migrator.addColumn(words, words.captionY);
            await migrator.addColumn(words, words.captionScale);
          }
          // Each paired with the version that created its table, as above.
          if (from < 12) {
            await migrator.addColumn(words, words.captionLook);
          }
          if (from >= 6 && from < 12) {
            await migrator.addColumn(
              transcribeLayers,
              transcribeLayers.captionLook,
            );
          }
          if (from >= 10 && from < 12) {
            await migrator.addColumn(textLayers, textLayers.look);
          }
          if (from < 13) {
            await migrator.createTable(translationLines);
          }
          // MediaClips exists from schema 5, so an older database has just
          // created it complete and must not add the columns twice.
          if (from >= 5 && from < 14) {
            await migrator.addColumn(mediaClips, mediaClips.audioStartOffsetMs);
            await migrator.addColumn(mediaClips, mediaClips.audioEndOffsetMs);
            await migrator.addColumn(mediaClips, mediaClips.audioMuted);
          }
          // Each paired with the version that created its table, as above.
          if (from < 15) {
            await migrator.createTable(tracks);
            await migrator.createTable(imageLayers);
            await migrator.addColumn(words, words.captionTrackId);
          }
          if (from >= 6 && from < 15) {
            await migrator.addColumn(transcribeLayers, transcribeLayers.trackId);
          }
          if (from >= 10 && from < 15) {
            await migrator.addColumn(textLayers, textLayers.trackId);
          }
          if (from >= 13 && from < 15) {
            await migrator.addColumn(translationLines, translationLines.trackId);
            await migrator.addColumn(translationLines, translationLines.x);
            await migrator.addColumn(translationLines, translationLines.y);
            await migrator.addColumn(translationLines, translationLines.scale);
            await migrator.addColumn(translationLines, translationLines.look);
          }

          // `createTable` does not create a table's declared indexes.
          for (final index in [
            mediaClipsProjectPosition,
            transcribeLayersProjectStart,
            wordsTranscriptStart,
            settingsKey,
            editEventsTranscriptSeq,
            textLayersProjectStart,
            translationLinesTranscript,
            tracksProjectPosition,
            imageLayersProjectStart,
          ]) {
            final sql = index.createStatementsByDialect[SqlDialect.sqlite];
            if (sql == null) continue;
            await customStatement(
              sql.replaceFirstMapped(
                RegExp('^CREATE (UNIQUE )?INDEX '),
                (m) => '${m.group(0)}IF NOT EXISTS ',
              ),
            );
          }

          // After the columns and tables exist: every project's items were
          // on the fixed lanes of old, and get the tracks those lanes were.
          if (from < 15) {
            final live = await (select(projects)
                  ..where((t) => t.deletedAt.isNull()))
                .get();
            for (final project in live) {
              await _placeOnTracks(project.id);
            }
          }
        },
      );

  /// Gives every existing transcript the layer its clip always implied.
  Future<void> _backfillLayers() async {
    final projectRows = await select(projects).get();
    final now = DateTime.now();

    for (final project in projectRows) {
      // Soft-deleted clips included: the offsets have to match the arrangement
      // the transcripts were made against, and a tombstoned project's rows
      // should stay internally consistent.
      final clips = await (select(mediaClips)
            ..where((t) => t.projectId.equals(project.id))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

      var offset = 0;
      for (final clip in clips) {
        final duration = clip.durationMs ?? 0;
        final span = duration < 0 ? 0 : duration;

        final covering = await (select(transcripts)
              ..where((t) => t.clipId.equals(clip.id) & t.deletedAt.isNull()))
            .get();

        for (final transcript in covering) {
          final layerId = _uuid.v4();
          await into(transcribeLayers).insert(
            TranscribeLayersCompanion.insert(
              id: layerId,
              createdAt: transcript.createdAt,
              updatedAt: now,
              projectId: project.id,
              startMs: offset,
              endMs: offset + span,
              deletedAt: Value(clip.deletedAt),
            ),
          );

          await (update(transcripts)..where((t) => t.id.equals(transcript.id)))
              .write(
            TranscriptsCompanion(
              layerId: Value(layerId),
              clipStartMs: const Value(0),
              clipEndMs: Value(span),
            ),
          );
        }

        offset += span;
      }
    }
  }

  /// Gives every pre-schema-5 project the clip its media already implied.
  Future<void> _backfillClips() async {
    final rows = await select(projects).get();
    final now = DateTime.now();

    for (final project in rows) {
      final clipId = _uuid.v4();
      await into(mediaClips).insert(
        MediaClipsCompanion.insert(
          id: clipId,
          createdAt: project.createdAt,
          updatedAt: now,
          projectId: project.id,
          position: 0,
          mediaPath: project.mediaPath,
          durationMs: Value(project.durationMs),
          title: project.title,
          // A deleted project's clip is deleted with it, so the tombstone
          // stays internally consistent.
          deletedAt: Value(project.deletedAt),
        ),
      );

      await (update(transcripts)..where((t) => t.projectId.equals(project.id)))
          .write(TranscriptsCompanion(clipId: Value(clipId)));
    }
  }

  /// Current value of [key], or null if never set.
  Future<String?> readSetting(String key) async {
    final row = await (select(settings)
          ..where((t) => t.key.equals(key) & t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return row?.value;
  }

  /// Inserts or updates [key].
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
  Future<void> writeSpeakerNames(String transcriptId, String? encoded) {
    final now = DateTime.now();
    return (update(transcripts)..where((t) => t.id.equals(transcriptId))).write(
      TranscriptsCompanion(
        speakerNames: Value(encoded),
        updatedAt: Value(now),
      ),
    );
  }

  /// How many *live* clips outside project [excluding] point at [mediaPath].
  Future<int> projectsSharingMedia(String mediaPath,
      {required String excluding}) async {
    final rows = await (select(mediaClips)
          ..where((t) =>
              t.mediaPath.equals(mediaPath) &
              t.deletedAt.isNull() &
              t.projectId.equals(excluding).not()))
        .get();
    final images = await (select(imageLayers)
          ..where((t) =>
              t.path.equals(mediaPath) &
              t.deletedAt.isNull() &
              t.projectId.equals(excluding).not()))
        .get();
    return rows.length + images.length;
  }

  /// Creates a project with no media, for the "Create project" entry point.
  Future<void> createEmptyProject({
    required String projectId,
    required String title,
  }) {
    final now = DateTime.now();
    return into(projects).insert(
      ProjectsCompanion.insert(
        id: projectId,
        createdAt: now,
        updatedAt: now,
        title: title,
        mediaPath: '',
      ),
    );
  }

  /// A project's clips in timeline order.
  Stream<List<MediaClip>> watchClips(String projectId) {
    return (select(mediaClips)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// A project's clips in timeline order, read once.
  Future<List<MediaClip>> clipsForProject(String projectId) {
    return (select(mediaClips)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  /// Records a clip's running time once something authoritative knows it.
  Future<void> fillMissingClipDuration(String clipId, Duration duration) {
    if (duration <= Duration.zero) return Future.value();
    return (update(mediaClips)
          ..where((t) =>
              t.id.equals(clipId) &
              (t.durationMs.isNull() | t.durationMs.isSmallerOrEqualValue(0))))
        .write(
      MediaClipsCompanion(
        durationMs: Value(duration.inMilliseconds),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Stores the amplitude readings backing a clip's audio lane.
  Future<void> fillMissingClipWaveform(String clipId, Uint8List peaks) {
    if (peaks.isEmpty) return Future.value();
    return (update(mediaClips)
          ..where((t) => t.id.equals(clipId) & t.waveform.isNull()))
        .write(
      MediaClipsCompanion(
        waveform: Value(peaks),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<MediaClip?> findClip(String id) {
    return (select(mediaClips)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Appends a clip to the end of [projectId]'s timeline.
  Future<void> appendClip({
    required String clipId,
    required String projectId,
    required String mediaPath,
    required Duration? duration,
    required String title,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      final existing = await clipsForProject(projectId);
      final next = existing.isEmpty ? 0 : existing.last.position + 1;

      await into(mediaClips).insert(
        MediaClipsCompanion.insert(
          id: clipId,
          createdAt: now,
          updatedAt: now,
          projectId: projectId,
          position: next,
          mediaPath: mediaPath,
          durationMs: Value(duration?.inMilliseconds),
          title: title,
        ),
      );
    });
  }

  /// Removes a clip and closes the gap its position left behind.
  Future<void> softDeleteClip(String clipId) {
    final now = DateTime.now();
    return transaction(() async {
      final clip = await findClip(clipId);
      if (clip == null) return;

      await (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
        MediaClipsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await customUpdate(
        'UPDATE media_clips SET position = position - 1, updated_at = ? '
        'WHERE project_id = ? AND deleted_at IS NULL AND position > ?',
        variables: [
          Variable.withInt(now.millisecondsSinceEpoch ~/ 1000),
          Variable.withString(clip.projectId),
          Variable.withInt(clip.position),
        ],
        updates: {mediaClips},
      );
    });
  }

  /// Rewrites the whole project's clip order from [orderedIds].
  Future<void> trimClip({
    required String clipId,
    required int startMs,
    required int endMs,
  }) {
    return (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
      MediaClipsCompanion(
        trimStartMs: Value(startMs),
        trimEndMs: Value(endMs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets where [clipId]'s sound begins and ends relative to its picture.
  Future<void> setAudioOffsets({
    required String clipId,
    required int startOffsetMs,
    required int endOffsetMs,
  }) {
    return (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
      MediaClipsCompanion(
        audioStartOffsetMs: Value(startOffsetMs),
        audioEndOffsetMs: Value(endOffsetMs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Removes [clipId]'s sound from the timeline, or puts it back.
  Future<void> setAudioMuted(String clipId, bool muted) {
    return (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
      MediaClipsCompanion(
        audioMuted: Value(muted),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Splits one clip into two at [atMediaMs], measured in the media's own time.
  Future<String?> splitClip({
    required String clipId,
    required int atMediaMs,
    required String Function() newId,
  }) async {
    final now = DateTime.now();

    return transaction(() async {
      final clip = await findClip(clipId);
      if (clip == null) return null;

      final newClipId = newId();
      final originalEnd = clip.trimEndMs;

      // Room first: every clip after this one moves along by one, highest
      // position first so no two rows ever hold the same position mid-flight.
      final later = await (select(mediaClips)
            ..where((t) =>
                t.projectId.equals(clip.projectId) &
                t.deletedAt.isNull() &
                t.position.isBiggerThanValue(clip.position))
            ..orderBy([(t) => OrderingTerm.desc(t.position)]))
          .get();

      for (final other in later) {
        await (update(mediaClips)..where((t) => t.id.equals(other.id))).write(
          MediaClipsCompanion(
            position: Value(other.position + 1),
            updatedAt: Value(now),
          ),
        );
      }

      await into(mediaClips).insert(
        MediaClipsCompanion.insert(
          id: newClipId,
          createdAt: now,
          updatedAt: now,
          projectId: clip.projectId,
          position: clip.position + 1,
          mediaPath: clip.mediaPath,
          durationMs: Value(clip.durationMs),
          trimStartMs: Value(atMediaMs),
          trimEndMs: Value(originalEnd),
          // The sound is cut where the picture is: the right half keeps the
          // original's tail, and its new front edge starts with its picture.
          audioEndOffsetMs: Value(clip.audioEndOffsetMs),
          audioMuted: Value(clip.audioMuted),
          title: clip.title,
          // The same file, so the readings are identical by construction.
          waveform: Value(clip.waveform),
        ),
      );

      await (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
        MediaClipsCompanion(
          trimEndMs: Value(atMediaMs),
          // The left half's sound now ends at the cut, with its picture.
          audioEndOffsetMs: const Value(0),
          updatedAt: Value(now),
        ),
      );

      for (final transcript in await transcriptsForClip(clipId)) {
        final newTranscriptId = newId();
        await into(transcripts).insert(
          TranscriptsCompanion.insert(
            id: newTranscriptId,
            createdAt: now,
            updatedAt: now,
            projectId: transcript.projectId,
            clipId: Value(newClipId),
            layerId: Value(transcript.layerId),
            clipStartMs: Value(transcript.clipStartMs),
            clipEndMs: Value(transcript.clipEndMs),
            language: Value(transcript.language),
            speakerNames: Value(transcript.speakerNames),
            fullText: transcript.fullText,
          ),
        );

        final carried = await (select(words)
              ..where((t) =>
                  t.transcriptId.equals(transcript.id) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();

        await batch((batch) {
          batch.insertAll(words, [
            for (final word in carried)
              WordsCompanion.insert(
                id: newId(),
                createdAt: now,
                updatedAt: now,
                transcriptId: newTranscriptId,
                position: word.position,
                word: word.word,
                startMs: word.startMs,
                endMs: word.endMs,
                speakerId: Value(word.speakerId),
              ),
          ]);
        });
      }

      return newClipId;
    });
  }

  Future<void> reorderClips({
    required String projectId,
    required List<String> orderedIds,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      for (final (index, id) in orderedIds.indexed) {
        await (update(mediaClips)
              ..where((t) => t.id.equals(id) & t.projectId.equals(projectId)))
            .write(
          MediaClipsCompanion(
            position: Value(index),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Every transcript covering one clip, earliest range first.
  Stream<List<Transcript>> watchTranscriptsForClip(String clipId) {
    return (select(transcripts)
          ..where((t) => t.clipId.equals(clipId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.clipStartMs),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Transcript>> transcriptsForClip(String clipId) {
    return (select(transcripts)
          ..where((t) => t.clipId.equals(clipId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.clipStartMs),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  /// A project's layers in timeline order.
  Stream<List<TranscribeLayer>> watchLayers(String projectId) {
    return (select(transcribeLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .watch();
  }

  Future<List<TranscribeLayer>> layersForProject(String projectId) {
    return (select(transcribeLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .get();
  }

  Future<TranscribeLayer?> findLayer(String layerId) {
    return (select(transcribeLayers)
          ..where((t) => t.id.equals(layerId) & t.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// Every transcript a layer's run produced.
  Future<List<Transcript>> transcriptsForLayer(String layerId) {
    return (select(transcripts)
          ..where((t) => t.layerId.equals(layerId) & t.deletedAt.isNull()))
        .get();
  }

  Future<void> insertLayer({
    required String layerId,
    required String projectId,
    required int startMs,
    required int endMs,
    int trackIndex = 0,
    String? trackId,
  }) {
    final now = DateTime.now();
    return into(transcribeLayers).insert(
      TranscribeLayersCompanion.insert(
        id: layerId,
        createdAt: now,
        updatedAt: now,
        projectId: projectId,
        startMs: startMs,
        endMs: endMs,
        trackIndex: Value(trackIndex),
        trackId: Value(trackId),
      ),
    );
  }

  Future<void> moveLayer({
    required String layerId,
    required int startMs,
    required int endMs,
  }) {
    final now = DateTime.now();
    return (update(transcribeLayers)..where((t) => t.id.equals(layerId))).write(
      TranscribeLayersCompanion(
        startMs: Value(startMs),
        endMs: Value(endMs),
        updatedAt: Value(now),
      ),
    );
  }

  /// Where a layer's captions sit.
  Future<void> setLayerCaptionPlacement({
    required String layerId,
    required double x,
    required double y,
    required double scale,
  }) {
    return (update(transcribeLayers)..where((t) => t.id.equals(layerId)))
        .write(
      TranscribeLayersCompanion(
        captionX: Value(x),
        captionY: Value(y),
        captionScale: Value(scale),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// How a clip's picture sits in the frame.
  Future<void> setClipFraming({
    required String clipId,
    required double x,
    required double y,
    required double scale,
    required double rotation,
  }) {
    return (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
      MediaClipsCompanion(
        offsetX: Value(x),
        offsetY: Value(y),
        scale: Value(scale),
        rotation: Value(rotation),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// A project's text layers in timeline order.
  Stream<List<TextLayer>> watchTextLayers(String projectId) {
    return (select(textLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .watch();
  }

  /// A transcript's translation, in the order it is said. Empty when it has
  /// none.
  Stream<List<TranslationLine>> watchTranslationLines(String transcriptId) {
    return (select(translationLines)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.startMs),
            (t) => OrderingTerm.asc(t.position),
          ]))
        .watch();
  }

  Future<List<TranslationLine>> translationLinesFor(String transcriptId) {
    return (select(translationLines)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.startMs),
            (t) => OrderingTerm.asc(t.position),
          ]))
        .get();
  }

  /// Puts [lines] in place of whatever translation [transcriptId] had, in one
  /// transaction: the old lines are retired, not overwritten, like every other
  /// row.
  Future<void> replaceTranslation(
    String transcriptId,
    List<TranslationLinesCompanion> lines, {
    ({int from, int to})? words,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(translationLines)
            ..where((t) {
              final live =
                  t.transcriptId.equals(transcriptId) & t.deletedAt.isNull();
              return words == null
                  ? live
                  : live &
                      t.firstWord.isSmallerOrEqualValue(words.to) &
                      t.lastWord.isBiggerOrEqualValue(words.from);
            }))
          .write(TranslationLinesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await batch((b) => b.insertAll(translationLines, lines));
    });
  }

  /// Retires [transcriptId]'s translation, or just the part over [words].
  Future<void> removeTranslation(
    String transcriptId, {
    ({int from, int to})? words,
  }) =>
      replaceTranslation(transcriptId, const [], words: words);

  /// A translation line, retired or not -- undo has to reach retired ones.
  Future<TranslationLine?> findTranslationLine(String id) =>
      (select(translationLines)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Every live translation line in a project, whichever transcript it
  /// translates.
  Future<List<TranslationLine>> translationLinesForProject(String projectId) {
    final query = select(translationLines).join([
      innerJoin(
        transcripts,
        transcripts.id.equalsExp(translationLines.transcriptId),
      ),
    ])
      ..where(transcripts.projectId.equals(projectId) &
          transcripts.deletedAt.isNull() &
          translationLines.deletedAt.isNull());
    return query.map((row) => row.readTable(translationLines)).get();
  }

  /// Writes whichever of a translation line's text, timing, track and
  /// placement are given. [clearPlacement] hands its placement and look back
  /// to its layer.
  Future<void> updateTranslationLine({
    required String id,
    String? content,
    int? startMs,
    int? endMs,
    String? trackId,
    double? x,
    double? y,
    double? scale,
    String? look,
  }) {
    Value<T> maybe<T>(T? value) =>
        value == null ? const Value.absent() : Value(value);

    return (update(translationLines)..where((t) => t.id.equals(id))).write(
      TranslationLinesCompanion(
        content: maybe(content),
        startMs: maybe(startMs),
        endMs: maybe(endMs),
        trackId: maybe(trackId),
        x: maybe(x),
        y: maybe(y),
        scale: maybe(scale),
        look: maybe(look),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets a translation line's placement outright, nulls included -- what
  /// undoing its first move on the stage has to write.
  Future<void> setTranslationLinePlacement({
    required String id,
    required double? x,
    required double? y,
    required double? scale,
  }) {
    return (update(translationLines)..where((t) => t.id.equals(id))).write(
      TranslationLinesCompanion(
        x: Value(x),
        y: Value(y),
        scale: Value(scale),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets a translation line's look outright, null included.
  Future<void> setTranslationLineLook({required String id, String? look}) {
    return (update(translationLines)..where((t) => t.id.equals(id))).write(
      TranslationLinesCompanion(
        look: Value(look),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Retires one translation line, or brings it back.
  Future<void> setTranslationLineRetired({
    required String id,
    required bool retired,
  }) {
    final now = DateTime.now();
    return (update(translationLines)..where((t) => t.id.equals(id))).write(
      TranslationLinesCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// A project's live tracks, top to bottom.
  Stream<List<Track>> watchTracks(String projectId) {
    return (select(tracks)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  Future<List<Track>> tracksForProject(String projectId) {
    return (select(tracks)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  /// Makes sure [projectId] has its video and audio tracks and that every
  /// transcription, text and translation line sits on a track, and returns the
  /// tracks, top to bottom.
  Future<List<Track>> ensureTracks(String projectId) =>
      transaction(() => _placeOnTracks(projectId));

  /// [ensureTracks] without its transaction, for the migration, which is
  /// already inside one.
  Future<List<Track>> _placeOnTracks(String projectId) async {
    {
      final existing = await tracksForProject(projectId);
      final known = {for (final track in existing) track.id};
      bool unplaced(String? trackId) =>
          trackId == null || !known.contains(trackId);

      final layers = [
        for (final layer in await layersForProject(projectId))
          if (unplaced(layer.trackId)) layer,
      ];
      final texts = [
        for (final text in await textLayersForProject(projectId))
          if (unplaced(text.trackId)) text,
      ];
      final lines = [
        for (final line in await translationLinesForProject(projectId))
          if (unplaced(line.trackId)) line,
      ];
      final hasVideo =
          existing.any((track) => track.kind == TrackKind.video.code);
      final hasAudio =
          existing.any((track) => track.kind == TrackKind.audio.code);
      if (layers.isEmpty &&
          texts.isEmpty &&
          lines.isEmpty &&
          hasVideo &&
          hasAudio) {
        return existing;
      }

      final now = DateTime.now();
      Future<String> add(TrackKind kind) async {
        final id = _uuid.v4();
        await into(tracks).insert(TracksCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          projectId: projectId,
          position: 0,
          kind: kind.code,
        ));
        return id;
      }

      final top = <String>[];
      final rows = {for (final text in texts) text.trackIndex}.toList()
        ..sort();
      for (final row in rows) {
        final id = await add(TrackKind.media);
        top.add(id);
        await (update(textLayers)
              ..where((t) => t.id.isIn([
                    for (final text in texts)
                      if (text.trackIndex == row) text.id,
                  ])))
            .write(TextLayersCompanion(trackId: Value(id)));
      }
      if (lines.isNotEmpty) {
        final id = await add(TrackKind.media);
        top.add(id);
        await (update(translationLines)
              ..where((t) => t.id.isIn([for (final line in lines) line.id])))
            .write(TranslationLinesCompanion(trackId: Value(id)));
      }
      if (layers.isNotEmpty) {
        final id = await add(TrackKind.media);
        top.add(id);
        await (update(transcribeLayers)
              ..where((t) => t.id.isIn([for (final layer in layers) layer.id])))
            .write(TranscribeLayersCompanion(trackId: Value(id)));
      }
      final bottom = [
        if (!hasVideo) await add(TrackKind.video),
        if (!hasAudio) await add(TrackKind.audio),
      ];

      await _writeTrackOrder([
        ...top,
        for (final track in existing) track.id,
        ...bottom,
      ]);
      return tracksForProject(projectId);
    }
  }

  /// Writes [trackIds]' positions as their order in the list.
  Future<void> setTrackOrder(List<String> trackIds) =>
      transaction(() => _writeTrackOrder(trackIds));

  Future<void> _writeTrackOrder(List<String> trackIds) async {
    final now = DateTime.now();
    for (final (position, id) in trackIds.indexed) {
      await (update(tracks)..where((t) => t.id.equals(id))).write(
        TracksCompanion(position: Value(position), updatedAt: Value(now)),
      );
    }
  }

  /// A new media track at [position], or at the bottom when that is null;
  /// every track from there down moves one lower.
  Future<void> insertTrack({
    required String id,
    required String projectId,
    int? position,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      final existing = await tracksForProject(projectId);
      await into(tracks).insert(TracksCompanion.insert(
        id: id,
        createdAt: now,
        updatedAt: now,
        projectId: projectId,
        position: 0,
        kind: TrackKind.media.code,
      ));
      final order = [for (final track in existing) track.id];
      order.insert((position ?? order.length).clamp(0, order.length), id);
      await _writeTrackOrder(order);
    });
  }

  /// Retires a track, or brings it back where it was.
  Future<void> setTrackRetired({required String id, required bool retired}) {
    final now = DateTime.now();
    return (update(tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Moves a transcription onto [trackId].
  Future<void> setLayerTrack({required String layerId, required String trackId}) {
    return (update(transcribeLayers)..where((t) => t.id.equals(layerId))).write(
      TranscribeLayersCompanion(
        trackId: Value(trackId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Retimes words, and sets the track their sentence sits on, one row each
  /// -- a sentence dragged or resized on the timeline.
  Future<void> setWordPlacements(
    List<({String id, int startMs, int endMs, String? trackId})> placements,
  ) {
    final now = DateTime.now();
    return transaction(() async {
      for (final word in placements) {
        await (update(words)..where((t) => t.id.equals(word.id))).write(
          WordsCompanion(
            startMs: Value(word.startMs),
            endMs: Value(word.endMs),
            captionTrackId: Value(word.trackId),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// A project's live images in timeline order.
  Stream<List<ImageLayer>> watchImageLayers(String projectId) {
    return (select(imageLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .watch();
  }

  Future<List<ImageLayer>> imageLayersForProject(String projectId) {
    return (select(imageLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .get();
  }

  /// An image, retired or not -- undo has to reach retired ones.
  Future<ImageLayer?> findImageLayer(String id) =>
      (select(imageLayers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertImageLayer(ImageLayersCompanion row) =>
      into(imageLayers).insert(row);

  /// Writes whichever of an image's timing, track and placement are given.
  Future<void> updateImageLayer({
    required String id,
    int? startMs,
    int? endMs,
    String? trackId,
    double? x,
    double? y,
    double? scale,
    double? rotation,
  }) {
    Value<T> maybe<T>(T? value) =>
        value == null ? const Value.absent() : Value(value);

    return (update(imageLayers)..where((t) => t.id.equals(id))).write(
      ImageLayersCompanion(
        startMs: maybe(startMs),
        endMs: maybe(endMs),
        trackId: maybe(trackId),
        x: maybe(x),
        y: maybe(y),
        scale: maybe(scale),
        rotation: maybe(rotation),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setImageLayerRetired({required String id, required bool retired}) {
    final now = DateTime.now();
    return (update(imageLayers)..where((t) => t.id.equals(id))).write(
      ImageLayersCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  Future<List<TextLayer>> textLayersForProject(String projectId) {
    return (select(textLayers)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.startMs)]))
        .get();
  }

  /// A text layer, retired or not -- undo has to reach retired ones.
  Future<TextLayer?> findTextLayer(String id) {
    return (select(textLayers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertTextLayer({
    required String id,
    required String projectId,
    required int startMs,
    required int endMs,
    required String content,
    int trackIndex = 0,
    String? trackId,
  }) {
    final now = DateTime.now();
    return into(textLayers).insert(
      TextLayersCompanion.insert(
        id: id,
        createdAt: now,
        updatedAt: now,
        projectId: projectId,
        startMs: startMs,
        endMs: endMs,
        content: content,
        trackIndex: Value(trackIndex),
        trackId: Value(trackId),
      ),
    );
  }

  /// Writes whichever of a text layer's words, timing and placement are given.
  Future<void> updateTextLayer({
    required String id,
    String? content,
    int? startMs,
    int? endMs,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    String? trackId,
  }) {
    Value<T> maybe<T>(T? value) =>
        value == null ? const Value.absent() : Value(value);

    return (update(textLayers)..where((t) => t.id.equals(id))).write(
      TextLayersCompanion(
        trackId: maybe(trackId),
        content: maybe(content),
        startMs: maybe(startMs),
        endMs: maybe(endMs),
        x: maybe(x),
        y: maybe(y),
        scale: maybe(scale),
        rotation: maybe(rotation),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Retires a text layer, or brings it back. Soft, per CLAUDE.md §5, and
  /// what lets adding and removing one be undone.
  Future<void> setTextLayerRetired({required String id, required bool retired}) {
    final now = DateTime.now();
    return (update(textLayers)..where((t) => t.id.equals(id))).write(
      TextLayersCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Places one sentence's captions -- the words at [fromPosition] to
  /// [toPosition] -- or, with nulls, hands them back to their layer.
  Future<void> setSentencePlacement({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required double? x,
    required double? y,
    required double? scale,
  }) {
    return (update(words)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.position.isBetweenValues(fromPosition, toPosition)))
        .write(
      WordsCompanion(
        captionX: Value(x),
        captionY: Value(y),
        captionScale: Value(scale),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Styles one sentence's captions, or with null hands them back to their
  /// layer's look.
  Future<void> setSentenceLook({
    required String transcriptId,
    required int fromPosition,
    required int toPosition,
    required String? look,
  }) {
    return (update(words)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.position.isBetweenValues(fromPosition, toPosition)))
        .write(
      WordsCompanion(
        captionLook: Value(look),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets words' looks one by one: what undoing "style all captions" puts
  /// back, since each sentence styled on its own had its own.
  Future<void> setWordLooks(Map<String, String?> looks) async {
    final now = DateTime.now();
    await transaction(() async {
      for (final MapEntry(key: id, value: look) in looks.entries) {
        await (update(words)..where((t) => t.id.equals(id))).write(
          WordsCompanion(captionLook: Value(look), updatedAt: Value(now)),
        );
      }
    });
  }

  /// The live words in [transcriptIds] that carry a look of their own.
  Future<List<Word>> wordsWithOwnLook(List<String> transcriptIds) {
    if (transcriptIds.isEmpty) return Future.value(const []);
    return (select(words)
          ..where((t) =>
              t.transcriptId.isIn(transcriptIds) &
              t.deletedAt.isNull() &
              t.captionLook.isNotNull()))
        .get();
  }

  /// The first live word of a sentence, for reading the sentence's own look.
  Future<Word?> wordAt({required String transcriptId, required int position}) {
    return (select(words)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.position.equals(position)))
        .getSingleOrNull();
  }

  Future<void> setLayerCaptionLook({
    required String layerId,
    required String? look,
  }) {
    return (update(transcribeLayers)..where((t) => t.id.equals(layerId)))
        .write(
      TranscribeLayersCompanion(
        captionLook: Value(look),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setTextLook({required String id, required String? look}) {
    return (update(textLayers)..where((t) => t.id.equals(id))).write(
      TextLayersCompanion(look: Value(look), updatedAt: Value(DateTime.now())),
    );
  }

  /// Removes a layer, and with it the transcripts its run produced.
  Future<void> softDeleteLayer(String layerId) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(transcripts)..where((t) => t.layerId.equals(layerId)))
          .write(
        TranscriptsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (update(transcribeLayers)..where((t) => t.id.equals(layerId)))
          .write(
        TranscribeLayersCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Discards a layer's transcripts while keeping the layer itself, so it can
  /// be run again.
  Future<void> softDeleteTranscriptsForLayer(String layerId) {
    final now = DateTime.now();
    return (update(transcripts)..where((t) => t.layerId.equals(layerId))).write(
      TranscriptsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Copies a project, its transcript and every word, sharing the media file.
  Future<String> duplicateProject({
    required String sourceProjectId,
    required String newProjectId,
    required String title,
    required String Function() newId,
  }) async {
    final now = DateTime.now();

    return transaction(() async {
      final source = await findProject(sourceProjectId);
      if (source == null) {
        throw StateError('No project $sourceProjectId to duplicate');
      }

      await into(projects).insert(
        ProjectsCompanion.insert(
          id: newProjectId,
          createdAt: now,
          updatedAt: now,
          title: title,
          // Vestigial since schema 5; media lives on the copied clips below.
          mediaPath: '',
        ),
      );

      // Tracks before anything that sits on one, so every item can point at
      // the copy of its track. Placed first, so there is nothing unplaced.
      final trackIds = <String, String>{};
      for (final track in await _placeOnTracks(sourceProjectId)) {
        final newTrackId = newId();
        trackIds[track.id] = newTrackId;
        await into(tracks).insert(TracksCompanion.insert(
          id: newTrackId,
          createdAt: now,
          updatedAt: now,
          projectId: newProjectId,
          position: track.position,
          kind: track.kind,
        ));
      }

      for (final image in await imageLayersForProject(sourceProjectId)) {
        await into(imageLayers).insert(image
            .toCompanion(false)
            .copyWith(
              id: Value(newId()),
              createdAt: Value(now),
              updatedAt: Value(now),
              projectId: Value(newProjectId),
              trackId: Value(trackIds[image.trackId] ?? image.trackId),
            ));
      }

      // Layers first, so each copied transcript can point at the copy of the
      // layer that produced it rather than at the original's.
      final layerIds = <String, String>{};
      for (final layer in await layersForProject(sourceProjectId)) {
        final newLayerId = newId();
        layerIds[layer.id] = newLayerId;
        await into(transcribeLayers).insert(
          TranscribeLayersCompanion.insert(
            id: newLayerId,
            createdAt: now,
            updatedAt: now,
            projectId: newProjectId,
            startMs: layer.startMs,
            endMs: layer.endMs,
            trackIndex: Value(layer.trackIndex),
            trackId: Value(trackIds[layer.trackId]),
            captionX: Value(layer.captionX),
            captionY: Value(layer.captionY),
            captionScale: Value(layer.captionScale),
            captionLook: Value(layer.captionLook),
          ),
        );
      }

      for (final text in await textLayersForProject(sourceProjectId)) {
        await into(textLayers).insert(
          TextLayersCompanion.insert(
            id: newId(),
            createdAt: now,
            updatedAt: now,
            projectId: newProjectId,
            startMs: text.startMs,
            endMs: text.endMs,
            content: text.content,
            x: Value(text.x),
            y: Value(text.y),
            scale: Value(text.scale),
            rotation: Value(text.rotation),
            trackIndex: Value(text.trackIndex),
            trackId: Value(trackIds[text.trackId]),
            look: Value(text.look),
          ),
        );
      }

      // Every clip, in order, each reusing the source's file. Not a copy --
      // see `projectsSharingMedia`.
      for (final clip in await clipsForProject(sourceProjectId)) {
        final newClipId = newId();
        await into(mediaClips).insert(
          MediaClipsCompanion.insert(
            id: newClipId,
            createdAt: now,
            updatedAt: now,
            projectId: newProjectId,
            position: clip.position,
            mediaPath: clip.mediaPath,
            durationMs: Value(clip.durationMs),
            trimStartMs: Value(clip.trimStartMs),
            trimEndMs: Value(clip.trimEndMs),
            title: clip.title,
            // Carried rather than recomputed: the duplicate points at the
            // same media file, so the readings are identical by construction
            // and re-deriving them would mean decoding every clip again.
            waveform: Value(clip.waveform),
            scale: Value(clip.scale),
            rotation: Value(clip.rotation),
            offsetX: Value(clip.offsetX),
            offsetY: Value(clip.offsetY),
            audioStartOffsetMs: Value(clip.audioStartOffsetMs),
            audioEndOffsetMs: Value(clip.audioEndOffsetMs),
            audioMuted: Value(clip.audioMuted),
          ),
        );

        // Every transcript on the clip, not just one. A clip covered by two
        // layers would otherwise lose all but the newest, and the duplicate
        // would show a timeline of layers with no words under most of them.
        for (final transcript in await transcriptsForClip(clip.id)) {
          final newTranscriptId = newId();
          await into(transcripts).insert(
            TranscriptsCompanion.insert(
              id: newTranscriptId,
              createdAt: now,
              updatedAt: now,
              projectId: newProjectId,
              clipId: Value(newClipId),
              layerId: Value(layerIds[transcript.layerId]),
              clipStartMs: Value(transcript.clipStartMs),
              clipEndMs: Value(transcript.clipEndMs),
              language: Value(transcript.language),
              speakerNames: Value(transcript.speakerNames),
              fullText: transcript.fullText,
            ),
          );

          final words = await (select(this.words)
                ..where((t) =>
                    t.transcriptId.equals(transcript.id) & t.deletedAt.isNull())
                ..orderBy([(t) => OrderingTerm.asc(t.position)]))
              .get();

          await batch((batch) {
            batch.insertAll(this.words, [
              for (final word in words)
                WordsCompanion.insert(
                  id: newId(),
                  createdAt: now,
                  updatedAt: now,
                  transcriptId: newTranscriptId,
                  position: word.position,
                  word: word.word,
                  startMs: word.startMs,
                  endMs: word.endMs,
                  speakerId: Value(word.speakerId),
                  captionX: Value(word.captionX),
                  captionY: Value(word.captionY),
                  captionScale: Value(word.captionScale),
                  captionLook: Value(word.captionLook),
                  captionTrackId: Value(trackIds[word.captionTrackId]),
                ),
            ]);
          });

          final lines = await translationLinesFor(transcript.id);
          await batch((batch) {
            batch.insertAll(translationLines, [
              for (final line in lines)
                line.toCompanion(false).copyWith(
                      id: Value(newId()),
                      createdAt: Value(now),
                      updatedAt: Value(now),
                      transcriptId: Value(newTranscriptId),
                      trackId: Value(trackIds[line.trackId]),
                    ),
            ]);
          });
        }
      }

      return newProjectId;
    });
  }

  /// Retires [key], for per-project settings whose project is being deleted.
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

  /// The projects [query] finds, newest first, re-run whenever a project, a
  /// transcript or a word changes.
  Stream<List<LibraryHit>> watchLibrarySearch(String query) {
    return customSelect(
      'SELECT 1',
      readsFrom: {projects, transcripts, words},
    ).watch().asyncMap((_) => searchLibrary(query));
  }

  /// Every project whose title, or whose transcribed words, contain [query].
  Future<List<LibraryHit>> searchLibrary(String query) async {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];

    final phrase = tokens.join(' ');
    final titled = <String>{
      for (final project in await watchProjects().first)
        if (project.title.toLowerCase().contains(phrase)) project.id,
    };

    // Candidate starts: every live word containing the first token. The rest
    // of the phrase is confirmed below against the words that follow.
    final candidates = await customSelect(
      'SELECT t.project_id AS project_id, w.transcript_id AS transcript_id, '
      't.clip_id AS clip_id, w.position AS position '
      'FROM words w '
      'JOIN transcripts t ON t.id = w.transcript_id '
      'JOIN projects p ON p.id = t.project_id '
      'WHERE w.deleted_at IS NULL AND t.deleted_at IS NULL '
      'AND p.deleted_at IS NULL '
      r"AND w.word LIKE ? ESCAPE '\' "
      'ORDER BY t.created_at, w.position',
      variables: [Variable.withString('%${escapeLike(tokens.first)}%')],
      readsFrom: {projects, transcripts, words},
    ).get();

    const context = 8;
    final found = <String, LibraryWordHit>{};
    for (final row in candidates) {
      final projectId = row.read<String>('project_id');
      if (found.containsKey(projectId)) continue;

      final transcriptId = row.read<String>('transcript_id');
      final position = row.read<int>('position');
      final window = await (select(words)
            ..where((w) =>
                w.transcriptId.equals(transcriptId) &
                w.deletedAt.isNull() &
                w.position.isBetweenValues(
                  position - context,
                  position + tokens.length - 1 + context,
                ))
            ..orderBy([(w) => OrderingTerm.asc(w.position)]))
          .get();
      final at = window.indexWhere((w) => w.position == position);
      final text = [for (final w in window) w.word];
      if (at < 0 || !phraseMatchesAt(text, at, tokens)) continue;

      found[projectId] = LibraryWordHit(
        transcriptId: transcriptId,
        clipId: row.readNullable<String>('clip_id'),
        startMs: window[at].startMs,
        snippet: text,
        matchStart: at,
        matchLength: tokens.length,
      );
    }

    return [
      for (final project in await watchProjects().first)
        if (titled.contains(project.id) || found.containsKey(project.id))
          LibraryHit(project: project, word: found[project.id]),
    ];
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

  Stream<List<Word>> watchWords(String transcriptId) {
    return (select(words)
          ..where((t) => t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// Corrects the text of one word, and nothing else.
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
  Future<void> softDeleteProject(String id) {
    final now = DateTime.now();
    return transaction(() async {
      // The clips go with it. Their transcripts and words are left live but
      // unreachable, exactly as before -- every read path starts from the
      // project, so nothing can still find them.
      await (update(mediaClips)..where((t) => t.projectId.equals(id))).write(
        MediaClipsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await (update(transcribeLayers)..where((t) => t.projectId.equals(id)))
          .write(
        TranscribeLayersCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      // Images count towards the media refcount, so they must stop counting.
      await (update(imageLayers)..where((t) => t.projectId.equals(id))).write(
        ImageLayersCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await _softDeleteProjectRow(id, now);
    });
  }

  Future<void> _softDeleteProjectRow(String id, DateTime now) {
    return (update(projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// How many undoable edits one transcript keeps.
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
      // A sentence placed on its own stays where it was put when its words
      // are retyped: the new words take the placement the old ones had.
      final placed = existing.firstOrNull;

      final claimed = {
        for (final row in replacements)
          if (row.id != null) row.id!,
      };

      // Which of those ids are rows that actually exist.
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
      // interleave.
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

      if (placed != null && placed.captionX != null && replacements.isNotEmpty) {
        await setSentencePlacement(
          transcriptId: transcriptId,
          fromPosition: fromPosition,
          toPosition: fromPosition + replacements.length - 1,
          x: placed.captionX,
          y: placed.captionY,
          scale: placed.captionScale,
        );
      }
      // Its look is kept the same way.
      if (placed != null &&
          placed.captionLook != null &&
          replacements.isNotEmpty) {
        await setSentenceLook(
          transcriptId: transcriptId,
          fromPosition: fromPosition,
          toPosition: fromPosition + replacements.length - 1,
          look: placed.captionLook,
        );
      }
      // And the track it was moved onto.
      if (placed != null &&
          placed.captionTrackId != null &&
          replacements.isNotEmpty) {
        await (update(words)
              ..where((t) =>
                  t.transcriptId.equals(transcriptId) &
                  t.deletedAt.isNull() &
                  t.position.isBetweenValues(
                    fromPosition,
                    fromPosition + replacements.length - 1,
                  )))
            .write(WordsCompanion(captionTrackId: Value(placed.captionTrackId)));
      }
    });
  }

  /// A transcript's words whose sentence was moved off its layer's track.
  Future<List<Word>> wordsMovedOffTheirLayer(String transcriptId) {
    return (select(words)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) &
              t.deletedAt.isNull() &
              t.captionTrackId.isNotNull()))
        .get();
  }

  /// Appends one event to [transcriptId]'s log.
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
  /// Retires or restores a clip.
  Future<void> setClipRetired({
    required String clipId,
    required bool retired,
  }) {
    final now = DateTime.now();
    return (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
      MediaClipsCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Retires or restores a layer and the transcripts it produced.
  Future<void> setLayerRetired({
    required String layerId,
    required bool retired,
  }) {
    final now = DateTime.now();
    return transaction(() async {
      if (retired) {
        await (update(transcripts)
              ..where((t) => t.layerId.equals(layerId) & t.deletedAt.isNull()))
            .write(
          TranscriptsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      } else {
        // Read before the layer is cleared: its deletion time is the only
        // record of which cascade those transcripts belonged to.
        final layer = await (select(transcribeLayers)
              ..where((t) => t.id.equals(layerId)))
            .getSingleOrNull();
        final retiredAt = layer?.deletedAt;

        if (retiredAt != null) {
          await (update(transcripts)
                ..where((t) =>
                    t.layerId.equals(layerId) &
                    t.deletedAt.equals(retiredAt)))
              .write(
            TranscriptsCompanion(
              deletedAt: const Value<DateTime?>(null),
              updatedAt: Value(now),
            ),
          );
        }
      }

      await (update(transcribeLayers)..where((t) => t.id.equals(layerId)))
          .write(
        TranscribeLayersCompanion(
          deletedAt: Value(retired ? now : null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Retires or restores exactly these transcripts.
  Future<void> setTranscriptsRetired({
    required List<String> transcriptIds,
    required bool retired,
  }) async {
    if (transcriptIds.isEmpty) return;

    final now = DateTime.now();
    await (update(transcripts)..where((t) => t.id.isIn(transcriptIds))).write(
      TranscriptsCompanion(
        deletedAt: Value(retired ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Appends one timeline event, and closes the redo branch.
  Future<void> appendTimelineEvent({
    required String projectId,
    required String kind,
    required String payload,
  }) async {
    final now = DateTime.now();

    await (update(timelineEvents)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.deletedAt.isNull() &
              t.undoneAt.isNotNull()))
        .write(TimelineEventsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));

    // Over every row, not just the live ones: a sequence reused after a prune
    // would sort a new event underneath an older one.
    final highest = await (selectOnly(timelineEvents)
          ..addColumns([timelineEvents.sequence.max()])
          ..where(timelineEvents.projectId.equals(projectId)))
        .getSingle();
    final next = (highest.read(timelineEvents.sequence.max()) ?? 0) + 1;

    await into(timelineEvents).insert(
      TimelineEventsCompanion.insert(
        id: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
        projectId: projectId,
        sequence: next,
        kind: kind,
        payload: payload,
      ),
    );
  }

  /// A project's live timeline events, oldest first.
  Future<List<TimelineEvent>> timelineEventsFor(String projectId) {
    return (select(timelineEvents)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();
  }

  /// A project's live *transcript* events, oldest first.
  Future<List<EditEvent>> editEventsForProject(String projectId) async {
    final ids = await (select(transcripts)
          ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull()))
        .map((row) => row.id)
        .get();
    if (ids.isEmpty) return const [];

    return (select(editEvents)
          ..where((t) => t.transcriptId.isIn(ids) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sequence)]))
        .get();
  }

  Future<EditEvent?> findEditEvent(String id) {
    return (select(editEvents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<TimelineEvent?> findTimelineEvent(String id) {
    return (select(timelineEvents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> setTimelineEventUndone(String id, {required bool undone}) {
    final now = DateTime.now();
    return (update(timelineEvents)..where((t) => t.id.equals(id))).write(
      TimelineEventsCompanion(
        undoneAt: Value(undone ? now : null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Drops an event that cannot be read, rather than letting one bad row wedge
  /// the button for good.
  Future<void> discardTimelineEvent(String id) {
    final now = DateTime.now();
    return (update(timelineEvents)..where((t) => t.id.equals(id))).write(
      TimelineEventsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

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

  /// Whether the project has anything to undo or redo.
  Stream<({bool canUndo, bool canRedo})> watchProjectHistory(String projectId) {
    return customSelect(
      'SELECT 1',
      readsFrom: {editEvents, timelineEvents, transcripts},
    ).watch().asyncMap((_) async {
      final edits = await editEventsForProject(projectId);
      final timeline = await timelineEventsFor(projectId);

      var canUndo = false;
      var canRedo = false;
      for (final undoneAt in [
        for (final event in edits) event.undoneAt,
        for (final event in timeline) event.undoneAt,
      ]) {
        if (undoneAt == null) {
          canUndo = true;
        } else {
          canRedo = true;
        }
      }
      return (canUndo: canUndo, canRedo: canRedo);
    }).distinct();
  }
}

/// One project a library search found: by its title, its words, or both.
class LibraryHit {
  const LibraryHit({required this.project, this.word});

  final Project project;

  /// Where its transcript says the query, when it does.
  final LibraryWordHit? word;
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
