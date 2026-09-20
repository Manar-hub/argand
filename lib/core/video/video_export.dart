import 'package:flutter/services.dart';

import '../captions/caption_grouper.dart';
import '../captions/speaker_palette.dart';
import '../database/database.dart';
import '../timeline/project_timeline.dart';

/// One caption as the renderer needs it: when to show it, what it says, and
/// what colour the speaker is.
///
/// Times are **relative to the clip**, not to the project. Word timings are
/// already stored that way -- `saveClipTranscript` applies its offset in one
/// place -- and Media3 gives every item in a sequence its own presentation
/// timebase, so the two agree without any conversion here.
typedef ExportCaption = ({int startMs, int endMs, String text, int colorArgb});

/// One clip to render, with whatever captions belong on top of it.
typedef ExportClip = ({String path, List<ExportCaption> captions});

/// What to render, and how long the result should be.
///
/// [totalMs] is carried so the caller can check the file it got back against
/// the timeline it asked for. A render that silently drops a clip still
/// produces a playable MP4, and duration is the cheapest thing that catches it.
typedef ExportRequest = ({List<ExportClip> clips, int totalMs});

/// The captions to burn over one clip, grouped from its words.
///
/// **Reuses `groupIntoCues` and `SpeakerPalette` rather than grouping again.**
/// Burned captions have to break and colour exactly as the preview does, and
/// the only way to guarantee that is for both to come from the same rule --
/// a second implementation here would drift the moment either was tuned.
///
/// Words may arrive from several transcripts when more than one transcribe
/// layer covers the clip, so they are sorted before grouping; `groupIntoCues`
/// expects transcript order and would otherwise break cues at the seam.
List<ExportCaption> exportCaptionsFor(
  List<Word> words, {
  Color fallback = const Color(0xFFFFFFFF),
}) {
  if (words.isEmpty) return const [];

  final ordered = [...words]..sort((a, b) => a.startMs.compareTo(b.startMs));

  return [
    for (final cue in groupIntoCues(ordered))
      (
        startMs: cue.startMs,
        endMs: cue.endMs,
        text: cue.text,
        colorArgb:
            SpeakerPalette.colorFor(cue.speaker, fallback: fallback).toARGB32(),
      ),
  ];
}

/// Builds the export request for a project, in timeline order.
///
/// **Order comes from [ProjectTimeline], not from the clip list.** The timeline
/// is already the single copy of the running sum that the ruler, the track and
/// the playhead all measure with; deriving order here a second way is exactly
/// the drift that made the ruler and the track disagree once before.
///
/// Returns null when there is nothing renderable. Null rather than an empty
/// request because the two mean different things to the caller: an empty
/// request would be handed to the encoder and fail there, while null is
/// answerable in the UI without starting anything.
///
/// A placement whose clip is missing from [clips] also yields null. The
/// alternative — rendering the clips that *are* present — produces a video
/// silently shorter than the timeline, which is worse than refusing, because
/// nothing about the result says a clip was dropped.
///
/// [captionsByClip] is keyed by clip id; a clip absent from it simply renders
/// without captions, which is what an untranscribed clip should do.
ExportRequest? exportRequestFor({
  required ProjectTimeline timeline,
  required List<MediaClip> clips,
  Map<String, List<ExportCaption>> captionsByClip = const {},
}) {
  if (timeline.placements.isEmpty) return null;

  final paths = <String, String>{
    for (final clip in clips) clip.id: clip.mediaPath,
  };

  final ordered = <ExportClip>[];
  for (final placement in timeline.placements) {
    // A zero-length placement contributes no frames and no samples. Passing it
    // to the encoder as an empty item is a failure on some codecs and a no-op
    // on others, and neither is worth the inconsistency.
    if (placement.durationMs <= 0) continue;

    final path = paths[placement.clipId];
    if (path == null) return null;
    ordered.add((
      path: path,
      captions: captionsByClip[placement.clipId] ?? const [],
    ));
  }

  if (ordered.isEmpty) return null;
  return (clips: ordered, totalMs: timeline.totalMs);
}

/// A rendered video, as the device's Downloads collection recorded it.
///
/// [sizeBytes] comes back from the store rather than from what was written:
/// that is what shows the bytes actually landed, not merely that a row was
/// created for them.
typedef ExportedVideo = ({
  String name,
  String location,
  String uri,
  int sizeBytes,
  int durationMs,
  int width,
  int height,
});

/// Characters Android will not accept in a file name, plus the separators that
/// would turn a title into a path.
final _illegalInFileName = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
final _runsOfSpace = RegExp(r'\s+');

