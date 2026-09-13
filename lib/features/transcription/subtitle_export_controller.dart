import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/captions/caption_grouper.dart';
import '../../core/captions/subtitle_export.dart';
import 'transcript_repository.dart';

part 'subtitle_export_controller.g.dart';

sealed class SubtitleExportStatus {
  const SubtitleExportStatus();
}

class SubtitleExportIdle extends SubtitleExportStatus {
  const SubtitleExportIdle();
}

class SubtitleExportRunning extends SubtitleExportStatus {
  const SubtitleExportRunning();
}

class SubtitleExportSaved extends SubtitleExportStatus {
  const SubtitleExportSaved(this.fileName);

  /// Shown back to the user. The full destination is a `content://` URI on
  /// Android, which means nothing to anybody, so only the name is kept.
  final String fileName;
}

/// The user dismissed the system save dialog. Distinct from idle so the UI can
/// acknowledge the tap rather than appearing to have ignored it -- the same
/// distinction [ImportCancelled] makes.
class SubtitleExportCancelled extends SubtitleExportStatus {
  const SubtitleExportCancelled();
}

class SubtitleExportFailed extends SubtitleExportStatus {
  const SubtitleExportFailed(this.error);

  final Object error;
}

/// The transcript has no words, so there is nothing to write.
///
/// Reachable: an import whose engine run returned nothing still creates a
/// transcript row. Caught before the save dialog opens, because asking someone
/// to choose a destination for an empty file wastes two taps and then puts a
/// header-only `.vtt` on their device.
class SubtitleExportEmpty extends SubtitleExportStatus {
  const SubtitleExportEmpty();
}

/// Writes a transcript out as a subtitle file.
///
/// **Nothing here is gated.** A subtitle file is the user's own transcript in a
/// different wrapper, and CLAUDE.md §2 puts every such container on the free
/// side of the line — the paid tier begins at professional interchange formats,
/// which these are not.
///
/// Cues are regrouped from the words at export time rather than read from
/// anywhere cached, exactly as the on-screen captions are. The file therefore
/// always reflects the latest correction, including one made and then undone a
/// moment earlier.
@riverpod
class SubtitleExporter extends _$SubtitleExporter {
  @override
  SubtitleExportStatus build() => const SubtitleExportIdle();

  void reset() => state = const SubtitleExportIdle();

  /// Groups [transcriptId] into cues, serialises them, and hands the bytes to
  /// the system save dialog.
  ///
  /// [speakerLabel] comes from the widget layer because "Speaker 1" is
  /// interface text (CLAUDE.md §4). Pass null to write a file with no
  /// attribution.
  Future<void> export({
    required String transcriptId,
    required String title,
    required String language,
    required SubtitleFormat format,
    String Function(int speaker)? speakerLabel,
  }) async {
    state = const SubtitleExportRunning();

    try {
      final words = await ref.read(transcriptRepositoryProvider)
          .watchWords(transcriptId)
          .first;

      if (words.isEmpty) {
        state = const SubtitleExportEmpty();
        return;
      }

      final content = formatSubtitles(
        groupIntoCues(words),
        format: format,
        speakerLabel: speakerLabel,
      );

      final fileName = subtitleFileName(
        title: title,
        language: language,
        format: format,
      );

      // Android's Storage Access Framework: the user picks the destination, so
      // the app needs no storage permission and the file lands somewhere they
      // can actually find. Returns null when the dialog is dismissed.
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        // UTF-8 without a BOM. Players expect it, and a BOM shows up as stray
        // characters ahead of the first cue number in some SubRip readers.
        bytes: Uint8List.fromList(utf8.encode(content)),
        mimeType: format.mimeType,
      );

      state = saved == null
          ? const SubtitleExportCancelled()
          : SubtitleExportSaved(fileName);
    } catch (error, stackTrace) {
      debugPrint('Subtitle export failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = SubtitleExportFailed(error);
    }
  }
}

/// A filename a file manager will accept, on any platform.
///
/// The language code is included because the convention for subtitle files is
/// `name.en.srt`, and players and media servers read it to label a track. That
/// code is only meaningful now that the engine reports the language it actually
/// used rather than echoing back the request.
String subtitleFileName({
  required String title,
  required String language,
  required SubtitleFormat format,
}) {
  // Windows forbids the first set outright; the control characters and
  // trailing dots and spaces are the rest of what makes a name unopenable
  // there. Stripped everywhere rather than per platform, because an exported
  // file is meant to travel.
  final cleaned = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');

  // Long titles come from filenames, which can be very long; 80 characters
  // leaves room for the suffixes under the usual 255-byte limit.
  final base = cleaned.isEmpty
      ? 'transcript'
      : (cleaned.length > 80 ? cleaned.substring(0, 80).trimRight() : cleaned);

  final tag = language.trim().isEmpty ? '' : '.${language.trim()}';
  return '$base$tag.${format.extension}';
}
