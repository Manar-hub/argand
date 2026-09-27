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

  /// **Vestigial since schema 5. Do not read it.**
  ///
  /// A project used to *be* one media file, and this column held its path.
  /// Media now lives on [MediaClips], one row per clip, because a project can
  /// hold several. The column survives only because migrations here are
  /// strictly additive (see [AppDatabase.migration]) and dropping it would mean
  /// recreating the table over real user data.
  ///
  /// Schema 5's migration copied every existing value into a clip row. New
  /// projects write `''`, which is why nothing may treat it as a path again.
  TextColumn get mediaPath => text()();

  /// **Vestigial since schema 5**, for the same reason as [mediaPath]. A
  /// project's running time is now the sum of its clips' durations.
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One piece of media inside a project, at a position on the timeline.
///
/// **Media and transcription are separate events.** A clip is added by copying
/// a file in; it carries no transcript until the user asks for one, which is
/// what lets a project hold several clips and transcribe only the ones worth
/// the minutes. [Transcripts.clipId] is the link, and it stays null until then.
///
/// Ordered by [position] rather than `createdAt` so clips can be rearranged
/// without rewriting timestamps.
@TableIndex(name: 'media_clips_project_position', columns: {#projectId, #position})
class MediaClips extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  /// Order on the timeline, contiguous from zero within a project. No unique
  /// constraint, for the same reason [Words.position] has none: a reorder
  /// rewrites a run of rows and would trip one mid-flight.
  IntColumn get position => integer()();

  /// Path to this app's own copy of the media, never the picker's original
  /// URI. Android content:// permissions are revocable, so a clip that
  /// referenced one would break the next time the app launched.
  ///
  /// Two clips may hold the same path: duplicating a project shares its media
  /// rather than copying hundreds of megabytes, so this is refcounted by query
  /// (`projectsSharingMedia`) rather than owned outright.
  TextColumn get mediaPath => text()();

  /// Null when `probeDuration` could not read the container -- the same
  /// tolerance [Projects.durationMs] had, for the same reason.
  IntColumn get durationMs => integer().nullable()();

  /// Where this clip begins and ends inside its media file.
  ///
  /// **Trimming is stored, never rendered.** The media is shared -- two clips
  /// may hold the same path, and duplicating a project shares it rather than
  /// copying hundreds of megabytes -- so cutting bytes out of the file would
  /// damage every other reference to it. An in/out point costs nothing, stays
  /// reversible, and is what lets a split be two rows over one file.
  ///
  /// **Null means untrimmed, which is not the same as zero.** A clip whose
  /// container could not be probed has no known end, so a null [trimEndMs]
  /// resolves to [durationMs] -- itself nullable -- rather than to a number.
  /// Writing 0 and the duration at creation time would have forced a backfill
  /// and made "never trimmed" indistinguishable from "trimmed to the whole".
  IntColumn get trimStartMs => integer().nullable()();
  IntColumn get trimEndMs => integer().nullable()();

  /// The source file's name, for accessibility labels and debugging. Clips are
  /// identified visually by their frames rather than by a name, so nothing in
  /// the UI renames this.
  TextColumn get title => text()();

  /// Amplitude readings for the audio lane: one byte per bucket, at
  /// `waveformPeaksPerSecond`. See `lib/core/audio/waveform.dart`.
  ///
  /// **Null means "not computed yet", never "silent".** Computing it needs a
  /// full native decode of the media, which is far too slow to run while the
  /// user waits for "+" to return, so the lane fills in afterwards and a clip
  /// added a moment ago legitimately has none.
  ///
  /// Stored rather than derived on demand, even though the 16kHz WAV it comes
  /// from is deliberately discarded (CLAUDE.md §5). The two are not comparable:
  /// that WAV is ~1.9MB per audio-minute and re-extracting it is seconds of
  /// CPU, whereas this is ~1.2KB per audio-minute and would otherwise be
  /// recomputed every time the timeline opened.
  BlobColumn get waveform => blob().nullable()();

  /// How the picture sits in the output frame: moved, turned and scaled on
  /// top of the fit the render already does. See `ItemTransform`.
  ///
  /// **Defaults, not nulls.** Unlike the trim points, "untouched" and "at the
  /// identity" are the same thing here -- a clip nobody has framed is exactly
  /// one at scale 1, turned 0 degrees, centred -- so the columns carry that
  /// value and every existing clip gets it without a backfill.
  RealColumn get scale => real().withDefault(const Constant(1.0))();

  /// Degrees, clockwise as seen.
  RealColumn get rotation => real().withDefault(const Constant(0.0))();

  /// The picture's centre, in shares of the frame's half-width and
  /// half-height from the middle; up is positive.
  RealColumn get offsetX => real().withDefault(const Constant(0.0))();
  RealColumn get offsetY => real().withDefault(const Constant(0.0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A stretch of the project timeline the user has asked to have transcribed.
///
/// **A layer is a request, not a result.** It exists as soon as the user draws
/// it and before anything has run; transcribing it produces [Transcripts], one
/// per clip it overlaps, and those point back here through
/// [Transcripts.layerId]. A layer with no transcripts has simply not been run
/// yet.
///
/// [startMs] and [endMs] are **project-timeline** milliseconds, not clip
/// offsets, because a layer may span several clips — which is also why it is
/// anchored to project time rather than to a clip. Reordering or deleting a
/// clip underneath a layer therefore changes the audio it covers without moving
/// the rectangle; the layer stops describing its transcripts, which is
/// detectable by comparing the two, and is a far more explicable outcome than a
/// rectangle silently jumping or vanishing.
///
/// Half-open, `[startMs, endMs)`, so two adjacent layers tile without both
/// claiming the same millisecond.
@TableIndex(
    name: 'transcribe_layers_project_start', columns: {#projectId, #startMs})
class TranscribeLayers extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  /// Which stacked track the layer sits on. Always 0 today.
  ///
  /// One column of insurance: a second track of layers is otherwise a
  /// migration rather than a UI change, and it costs nothing to carry now.
  /// Layers on the same track may not overlap, which is what makes "what
  /// happens when two layers claim the same audio" a question nobody has to
  /// answer.
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  /// Where this layer's captions sit in the frame, and how large.
  ///
  /// **Per layer, not per project**, so two layers -- two speakers, two
  /// languages -- can be placed apart. Moving several at once is a matter of
  /// selecting them together, not of a shared setting.
  ///
  /// The default is where captions have always rendered: centred, near the
  /// bottom (`CAPTION_ANCHOR_Y` in `VideoExportChannel.kt`).
  RealColumn get captionX => real().withDefault(const Constant(0.0))();
  RealColumn get captionY => real().withDefault(const Constant(-0.82))();
  RealColumn get captionScale => real().withDefault(const Constant(1.0))();

  /// How this layer's captions look, as `ItemLook` JSON. Null is the default
  /// look captions have always had.
  ///
  /// **JSON in one column** rather than a column per option, so the next
  /// style option costs no migration.
  TextColumn get captionLook => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Words the user put on the picture, for a stretch of the project.
///
/// Timed in **project** milliseconds, like [TranscribeLayers], so a text sits
/// over whatever is playing at that moment rather than belonging to a clip:
/// reordering clips underneath does not drag the title along with one of them.
///
/// Placed with the same four numbers a clip's picture uses (see
/// `ItemTransform`), so the stage moves, scales and turns every kind of item
/// the same way.
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

  /// Which stacked text track it sits on. Always 0 today; carried for the
  /// same reason [TranscribeLayers.trackIndex] is.
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  /// Font and colour, as `ItemLook` JSON; null is bold white in the default
  /// face.
  TextColumn get look => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transcripts extends Table with _RecordColumns {
  TextColumn get projectId => text().references(Projects, #id)();

  /// The clip these words were transcribed from.
  ///
  /// Nullable only because schema 5 added it to a table that already had rows
  /// and an additive `addColumn` cannot introduce NOT NULL; the migration
  /// back-filled every existing transcript, and everything written since sets
  /// it. Treat a null here as a row from a database that has not been migrated.
  ///
  /// Word timings are relative to the clip's own media. A project-wide axis
  /// does exist now (`ProjectTimeline`), but it describes the *arrangement* of
  /// clips rather than a single continuous recording, so it is derived from
  /// clip durations and never stored on a word.
  TextColumn get clipId => text().nullable().references(MediaClips, #id)();

  /// The layer whose run produced this transcript, or null for one written
  /// before layers existed and back-filled by the schema-6 migration.
  TextColumn get layerId => text().nullable().references(TranscribeLayers, #id)();

  /// The clip-relative range these words actually cover.
  ///
  /// **Stored rather than derived from the layer.** A layer's position is a
  /// fact about arrangement and moves whenever clips are reordered; this is a
  /// fact about audio — the range that was fed to the engine at the moment it
  /// ran — and must not move with it. Deriving it would silently relabel words
  /// the user has already corrected.
  ///
  /// Null means "the whole clip", which is exactly what a pre-schema-6
  /// transcript is, so legacy rows need no special case: read them as
  /// `clipStartMs ?? 0` and `clipEndMs ?? clip.durationMs`.
  IntColumn get clipStartMs => integer().nullable()();
  IntColumn get clipEndMs => integer().nullable()();

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

  /// Where this word's sentence sits as a caption, when it has been placed
  /// on its own. **Null means "wherever its layer puts captions"**, which is
  /// every word until the user moves its sentence.
  ///
  /// Kept on the word rather than on a sentence row because sentences are
  /// derived, never stored: every word of a placed sentence carries the same
  /// values, so a caption finds its placement from its own first word however
  /// the sentence is later cut into cues.
  RealColumn get captionX => real().nullable()();
  RealColumn get captionY => real().nullable()();
  RealColumn get captionScale => real().nullable()();

  /// How this word's sentence looks as a caption when styled on its own --
  /// font, colour, karaoke and the like, as `ItemLook` JSON. Null follows the
  /// layer, the same bargain as the placement above.
  TextColumn get captionLook => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A transcript's translation, one line per sentence, kept **beside** the
/// transcript rather than in it.
///
/// Its own table so nothing that reads a transcript -- the script, the
/// timeline's sentences, captions, subtitle export -- ever meets it unless it
/// asks: a translation is an extra, shown where the user turns it on.
///
/// A line carries its sentence's timing, in the clip's own time like [Words],
/// and the positions of the sentence's first and last word, so the script can
/// put it under the sentence it translates. One language per transcript:
/// translating again replaces the lines.
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

/// One reversible thing that happened to a project's arrangement.
///
/// **Deliberately generic, and that is the design.** Adding a new undoable
/// action must not cost a migration: everything specific to an action lives in
/// [payload], so a new one is a new [kind] code and an entry saying how to
/// apply it in each direction. Nothing here changes.
///
/// Separate from [EditEvents] because that table's `transcriptId` is a non-null
/// reference to [Transcripts] and a split or a reorder belongs to no
/// transcript. Relaxing that column means recreating the table, which the
/// additive-migration rule rules out. The two are read together as one
/// history, ordered by `createdAt`.
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 13;

  /// Schema history: 1 -> 2 added [Settings], 2 -> 3 added [EditEvents],
  /// 3 -> 4 added [Transcripts.speakerNames], 4 -> 5 added [MediaClips] and
  /// [Transcripts.clipId], moving media off the project row, 5 -> 6 added
  /// [TranscribeLayers] and the range columns on [Transcripts], 6 -> 7 added
  /// [MediaClips.waveform], 7 -> 8 added [MediaClips.trimStartMs] and
  /// [MediaClips.trimEndMs], 8 -> 9 added [TimelineEvents], 9 -> 10 added
  /// the framing columns on [MediaClips], the caption placement on
  /// [TranscribeLayers], and [TextLayers], 10 -> 11 added the per-sentence
  /// caption placement on [Words], 11 -> 12 added the looks (font, colour,
  /// caption mode) on [TranscribeLayers], [Words] and [TextLayers], 12 -> 13
  /// added [TranslationLines].
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
          // **`from >= 5`, not just `from < 7`.** `createTable` builds a table
          // from its *current* definition, so a database coming from before
          // schema 5 has just been handed a `media_clips` that already has
          // this column, and adding it again fails the whole migration with
          // "duplicate column name". Only a database that already carried the
          // table from an older build is missing it.
          //
          // The same applies to every future column on a table younger than
          // the schema: pair the version that adds the column with the
          // version that created the table.
          if (from >= 5 && from < 7) {
            // No backfill. Null already means "not computed yet", so every
            // existing clip simply fills its lane in the first time the
            // timeline asks -- which is the same path a newly added clip
            // takes. Decoding every clip in the library during a migration
            // would block the first launch after an update for minutes.
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
          // Paired with 5, the version that created `media_clips`, and with
          // 6 for `transcribe_layers`, for the reason given above. Their
          // defaults are the identity and today's caption position, so no
          // row needs writing.
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

          // **`createTable` does not create a table's declared indexes.**
          // `createAll()` does, so a fresh install had them and every upgraded
          // one silently did not -- `edit_events_transcript_seq` has been
          // missing on upgraded installs since schema 3, and
          // `media_clips_project_position` since schema 5. Nothing was
          // incorrect, queries were just walking tables that should have been
          // indexed, which is exactly the kind of drift that never announces
          // itself.
          //
          // Run unconditionally rather than inside a version guard, because
          // this has to repair databases already upgraded past the version
          // that should have created them — there is no `from` that identifies
          // "was missing an index it should have had".
          //
          // `createIndex` is not idempotent, so the statement each index
          // carries is rewritten to `IF NOT EXISTS` rather than being
          // hand-copied here; duplicating the definitions is how they drift
          // from the annotations they came from.
          for (final index in [
            mediaClipsProjectPosition,
            transcribeLayersProjectStart,
            wordsTranscriptStart,
            settingsKey,
            editEventsTranscriptSeq,
            textLayersProjectStart,
            translationLinesTranscript,
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
        },
      );

  /// Gives every existing transcript the layer its clip always implied.
  ///
  /// Runs inside the 5 -> 6 step. Each transcript covered a whole clip, so each
  /// gets a layer spanning that clip's stretch of the project timeline, and
  /// records the clip-relative range it covers as the whole clip.
  ///
  /// **Without this an already-transcribed project would open showing an empty
  /// layer track beside a full transcript**, and the obvious response is to
  /// draw a layer over the whole thing and transcribe it a second time. The
  /// back-fill is what makes "the track shows what has been transcribed" true
  /// on the first launch after upgrading.
  ///
  /// A transcript whose clip cannot be resolved keeps a null [Transcripts.layerId]
  /// rather than being given an invented rectangle over media nobody can find.
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
  ///
  /// Runs inside the 4 -> 5 step. Each project had exactly one media file
  /// recorded on its own row, so each gets exactly one clip at position 0
  /// carrying that path, and its transcripts are pointed at that clip.
  ///
  /// **Files are not moved.** `mediaPath` is an absolute path, so a migrated
  /// clip keeps pointing at `<media>/<projectId>/source.<ext>` while clips
  /// added later live in `<media>/<projectId>/<clipId>/`. Both layouts are
  /// valid and `MediaConverter` handles the difference when discarding one.
  ///
  /// Soft-deleted projects are migrated too: a tombstone row is what a future
  /// sync needs, and leaving one without a clip would make it the single shape
  /// the rest of the code no longer expects.
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

  /// How many *live* clips outside project [excluding] point at [mediaPath].
  ///
  /// The whole of media refcounting. Duplicated projects share one file rather
  /// than copying hundreds of megabytes, so a file can only be removed once
  /// nothing still needs it — and "nothing" means no clip a user can still
  /// open, which is why soft-deleted rows do not count.
  ///
  /// Counted over clips rather than projects since schema 5: media hangs off
  /// [MediaClips] now, and one project can hold several files.
  Future<int> projectsSharingMedia(String mediaPath,
      {required String excluding}) async {
    final rows = await (select(mediaClips)
          ..where((t) =>
              t.mediaPath.equals(mediaPath) &
              t.deletedAt.isNull() &
              t.projectId.equals(excluding).not()))
        .get();
    return rows.length;
  }

  /// Creates a project with no media, for the "Create project" entry point.
  ///
  /// [Projects.mediaPath] is written empty rather than left out because the
  /// column is NOT NULL and vestigial — see its doc. Clips carry the media.
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
  ///
  /// Written only when the row does not already have a usable one.
  /// `probeDuration` is allowed to fail, and every clip carried over by the
  /// schema-5 migration inherited whatever the *project* row held -- which for
  /// anything imported before duration probing worked is either null or, for
  /// the oldest rows, a literal zero. **Both count as unknown**: a zero-length
  /// clip cannot exist, so treating it as a real duration would collapse the
  /// clip to a minimum width on the timeline and leave the ruler nothing to
  /// measure, permanently. The player repairs it the first time it opens the
  /// clip and actually knows.
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
  ///
  /// Writes only where none are stored yet, so two timelines racing to fill
  /// the same lane settle on one result rather than the later one winning.
  /// Nothing invalidates these: a clip's media never changes in place -- the
  /// app owns its own copy and editing produces new clips.
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
  ///
  /// The position is computed here rather than by the caller so two adds cannot
  /// race to the same slot — the read and the insert share one transaction.
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
  ///
  /// The clip's transcript and words are left live but unreachable, exactly as
  /// [softDeleteProject] leaves a deleted project's rows: every read path
  /// starts from the clip, so nothing can still find them, and a future sync
  /// wants the tombstone rather than a hole.
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
  ///
  /// Takes the full order rather than a from/to pair: a drag produces a new
  /// arrangement, and writing it wholesale cannot leave two clips claiming one
  /// position the way an incremental shift can if it is interrupted.
  /// Stores a clip's in and out points.
  ///
  /// The media is untouched: two clips may share one file and duplicating a
  /// project shares it again, so a trim that rewrote bytes would damage every
  /// other reference. Nothing here validates the window -- `clipWindow` and
  /// `applyTrim` own that rule, and they are pure so it can be proven.
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

  /// Splits one clip into two at [atMediaMs], measured in the media's own time.
  ///
  /// **Two rows over one file**, not two files. The left keeps the original id
  /// and everything pointing at it; the right is new, starts where the left
  /// ends, and every later clip shifts along to make room.
  ///
  /// **The transcripts are copied to the right-hand clip rather than moved or
  /// dropped.** Word timings are relative to the media, so both halves address
  /// the same numbers and each simply renders the part inside its own window.
  /// Moving them would strip the left clip of its captions, and dropping them
  /// would silently lose the second half's -- the kind of loss that only shows
  /// up at export.
  ///
  /// Returns the new clip's id, or null if the clip is gone.
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
          title: clip.title,
          // The same file, so the readings are identical by construction.
          waveform: Value(clip.waveform),
        ),
      );

      await (update(mediaClips)..where((t) => t.id.equals(clipId))).write(
        MediaClipsCompanion(
          trimEndMs: Value(atMediaMs),
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
  ///
  /// **Plural since schema 6**, having been a single row with
  /// `ORDER BY createdAt DESC LIMIT 1` before that. Once a clip can be covered
  /// by two layers — 0–10s and 40–60s, say — the old shape did not merely lose
  /// precision, it returned whichever ran most recently and gave no sign the
  /// other existed.
  ///
  /// Watched rather than fetched once because speaker names live on these rows,
  /// so a rename has to reach the transcript view, the caption overlay and the
  /// export button without any of them being told to refresh.
  ///
  /// Ordered by [Transcripts.clipStartMs], which sorts nulls first in SQLite —
  /// exactly where a legacy whole-clip transcript belongs.
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

  /// A transcript's translation, in sentence order. Empty when it has none.
  Stream<List<TranslationLine>> watchTranslationLines(String transcriptId) {
    return (select(translationLines)
          ..where((t) =>
              t.transcriptId.equals(transcriptId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  Future<List<TranslationLine>> translationLinesFor(String transcriptId) =>
      watchTranslationLines(transcriptId).first;

  /// Puts [lines] in place of whatever translation [transcriptId] had, in one
  /// transaction: the old lines are retired, not overwritten, like every
  /// other row.
  Future<void> replaceTranslation(
    String transcriptId,
    List<TranslationLinesCompanion> lines,
  ) {
    final now = DateTime.now();
    return transaction(() async {
      await (update(translationLines)
            ..where((t) =>
                t.transcriptId.equals(transcriptId) & t.deletedAt.isNull()))
          .write(TranslationLinesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      await batch((b) => b.insertAll(translationLines, lines));
    });
  }

  /// Retires [transcriptId]'s translation.
  Future<void> removeTranslation(String transcriptId) =>
      replaceTranslation(transcriptId, const []);

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
  }) {
    Value<T> maybe<T>(T? value) =>
        value == null ? const Value.absent() : Value(value);

    return (update(textLayers)..where((t) => t.id.equals(id))).write(
      TextLayersCompanion(
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
  ///
  /// The words are left live but unreachable, the same bargain
  /// [softDeleteClip] makes: every read path starts from the transcript, and a
  /// future sync wants the tombstone rather than a hole.
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
  ///
  /// The rows are cheap — a word is about a hundred bytes, so an hour of speech
  /// is roughly a megabyte — and copying them is what lets each duplicate carry
  /// its own edits. The alternative, one canonical transcript with per-project
  /// overlays, would turn every read into a merge to save that megabyte.
  ///
  /// The **edit history is deliberately not copied.** A duplicate starts with a
  /// clean slate: replaying the original's undo log against new rows would let
  /// an undo reach back past the moment the copy was made, which is not
  /// something the user could reason about.
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
          ),
        );

        // **Every** transcript on the clip, not just one. A clip covered by
        // two layers would otherwise lose all but the newest, and the
        // duplicate would show a timeline of layers with no words under most
        // of them.
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
                ),
            ]);
          });
        }
      }

      return newProjectId;
    });
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

  /// The projects [query] finds, newest first, re-run whenever a project, a
  /// transcript or a word changes.
  ///
  /// Empty for an empty query -- the caller shows the whole list instead.
  Stream<List<LibraryHit>> watchLibrarySearch(String query) {
    return customSelect(
      'SELECT 1',
      readsFrom: {projects, transcripts, words},
    ).watch().asyncMap((_) => searchLibrary(query));
  }

  /// Every project whose title, or whose transcribed words, contain [query].
  ///
  /// **Words, not `Transcripts.fullText`.** That column is written once when a
  /// transcript is made and never follows a correction, so searching it would
  /// find what the user fixed and miss what they fixed it to.
  ///
  /// Each project is listed once, with the first place its words say the
  /// query -- by transcript, then by position -- when they do.
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
      // A sentence placed on its own stays where it was put when its words
      // are retyped: the new words take the placement the old ones had.
      final placed = existing.firstOrNull;

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
  /// Retires or restores a clip.
  ///
  /// **Soft in both directions**, which is what makes a split reversible: the
  /// half a split created keeps its id, its position and the transcripts
  /// copied onto it while it is put away, so bringing it back restores the
  /// arrangement rather than rebuilding an approximation of it.
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

  /// Retires or restores a layer **and the transcripts it produced**.
  ///
  /// Mirrors [softDeleteLayer] rather than touching the layer row alone. An
  /// earlier version of this updated only `transcribe_layers`, so undoing a
  /// layer took its track off the timeline and left its captions on the video:
  /// the transcript rows were still live, and every caption read path starts
  /// from the transcript, not from the track. **An inverse that does less than
  /// the action it reverses is not an inverse.**
  ///
  /// Restoring brings back only the transcripts that went away *with* this
  /// layer, matched on the moment they were retired, so words discarded by an
  /// earlier rerun stay discarded instead of returning alongside the ones that
  /// replaced them. Timestamps are stored to the second, so two unrelated
  /// cascades over one layer inside the same second would be indistinguishable
  /// -- reachable only by undoing in the same second a rerun discarded, and the
  /// cost of being wrong is a stale transcript rather than a lost one.
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
  ///
  /// Takes ids rather than a layer because the run that wrote them knows which
  /// rows are its own. Undoing a rerun must not resurrect the words that rerun
  /// replaced, and a layer-wide sweep could not tell the two sets apart.
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
  ///
  /// Doing something new after an undo discards what was undone — the same
  /// rule [appendEditEvent] follows, and the one every editor follows, because
  /// the alternative is a redo that reapplies a change to a document it no
  /// longer fits.
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
  ///
  /// Read by project rather than by transcript because the history the user
  /// made is one sequence; which transcript a word edit landed on is an
  /// implementation detail of where it was stored.
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

  /// Whether the **project** has anything to undo or redo.
  ///
  /// Both logs at once. A trivial query declared as reading from all three
  /// tables is what makes this re-emit when either log changes -- drift
  /// invalidates a stream by the tables it was told about, not by what the SQL
  /// happens to select, and there is no need to read rows here that the two
  /// counts below already answer.
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
