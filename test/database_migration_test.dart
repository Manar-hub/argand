import 'package:argand/core/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The schema-2 tables, written by hand so the migration is exercised against a
/// database this build did not create.
///
/// Left at **2** deliberately as the schema grows: upgrading from the oldest
/// version anyone can still be running exercises every `if (from < n)` block in
/// order, which is the case a device that skipped releases actually hits.
///
/// Verbose on purpose. `createAll()` would produce schema 3 and the upgrade
/// path would never run -- which is exactly the path that touches a real user's
/// transcripts, and the only one that can destroy them.
const _schemaV2 = [
  '''
  CREATE TABLE projects (
    id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    title TEXT NOT NULL,
    media_path TEXT NOT NULL,
    duration_ms INTEGER NULL,
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE transcripts (
    id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    project_id TEXT NOT NULL REFERENCES projects (id),
    language TEXT NOT NULL DEFAULT 'en',
    full_text TEXT NOT NULL,
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE words (
    id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    transcript_id TEXT NOT NULL REFERENCES transcripts (id),
    position INTEGER NOT NULL,
    word TEXT NOT NULL,
    start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL,
    speaker_id TEXT NULL,
    PRIMARY KEY (id)
  )''',
  'CREATE INDEX words_transcript_start ON words (transcript_id, start_ms)',
  '''
  CREATE TABLE settings (
    id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER NULL,
    "key" TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY (id)
  )''',
  'CREATE UNIQUE INDEX settings_key ON settings ("key")',
  'PRAGMA user_version = 2',
];