/// Longest stem kept from a project title.
///
/// Comfortably inside every filesystem limit while leaving room for the
/// timestamp and extension, and long enough that a title is still recognisable
/// in a folder listing.
const int maxExportStemLength = 60;

/// Builds the name a rendered video is saved under.
///
/// **The project's own title, not its id.** Downloads is somewhere a person
/// looks; a UUID there is unreadable. The timestamp keeps successive renders
/// of one project apart and orders them.
String exportFileName({required String projectTitle, required DateTime at}) {
  var stem = projectTitle
      .replaceAll(_illegalInFileName, ' ')
      .replaceAll(_runsOfSpace, ' ')
      .trim();

  // Leading dots hide the file on Android, which for something the user asked
  // to be given is the opposite of the intent.
  while (stem.startsWith('.')) {
    stem = stem.substring(1).trim();
  }

  if (stem.length > maxExportStemLength) {
    stem = stem.substring(0, maxExportStemLength).trim();
  }
  if (stem.isEmpty) stem = 'argand';

  final stamp = '${at.year.toString().padLeft(4, '0')}'
      '${at.month.toString().padLeft(2, '0')}'
      '${at.day.toString().padLeft(2, '0')}'
      '-${at.hour.toString().padLeft(2, '0')}'
      '${at.minute.toString().padLeft(2, '0')}'
      '${at.second.toString().padLeft(2, '0')}';

  return '$stem $stamp.mp4';
}

/// Renders a project's clips into one MP4 through Media3 `Transformer`.
///
/// A **MethodChannel** to native Kotlin, the mechanism CLAUDE.md §8 names for
/// platform work, and the same shape `ThumbnailService` uses. Nothing about the
/// render happens in Dart: the native side owns the encoder, and this is the
/// request and the progress coming back.
///
/// Progress arrives as calls *from* native rather than on a stream, because
/// `Transformer` has no progress callback of its own — the Kotlin side polls it
/// and forwards each reading.
class VideoExporter {
  const VideoExporter();

  static const _channel = MethodChannel('argand/video_export');

  /// Renders [clipPaths] end to end and saves the result as [fileName].
  ///
  /// **Dart names the file; the platform chooses where it goes.** From API 29
  /// the Downloads collection is owned by MediaStore and has no filesystem
  /// path to pass down, so a caller that insisted on one would be describing a
  /// location that does not exist.
  ///
  /// [onProgress] receives whole percentages, which is all `Transformer`
  /// reports.
  Future<ExportedVideo> export({
    required List<ExportClip> clips,
    required String fileName,
    void Function(int percent)? onProgress,
  }) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && onProgress != null) {
        final percent = call.arguments;
        if (percent is int) onProgress(percent);
      }
      return null;
    });

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('export', {
        'clips': [
          for (final clip in clips)
            {
              'path': clip.path,
              'captions': [
                for (final caption in clip.captions)
                  {
                    'startMs': caption.startMs,
                    'endMs': caption.endMs,
                    'text': caption.text,
                    'colorArgb': caption.colorArgb,
                  },
              ],
            },
        ],
        'fileName': fileName,
      });
      // The native side answers with what the store recorded. Falling back to
      // what was requested would paper over a contract change rather than
      // surface it, so a missing answer is an error.
      if (result == null) {
        throw const VideoExportException('The export returned no file.');
      }

      final size = result['sizeBytes'];
      final bytes = size is int ? size : 0;
      if (bytes <= 0) {
        // A row with no bytes is the failure worth naming: the file appears in
        // Downloads and plays as nothing.
        throw const VideoExportException('The export saved an empty file.');
      }

      int intOf(String key) {
        final value = result[key];
        return value is int ? value : 0;
      }

      return (
        name: result['name'] as String? ?? fileName,
        location: result['location'] as String? ?? fileName,
        uri: result['uri'] as String? ?? '',
        sizeBytes: bytes,
        durationMs: intOf('durationMs'),
        width: intOf('width'),
        height: intOf('height'),
      );
    } on PlatformException catch (error) {
      throw VideoExportException(error.message ?? error.code);
    } finally {
      // Cleared whatever happened: the handler closes over this call's
      // [onProgress], and leaving it attached would feed a finished export's
      // callback from the next one.
      _channel.setMethodCallHandler(null);
    }
  }

  /// Stops a running export. Safe to call when none is running.
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

/// A render that did not produce a file.
class VideoExportException implements Exception {
  const VideoExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
