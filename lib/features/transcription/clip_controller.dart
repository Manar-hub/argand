import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
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
/// a separate, explicit act (`ClipTranscriptionController`).
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
