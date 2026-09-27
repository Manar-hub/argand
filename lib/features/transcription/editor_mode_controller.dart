import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';

part 'editor_mode_controller.g.dart';

/// The two ways the editing screen can be arranged.
///
/// Script mode is the transcript-first view the app already had: video
/// small, transcript dominant. Timeline mode is the clip/track view. Both
/// read the same project and the same media -- switching between them is a
/// layout choice, not a different screen or a different pipeline run.
enum EditorMode { script, timeline }

/// The `Settings` key holding which [EditorMode] a project was last opened
/// in, namespaced the same way [playbackPositionKey] is (one shared
/// key/value table, so every per-project key needs its own prefix).
String editorModeKey(String projectId) => 'project.$projectId.editorMode';

/// Reads the mode [projectId] was last opened in, or null if none was ever
/// recorded -- a fresh project, or one opened only through the entry point
/// that already knows which mode to show.
Future<EditorMode?> readStoredEditorMode(AppDatabase db, String projectId) async {
  final stored = await db.readSetting(editorModeKey(projectId));
  return switch (stored) {
    'timeline' => EditorMode.timeline,
    'script' => EditorMode.script,
    _ => null,
  };
}

/// Which mode [projectId]'s editing screen is currently showing.
///
/// Starts at [EditorMode.script] -- the least surprising default, and the
/// only mode every project opened in before Timeline mode existed.
/// `ProjectScreen` overrides this once, in `initState`, either from the entry
/// point that was tapped (import-and-edit vs. transcribe) or, for a project
/// reopened from the library list, from whichever mode was last recorded for
/// it via [select].
/// Whether Script mode shows each sentence's translation under it. Off until
/// asked for; kept for the session, across projects.
@Riverpod(keepAlive: true)
class ShowTranslation extends _$ShowTranslation {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

@riverpod
class SessionEditorMode extends _$SessionEditorMode {
  @override
  EditorMode build(String projectId) => EditorMode.script;

  /// Switches mode and remembers it, so reopening this project later lands
  /// back where it was left. Fire-and-forget, the same as
  /// `MediaPlayer._write` -- a session-mode switch is not worth blocking a
  /// frame on.
  void select(EditorMode mode) {
    if (state == mode) return;
    state = mode;
    ref.read(appDatabaseProvider).writeSetting(editorModeKey(projectId), mode.name);
  }
}