void main() {
  /// Opens a database already holding one project, transcript, word and
  /// setting at schema 2. Drift sees `user_version = 2` and runs `onUpgrade`.
  AppDatabase openV2WithData() {
    return AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final statement in _schemaV2) {
            raw.execute(statement);
          }

          const stamp = 1757000000;
          raw.execute(
            'INSERT INTO projects (id, created_at, updated_at, title, '
            'media_path, duration_ms) VALUES (?, ?, ?, ?, ?, ?)',
            ['p1', stamp, stamp, 'interview', '/media/p1/clip.mp4', 61000],
          );
          raw.execute(
            'INSERT INTO transcripts (id, created_at, updated_at, project_id, '
            'language, full_text) VALUES (?, ?, ?, ?, ?, ?)',
            ['t1', stamp, stamp, 'p1', 'en', 'hello there'],
          );
          raw.execute(
            'INSERT INTO words (id, created_at, updated_at, transcript_id, '
            'position, word, start_ms, end_ms, speaker_id) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            ['w1', stamp, stamp, 't1', 0, 'hello', 0, 400, '0'],
          );
          raw.execute(
            'INSERT INTO settings (id, created_at, updated_at, "key", value) '
            'VALUES (?, ?, ?, ?, ?)',
            ['s1', stamp, stamp, 'whisper.model', 'base'],
          );
        },
      ),
    );
  }

  group('schema 2 -> 9', () {
    test('keeps every existing row', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      // The first query is what triggers the migration.
      final project = await db.findProject('p1');
      expect(project, isNotNull);
      expect(project!.title, 'interview');
      expect(project.mediaPath, '/media/p1/clip.mp4');
      expect(project.durationMs, 61000);

      final transcript = await db.findTranscriptForProject('p1');
      expect(transcript!.fullText, 'hello there');
      expect(transcript.language, 'en');

      final words = await db.watchWords('t1').first;
      expect(words.single.word, 'hello');
      expect(words.single.speakerId, '0');
      expect(words.single.startMs, 0);
      expect(words.single.endMs, 400);

      // A settings row written by the older build must still be readable, not
      // shadowed by a fresh table.
      expect(await db.readSetting('whisper.model'), 'base');
    });

    test('adds a usable edit log to the upgraded database', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      // Nothing to undo yet: the table exists but an upgraded install has no
      // history, which is the honest state -- edits made before this release
      // were never recorded.
      expect(
        await db.watchEditHistory('t1').first,
        (canUndo: false, canRedo: false),
      );

      await db.appendEditEvent(
        transcriptId: 't1',
        kind: 'wordText',
        payload: '{"wordId":"w1","before":"hello","after":"Hello"}',
      );

      expect(
        await db.watchEditHistory('t1').first,
        (canUndo: true, canRedo: false),
      );
      expect(await db.nextUndoEvent('t1'), isNotNull);
    });

    test('adds the speaker names column, empty', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      // Present and null: a transcript from before the column existed has
      // nobody renamed, which is exactly what null means.
      final transcript = await db.findTranscript('t1');
      expect(transcript, isNotNull);
      expect(transcript!.speakerNames, isNull);

      await db.writeSpeakerNames('t1', '{"0":{"name":"Ana"}}');
      expect(
        (await db.findTranscript('t1'))!.speakerNames,
        '{"0":{"name":"Ana"}}',
      );
    });

    test('reports the new schema version', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      await db.findProject('p1');
      final row = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();

      expect(row, 9);
    });

    test('gives the existing transcript the layer its clip always implied',
        () async {
      final db = openV2WithData();
      addTearDown(db.close);

      final clip = (await db.clipsForProject('p1')).single;

      // Without this an already-transcribed project opens showing an empty
      // layer track beside a full transcript, and the obvious response is to
      // draw a layer over the whole thing and transcribe it a second time.
      final layers = await db.layersForProject('p1');
      expect(layers, hasLength(1));
      expect(layers.single.startMs, 0);
      expect(layers.single.endMs, 61000,
          reason: 'the layer spans the clip it covers');
      expect(layers.single.trackIndex, 0);

      final transcript = await db.findTranscript('t1');
      expect(transcript!.layerId, layers.single.id);
      // The range is recorded as a fact about audio, so a later reorder cannot
      // relabel words the user has already corrected.
      expect(transcript.clipStartMs, 0);
      expect(transcript.clipEndMs, 61000);
      expect(transcript.clipId, clip.id);
    });

    test('gives the project the clip its media always implied', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      final clips = await db.clipsForProject('p1');
      expect(clips, hasLength(1),
          reason: 'a project that held one file becomes a project of one clip');

      final clip = clips.single;
      expect(clip.mediaPath, '/media/p1/clip.mp4',
          reason: 'the path moves to the clip verbatim -- no file is relocated');
      expect(clip.durationMs, 61000);
      expect(clip.position, 0);
      expect(clip.projectId, 'p1');
    });

    test('leaves the audio lane uncomputed rather than back-filling it',
        () async {
      final db = openV2WithData();
      addTearDown(db.close);

      final clip = (await db.clipsForProject('p1')).single;

      // Deliberately null. Deriving these needs a full native decode per clip,
      // so back-filling a library during a migration would block the first
      // launch after an update for minutes. Null already means "not computed
      // yet", and the timeline fills it in on first sight -- the same path a
      // newly added clip takes.
      expect(clip.waveform, isNull);
    });

    test('the timeline history arrives, and is empty', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      // A whole table rather than a column, so it needs no version pairing --
      // but it does have to actually be created on an upgrade, which is the
      // failure `createTable` not running would produce silently.
      final events = await db.select(db.timelineEvents).get();
      expect(events, isEmpty);
    });

    test('an upgraded clip is untrimmed, not trimmed to zero', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      final clip = (await db.clipsForProject('p1')).single;

      // Null is what "never trimmed" means, and it is why schema 8 needed no
      // backfill. Writing 0 and the duration instead would make an untouched
      // clip indistinguishable from one deliberately trimmed to its full
      // length -- and would break for a clip whose duration never probed.
      expect(clip.trimStartMs, isNull);
      expect(clip.trimEndMs, isNull);
    });

    test('points the existing transcript at the back-filled clip', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      final clip = (await db.clipsForProject('p1')).single;

      // The link the whole multi-clip model hangs on. Without it the words a
      // user has already corrected would belong to no clip and show nowhere.
      final transcript = await db.findTranscript('t1');
      expect(transcript!.clipId, clip.id);

      expect((await db.transcriptsForClip(clip.id)).first.id, 't1');
      expect((await db.watchTranscriptsForClip(clip.id).first).first.id, 't1');
    });

    test('media refcounting still sees the migrated file', () async {
      final db = openV2WithData();
      addTearDown(db.close);

      await db.findProject('p1');

      // Nothing else points at it, so deleting p1 may reclaim the bytes.
      expect(
        await db.projectsSharingMedia('/media/p1/clip.mp4', excluding: 'p1'),
        0,
      );

      // A duplicate shares the file, and the count has to notice -- this is
      // what stops one project's deletion destroying the other's video.
      await db.duplicateProject(
        sourceProjectId: 'p1',
        newProjectId: 'p2',
        title: 'interview copy',
        newId: () => 'copy-${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(
        await db.projectsSharingMedia('/media/p1/clip.mp4', excluding: 'p1'),
        1,
      );

      // And the copy carries the clip and its words, not just the row.
      final copied = await db.clipsForProject('p2');
      expect(copied.single.mediaPath, '/media/p1/clip.mp4');
      final copiedTranscript = (await db.transcriptsForClip(copied.single.id)).firstOrNull;
      expect(copiedTranscript, isNotNull);
      expect(await db.watchWords(copiedTranscript!.id).first, hasLength(1));
    });
  });

  test('a fresh install lands on the same schema as an upgraded one', () async {
    final upgraded = openV2WithData();
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(upgraded.close);
    addTearDown(fresh.close);

    // Indexes as well as tables. `createTable` emits a table's declared
    // indexes on the upgrade path too, so an index that exists on only one
    // route is real drift -- and an index is exactly the kind of thing that
    // goes missing silently, costing query speed rather than correctness.
    Future<List<String>> schemaOf(AppDatabase db) async {
      final rows = await db
          .customSelect(
            "SELECT type || ':' || name AS entry FROM sqlite_master "
            "WHERE type IN ('table', 'index') AND name NOT LIKE 'sqlite_%' "
            'ORDER BY entry',
          )
          .map((r) => r.read<String>('entry'))
          .get();
      return rows;
    }

    // `onCreate` runs `createAll()` and does not replay `onUpgrade`, so the two
    // routes can silently drift apart. This is the assertion that catches it.
    await upgraded.findProject('p1');
    expect(await schemaOf(upgraded), await schemaOf(fresh));
  });
}
