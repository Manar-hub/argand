import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter/painting.dart' show Color;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/captions/caption_cue.dart';
import '../../core/captions/project_cues.dart';
import '../../core/captions/subtitle_export.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/transcript/speaker_names.dart';
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

/// Nothing on the timeline has been transcribed, so there is nothing to write.
class SubtitleExportEmpty extends SubtitleExportStatus {
  const SubtitleExportEmpty();
}

/// Writes a transcript out as a subtitle file.
@riverpod
class SubtitleExporter extends _$SubtitleExporter {
  @override
  SubtitleExportStatus build() => const SubtitleExportIdle();

  void reset() => state = const SubtitleExportIdle();

  /// Writes the project's captions out as [format], through the system save
  /// dialog.
  Future<void> export({
    required String projectId,
    required SubtitleFormat format,
    SubtitleLineLength lineLength = SubtitleLineLength.standard,
    String Function(int speaker)? defaultSpeakerLabel,
    bool includeTranslation = false,
  }) async {
    state = const SubtitleExportRunning();

    try {
      final repository = ref.read(transcriptRepositoryProvider);

      // Straight from the repository, for the reason the video export gives:
      // the clip providers may not have emitted yet, and an empty timeline
      // beside a full clip list would write an empty file.
      final clips = await repository.clipsForProject(projectId);
      final timeline = ProjectTimeline.fromClips(clips);

      final wordsByClip = <String, List<Word>>{};
      final namesByTranscript = <String, SpeakerNames>{};
      final translationsByTranscript = <String, List<TranslationLine>>{};
      String? language;

      for (final placement in timeline.placements) {
        final transcripts =
            await repository.transcriptsForClip(placement.clipId);
        final words = <Word>[];

        for (final transcript in transcripts) {
          words.addAll(await repository.watchWords(transcript.id).first);
          namesByTranscript[transcript.id] =
              SpeakerNames.decode(transcript.speakerNames);
          if (includeTranslation) {
            translationsByTranscript[transcript.id] =
                await repository.watchTranslation(transcript.id).first;
          }
          // The first language the timeline reaches, which is what the file
          // name should claim: players label the track from it.
          language ??= transcript.language;
        }

        if (words.isNotEmpty) wordsByClip[placement.clipId] = words;
      }

      final cues = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: wordsByClip,
      );

      if (cues.isEmpty) {
        state = const SubtitleExportEmpty();
        return;
      }

      final fallback = defaultSpeakerLabel;
      final content = formatSubtitles(
        cues,
        format: format,
        options: SubtitleOptions(maxLineCharacters: lineLength.maxCharacters),
        // The translated sentence being said when the cue starts, so it is on
        // screen for as long as its stretch of speech is. By time, because a
        // translation's sentences need not match the source's.
        translation: includeTranslation
            ? (CaptionCue cue) {
                final word = cue.words.first;
                return translationsByTranscript[word.transcriptId]
                    ?.where((line) =>
                        line.startMs <= word.startMs &&
                        line.endMs > word.startMs)
                    .firstOrNull
                    ?.content;
              }
            : null,
        // Named from the transcript the cue's own words belong to. The same
        // speaker number is a different person in a different run, so a
        // project-wide name map would put one person's name on another.
        // ASS styles each speaker in their colour: their own, or the palette's.
        colorOf: (CaptionCue cue) => SpeakerPalette.colorFor(
          cue.speaker,
          fallback: const Color(0xFFFFFFFF),
          custom: namesByTranscript[cue.words.first.transcriptId]
              ?.colorOf(cue.speaker),
        ).toARGB32(),
        speakerLabel: fallback == null
            ? null
            : (CaptionCue cue) {
                final speaker = cue.speaker!;
                final names = namesByTranscript[cue.words.first.transcriptId];
                final byDefault = fallback(speaker);
                return names?.labelFor(speaker, defaultLabel: byDefault) ??
                    byDefault;
              },
      );

      final project = await repository.findProject(projectId);
      final fileName = subtitleFileName(
        title: project?.title ?? '',
        language: language ?? '',
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
String subtitleFileName({
  required String title,
  required String language,
  required SubtitleFormat format,
}) {
  // Windows forbids the first set outright; the control characters and trailing
  // dots and spaces are the rest of what makes a name unopenable there.
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
