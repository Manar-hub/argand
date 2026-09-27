import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
import '../../core/timeline/timeline_selection.dart';
import 'transcript_repository.dart';

part 'clip_controller.g.dart';

/// Containers offered when adding a clip.
///
/// The same set the import picker offers (`import_controller.dart`), shared so
/// the two entry points cannot drift into accepting different files — a format
/// the app can transcribe on import but not add to a timeline would be a
/// distinction with no reason behind it.
const mediaExtensions = [
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp',
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr',
];

/// Which clip the timeline and Script mode are currently showing.
///
/// **One selection per project**, held in memory rather than persisted: it is a
/// cursor, not a preference, and restoring yesterday's selection would be
/// arbitrary once clips have been added or removed since.
///
/// Null means nothing is selected — an empty project, or the moment after the
/// selected clip was removed. The timeline resolves null to the first clip when
/// one exists, which is why this stays deliberately dumb.
@riverpod
class SelectedClip extends _$SelectedClip {
  @override
  String? build(String projectId) => null;

  void select(String clipId) => state = clipId;

  void clear() => state = null;
}

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.
///
/// **Hidden means left out**, in the preview and in the export alike: a
/// hidden video track plays black, hidden audio is silent, and hidden
/// captions, texts, translation or images are not drawn or burned in --
/// whatever sits on a hidden track. What the preview shows is what the
/// export makes.
///
/// A session's view of the project, not a property of its data, so it is
/// held here rather than stored.
@Riverpod(keepAlive: true)
class HiddenTracks extends _$HiddenTracks {
  @override
  Set<String> build(String projectId) => const {};

  void toggle(String trackId) {
    state = state.contains(trackId)
        ? state.where((t) => t != trackId).toSet()
        : {...state, trackId};
  }

  void show(String trackId) {
    if (state.contains(trackId)) {
      state = state.where((t) => t != trackId).toSet();
    }
  }
}

/// Whether the video track, and the audio track, are hidden -- the two every
/// project has exactly one of.
typedef HiddenPlayback = ({bool video, bool audio});

HiddenPlayback hiddenPlaybackOf(Set<String> hidden, List<Track> tracks) {
  bool hides(TrackKind kind) => tracks.any(
        (t) => TrackKind.fromCode(t.kind) == kind && hidden.contains(t.id),
      );
  return (video: hides(TrackKind.video), audio: hides(TrackKind.audio));
}

@riverpod
HiddenPlayback hiddenPlayback(Ref ref, String projectId) => hiddenPlaybackOf(
      ref.watch(hiddenTracksProvider(projectId)),
      ref.watch(projectTracksProvider(projectId)).value ?? const [],
    );

/// Picture files offered when adding an image.
const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'];

/// How long an added image stays on screen, like a text.
const int defaultImageMs = 3000;

/// Opens the picker and puts the chosen picture on the timeline at
/// [atMs], on the first track free there. Returns its id, or null when the
/// picker was dismissed.
Future<String?> pickAndAddImage(
  TranscriptRepository repository, {
  required String projectId,
  required int atMs,
  required int totalMs,
}) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: imageExtensions,
  );
  if (picked == null) return null;
  // Never past the end: an image hanging off the project shows over nothing.
  final end = totalMs > 0
      ? (atMs + defaultImageMs).clamp(0, totalMs)
      : atMs + defaultImageMs;
  final start = end - atMs < 500 ? (end - defaultImageMs).clamp(0, end) : atMs;
  return repository.addImage(
    projectId: projectId,
    fileName: picked.name,
    bytes: picked.readAsByteStream(),
    startMs: start,
    endMs: end,
  );
}

/// Where the playhead sits, in project time.
///
/// **Lifted out of the track widget** because three things need it and only
/// one of them draws it: the ruler puts it on screen, the toolbar cuts there,
/// and the preview shows whatever it is over. Passing it down by constructor
/// reached the first two and never the third.
@riverpod
class TimelinePlayhead extends _$TimelinePlayhead {
  @override
  int build(String projectId) => 0;

  void moveTo(int projectMs) {
    final next = projectMs < 0 ? 0 : projectMs;
    if (next != state) state = next;
  }
}

/// Everything the editing tools will act on.
///
/// **One selection across every track**, replacing the separate "selected
/// clip" and "selected layer" the timeline used to keep. Those two could
/// disagree, and only one of them was ever reachable from the toolbar, which
/// is why Split could cut the video and nothing else.
///
/// Holds ids only; what they refer to is resolved against the rows that
/// currently exist, so a removed clip or a replaced row simply stops being
/// selected rather than leaving the tools pointing at nothing.
@riverpod
class TimelineSelection extends _$TimelineSelection {
  @override
  Set<TimelineItem> build(String projectId) => const {};

  TimelineMultiSelect get _multi =>
      ref.read(timelineMultiSelectProvider(projectId).notifier);

  /// A tap: picks this one, or toggles it while multi-selecting.
  void tap(TimelineItem item) => _set(
        tapSelection(
          state,
          item,
          multi: ref.read(timelineMultiSelectProvider(projectId)),
        ),
      );

  /// A long press: starts multi-select with this item toggled.
  void longPress(TimelineItem item) {
    _multi.enter();
    _set(longPressSelection(state, item));
  }

  void toggle(TimelineItem item) => _set(toggleSelection(state, item));

  void selectOnly(TimelineItem item) => _set({item});

  /// Selects [items] together, in multi-select -- a whole track's content,
  /// from a long press on its gutter or an empty spot on its lane.
  void selectAll(Set<TimelineItem> items) {
    if (items.isEmpty) return;
    _multi.enter();
    _set(items);
  }

