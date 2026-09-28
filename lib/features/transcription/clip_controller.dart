import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
import '../../core/timeline/timeline_selection.dart';
import 'transcript_repository.dart';

part 'clip_controller.g.dart';

/// Containers offered when adding a clip.
const mediaExtensions = [
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp',
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr',
];

/// Which clip the timeline and Script mode are currently showing.
@riverpod
class SelectedClip extends _$SelectedClip {
  @override
  String? build(String projectId) => null;

  void select(String clipId) => state = clipId;

  void clear() => state = null;
}

/// Which tracks the eye in the gutter has hidden, by `Tracks` row id.
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
class AddClipCopying extends AddClipStatus {
  const AddClipCopying();
}

class AddClipFailed extends AddClipStatus {
  const AddClipFailed(this.error);

  final Object error;
}

/// Adds media to a project without transcribing it.
@riverpod
class AddClipController extends _$AddClipController {
  @override
  AddClipStatus build(String projectId) => const AddClipIdle();

  /// Opens the picker and adds the chosen file as the last clip.
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
