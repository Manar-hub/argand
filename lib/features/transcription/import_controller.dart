import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/media/media_converter.dart';
import '../../core/media/shared_media.dart';
import '../../core/translation/translator.dart';
import 'transcript_repository.dart';
import 'transcription_run.dart';

part 'import_controller.g.dart';

/// Steps the import pipeline moves through, in order. The UI maps these to
/// localized labels; the controller never holds display strings itself.
///
/// Silence skipping does not appear here: it is a parameter of the transcribe
/// call rather than a pass over the audio, so it happens inside
/// [transcribing] rather than before it.
///
/// [identifyingSpeakers] is skipped when the setting is off, so this is the
/// order stages appear in, not a sequence every import runs in full.
enum ImportStage {
  preparingModel,
  copyingMedia,
  extractingAudio,
  transcribing,
  identifyingSpeakers,
  saving,

  /// The Transcribe sheet's "Translate to" is set: the words are saved and
  /// are now being translated beside them.
  translating,
}

sealed class ImportStatus {
  const ImportStatus();
}

class ImportIdle extends ImportStatus {
  const ImportIdle();
}

/// User dismissed the picker without choosing anything. Distinct from idle so
/// the UI can acknowledge the tap instead of appearing to have ignored it.
class ImportCancelled extends ImportStatus {
  const ImportCancelled();
}

class ImportRunning extends ImportStatus {
  const ImportRunning(this.stage, {this.percent});

  final ImportStage stage;

  /// Only populated during [ImportStage.transcribing], where the engine
  /// reports real progress. Null elsewhere, meaning "indeterminate".
  final int? percent;
}

class ImportSucceeded extends ImportStatus {
  const ImportSucceeded(this.projectId);

  final String projectId;
}

class ImportFailed extends ImportStatus {
  const ImportFailed(this.error);

  final Object error;
}

/// Drives one media file from the picker all the way to persisted words.
///
/// Every step that touches the filesystem or the engine lives here rather
/// than in a widget, so the import screen can be redesigned without moving
/// any of this logic (CLAUDE.md 4).
@riverpod
class ImportController extends _$ImportController {
  @override
  ImportStatus build() => const ImportIdle();

  /// Containers offered in the picker.
  ///
  /// [FileType.custom] rather than one of the presets because none of them
  /// covers this app's actual input set: `FileType.media` means video *and
  /// images* while excluding audio outright, and `FileType.audio` drops video.
  /// Android resolves these extensions to MIME types through its own
  /// `MimeTypeMap`, which does know `.mov`.
  static const _mediaExtensions = [
    'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp',
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr',
  ];

  /// Opens the system picker and runs the full pipeline on the chosen file.
  Future<void> importFromPicker() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _mediaExtensions,
    );
    if (picked == null) {
      state = const ImportCancelled();
      return;
    }
    await _run(
      fileName: picked.name,
      copyIn: (converter, projectId, clipId) => converter.importToAppStorage(
        projectId: projectId,
        clipId: clipId,
        fileName: picked.name,
        bytes: picked.readAsByteStream(),
      ),
    );
  }

  /// Runs the pipeline on a file handed over by the system share sheet.
  ///
  /// The bytes are already out of the content provider by the time this is
  /// called -- native does that, because a `content://` URI has no filesystem
  /// path and its read grant is revocable. What is left is a real file in the
  /// cache directory, which the import **adopts** rather than copies: it is
  /// about to be moved into the project, and writing a video twice to save a
  /// rename would be a poor trade on a phone.
  Future<void> importShared(SharedMedia media) async {
    state = const ImportRunning(ImportStage.copyingMedia);

    final String? cached;
    try {
      cached = await ref.read(sharedMediaChannelProvider).copy(media);
    } catch (error, stackTrace) {
      debugPrint('Could not read the shared file: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = ImportFailed(error);
      return;
    }

    if (cached == null) {
      // The provider gave us nothing. Treated as a cancellation rather than a
      // failure: from the user's side nothing happened, and an error banner for
      // a share they may have dismissed would be noise.
      state = const ImportCancelled();
      return;
    }

    await _run(
      fileName: media.name,
      copyIn: (converter, projectId, clipId) => converter.adoptIntoAppStorage(
        projectId: projectId,
        clipId: clipId,
        fileName: media.name,
        source: File(cached!),
      ),
    );
  }

  /// Translates what was just saved when the Transcribe sheet asked for it.
  ///
  /// **Never fails the import.** The transcription is saved and is what was
  /// asked for first; a translation that could not run -- no connection for
  /// the pack, say -- is one tap away on the captions afterwards.
  Future<void> _translateIfAsked(
    TranscriptRepository repository,
    List<String> transcriptIds,
  ) async {
    final to = await ref.read(translationTargetProvider.future);
    if (to == null || transcriptIds.isEmpty) return;
    state = const ImportRunning(ImportStage.translating);
    final failure = await repository.translateAll(
      transcriptIds: transcriptIds,
      to: to,
      translator: ref.read(translatorProvider),
    );
    if (failure != null) debugPrint('Translation after import: $failure');
  }

  /// Resets a finished or failed run so the UI returns to its resting state.
  void reset() => state = const ImportIdle();

  /// The pipeline, once the media is identified.
  ///
  /// [copyIn] is injected because the two entry points get the bytes into the
  /// project differently -- the picker streams them out of a URI, a share moves
  /// a file native has already written -- while everything after that point is
  /// identical and must stay that way.
  Future<void> _run({
    required String fileName,
    required Future<File> Function(
            MediaConverter, String projectId, String clipId)
        copyIn,
  }) async {
    final repository = ref.read(transcriptRepositoryProvider);
    final converter = ref.read(mediaConverterProvider);

    final projectId = repository.newId();
    // Minted alongside the project because the media directory is keyed by
    // both, and the copy has to land somewhere before any row exists.
    final clipId = repository.newId();

    try {
      state = const ImportRunning(ImportStage.copyingMedia);
      final media = await copyIn(converter, projectId, clipId);
      final duration = await converter.probeDuration(media.path);

      // The engine sequence itself lives in TranscriptionRunner, shared with
      // the on-demand path that transcribes a clip added later.
      final outcome = await TranscriptionRunner(ref).run(
        mediaPath: media.path,
        onStage: (stage, {int? percent}) {
          state = ImportRunning(stage, percent: percent);
        },
      );

      state = const ImportRunning(ImportStage.saving);
      await repository.saveImport(
        projectId: projectId,
        clipId: clipId,
        title: p.basenameWithoutExtension(fileName),
        mediaPath: media.path,
        duration: duration,
        language: outcome.language,
        speakerSpans: outcome.speakerSpans,
        result: outcome.result,
      );

      await _translateIfAsked(repository, [
        for (final transcript in await repository.transcriptsForClip(clipId))
          transcript.id,
      ]);

      state = ImportSucceeded(projectId);
    } catch (error) {
      // Nothing was committed to the database yet -- saveImport is the last
      // step and runs in a transaction -- so rolling back means dropping the
      // copied media, otherwise a failed import leaks a few hundred MB.
      // Guarded so a cleanup failure cannot replace the error worth reporting.
      try {
        await converter.discardProjectMedia(projectId);
      } catch (_) {
        // Ignored: the original failure below is the one the user needs.
      }
      state = ImportFailed(error);
    }
  }

}