  void clear() => _set(const {});

  /// Drops anything that no longer exists. Called with the rows in hand rather
  /// than querying, so it cannot race the stream that produced them.
  void prune({
    required Set<String> clipIds,
    required Set<String> layerIds,
    Set<String>? textIds,
  }) {
    final next = prunedSelection(
      state,
      clipIds: clipIds,
      layerIds: layerIds,
      textIds: textIds,
    );
    if (next.length != state.length) _set(next);
  }

  /// Every change goes through here, so an empty selection always ends
  /// multi-select: there is nothing left to add to.
  void _set(Set<TimelineItem> next) {
    state = next;
    if (next.isEmpty) _multi.exit();
  }
}

/// Whether taps on the timeline add to the selection rather than replace it.
///
/// Entered by a long press and left when the selection empties or the user
/// says Done. Its own provider rather than a field on [TimelineSelection],
/// whose value is the set that dozens of call sites already read.
@riverpod
class TimelineMultiSelect extends _$TimelineMultiSelect {
  @override
  bool build(String projectId) => false;

  void enter() => state = true;

  void exit() {
    if (state) state = false;
  }
}

/// Which clip both modes are actually showing.
///
/// [SelectedClip] holds what the user last tapped; this resolves it against
/// the clips that currently exist. Shared so Timeline and Script cannot
/// disagree about which clip is in front of the user — they are two views of
/// one selection, and a project whose filmstrip highlights one clip while the
/// transcript shows another would be incoherent.
///
/// Falls back to the first clip rather than to nothing, which is what keeps the
/// screen sensible after a removal: the selected clip can disappear from under
/// the user, and an empty view beside a full timeline would read as a bug.
/// Null only when the project genuinely has no clips.
@riverpod
String? resolvedSelectedClip(Ref ref, String projectId) {
  final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
  if (clips.isEmpty) return null;

  final selected = ref.watch(selectedClipProvider(projectId));
  if (selected != null && clips.any((clip) => clip.id == selected)) {
    return selected;
  }
  return clips.first.id;
}

/// What the "+" button is doing right now.
sealed class AddClipStatus {
  const AddClipStatus();
}

class AddClipIdle extends AddClipStatus {
  const AddClipIdle();
}

/// Copying the chosen file into the project.
///
/// A visible stage because a video runs to hundreds of megabytes and the copy
/// is not instant — but a short one, because **nothing is transcribed here**.
class AddClipCopying extends AddClipStatus {
  const AddClipCopying();
}

class AddClipFailed extends AddClipStatus {
  const AddClipFailed(this.error);

  final Object error;
}

/// Adds media to a project without transcribing it.
///
/// **This is the half of import that does not run the engine.** Picking a file
/// used to mean committing to minutes of whisper and diarization; a project
/// that holds several clips cannot work that way, because most of them are not
/// worth that cost until the user says so. So this copies the bytes in, probes
/// the duration and writes a row — seconds, not minutes — and transcription is
/// a separate, explicit act: drawing a transcribe layer and running it.
@riverpod
class AddClipController extends _$AddClipController {
  @override
  AddClipStatus build(String projectId) => const AddClipIdle();

  /// Opens the picker and adds the chosen file as the last clip.
  ///
  /// Returns the new clip's id, or null if the user dismissed the picker or the
  /// copy failed — the caller uses it to select what was just added.
  Future<String?> pickAndAdd() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: mediaExtensions,
    );
    // Dismissing the picker is not a failure and gets no error state: from the
    // user's side nothing happened.
    if (picked == null) return null;

    state = const AddClipCopying();
    try {
      final clip = await ref.read(transcriptRepositoryProvider).addClip(
            projectId: projectId,
            fileName: picked.name,
            bytes: picked.readAsByteStream(),
          );
      state = const AddClipIdle();
      return clip.id;
    } catch (error, stackTrace) {
      debugPrint('Could not add a clip to $projectId: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = AddClipFailed(error);
      return null;
    }
  }

  void reset() => state = const AddClipIdle();
}

/// Removing and reordering clips.
///
/// Separate from [AddClipController] because these need no status of their own:
/// both are immediate, both are driven straight off the clip stream, and
/// neither has a stage worth rendering.
@riverpod
ClipEditor clipEditor(Ref ref) => ClipEditor(
      ref.watch(transcriptRepositoryProvider),
    );

class ClipEditor {
  const ClipEditor(this._repository);

  final TranscriptRepository _repository;

  /// Removes [clipId] and its media. The transcript rows survive as tombstones
  /// — see [AppDatabase.softDeleteClip].
  Future<void> remove(String clipId) => _repository.removeClip(clipId);

  /// Moves the clip at [from] to [to], writing the whole resulting order.
  ///
  /// Takes the list it is reordering rather than reading it again, so the order
  /// written is exactly the one the user saw when they let go of the drag.
  Future<void> move({
    required String projectId,
    required List<MediaClip> clips,
    required int from,
    required int to,
  }) {
    final ids = [for (final clip in clips) clip.id];
    if (from < 0 || from >= ids.length) return Future.value();

    final moved = ids.removeAt(from);
    ids.insert(to.clamp(0, ids.length), moved);
    return _repository.reorderClips(projectId: projectId, orderedIds: ids);
  }
}

/// Total bytes one clip occupies, for the remove confirmation.
@riverpod
Future<int> clipMediaBytes(Ref ref, String projectId) =>
    ref.watch(mediaConverterProvider).projectMediaBytes(projectId);
