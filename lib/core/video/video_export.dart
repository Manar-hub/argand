import 'package:flutter/services.dart';

import '../captions/project_cues.dart';
import '../captions/speaker_palette.dart';
import '../transcript/speaker_names.dart';
import '../database/database.dart';
import '../timeline/audio_window.dart';
import '../timeline/clip_trim.dart';
import '../timeline/item_look.dart';
import '../timeline/item_transform.dart';
import '../timeline/project_timeline.dart';
import 'export_options.dart';

/// One caption as the renderer needs it: when to show it, what it says, and
/// what colour the speaker is.
typedef ExportCaption = ({
  int startMs,
  int endMs,
  String text,
  int colorArgb,
  double x,
  double y,
  double scale,
  List<TimedText> words,
  ItemLook look,

  /// The speaker's name, drawn small above the words; null for none.
  String? label,
});

/// One text layer's stretch over one clip, timed on that clip's own clock.
typedef ExportText = ({
  int startMs,
  int endMs,
  String text,
  ItemTransform placement,
  ItemLook look,
});

/// One image's stretch over one clip, timed on that clip's own clock.
typedef ExportImage = ({
  int startMs,
  int endMs,
  String path,
  int widthPx,
  int heightPx,
  ItemTransform placement,
});

/// How big an image is drawn at scale 1: its longer side this share of the
/// frame's shorter edge. The stage and the render both size by it.
const double imageExtentFraction = 0.5;

/// One clip to render: which stretch of its media, and what goes on top.
typedef ExportClip = ({
  String path,
  int startMs,
  int endMs,
  List<ExportCaption> captions,
  List<ExportText> texts,
  List<ExportImage> images,
  ItemTransform framing,
  ({int startMs, int endMs, int projectStartMs, bool inline})? audio,
});

/// What to render, and how long the result should be.
typedef ExportRequest = ({List<ExportClip> clips, int totalMs});

/// The captions to burn over one clip, coloured by speaker.
List<ExportCaption> exportCaptionsFor(
  List<Word> words, {
  ClipWindow? window,
  ItemTransform placement = ItemTransform.captionDefault,
  ItemLook look = ItemLook.defaults,
  Color fallback = const Color(0xFFFFFFFF),
  SpeakerNames names = const SpeakerNames.empty(),
  String Function(int speaker)? speakerLabel,
}) {
  // Cues are moved onto the clip's clock; their words are not, so they are
  // moved here by the same amount.
  final shift = window?.startMs ?? 0;
  int local(int ms) => ms - shift < 0 ? 0 : ms - shift;

  return [
    for (final cue in clipCuesFor(words, window: window))
      if ((
        _ownPlacement(cue.words.first) ?? placement,
        ItemLook.decode(cue.words.first.captionLook) ?? look,
      )
          case (final at, final style))
        (
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: cue.text,
          colorArgb: style.colorArgb ??
              SpeakerPalette.colorFor(
                cue.speaker,
                fallback: fallback,
                custom: names.colorOf(cue.speaker),
              ).toARGB32(),
          x: at.x,
          y: at.y,
          scale: at.scale,
          words: [
            for (final word in cue.words)
              (
                text: word.word.trim(),
                startMs: local(word.startMs),
                endMs: local(word.endMs),
              ),
          ],
          look: style,
          label: speakerLabel == null || cue.speaker == null
              ? null
              : names.labelFor(
                  cue.speaker!,
                  defaultLabel: speakerLabel(cue.speaker!),
                ),
        ),
  ];
}

/// A sentence placed on its own carries its placement on every one of its
/// words; the first word of a cue says where that cue goes.
ItemTransform? _ownPlacement(Word word) => word.captionX == null
    ? null
    : ItemTransform(
        x: word.captionX!,
        y: word.captionY ?? ItemTransform.captionDefault.y,
        scale: word.captionScale ?? 1,
      );

/// The parts of [texts] that fall on a clip placed at [startMs] for
/// [durationMs] of the project, on that clip's own clock.
List<ExportText> exportTextsFor(
  List<TextLayer> texts, {
  required int startMs,
  required int durationMs,
}) {
  final endMs = startMs + durationMs;
  return [
    for (final text in texts)
      if (text.startMs < endMs && text.endMs > startMs)
        (
          startMs: (text.startMs - startMs).clamp(0, durationMs),
          endMs: (text.endMs - startMs).clamp(0, durationMs),
          text: text.content,
          placement: ItemTransform(
            x: text.x,
            y: text.y,
            scale: text.scale,
            rotation: text.rotation,
          ),
          look: ItemLook.decode(text.look) ?? ItemLook.defaults,
        ),
  ];
}

/// The parts of [images] that fall on a clip placed at [startMs] for
/// [durationMs] of the project, on that clip's own clock -- cut at clip
/// boundaries as [exportTextsFor] cuts texts.
List<ExportImage> exportImagesFor(
  List<ImageLayer> images, {
  required int startMs,
  required int durationMs,
}) {
  final endMs = startMs + durationMs;
  return [
    for (final image in images)
      if (image.startMs < endMs && image.endMs > startMs)
        (
          startMs: (image.startMs - startMs).clamp(0, durationMs),
          endMs: (image.endMs - startMs).clamp(0, durationMs),
          path: image.path,
          widthPx: image.widthPx,
          heightPx: image.heightPx,
          placement: ItemTransform(
            x: image.x,
            y: image.y,
            scale: image.scale,
            rotation: image.rotation,
          ),
        ),
  ];
}

/// Builds the export request for a project, in timeline order.
ExportRequest? exportRequestFor({
  required ProjectTimeline timeline,
  required List<MediaClip> clips,
  Map<String, List<ExportCaption>> captionsByClip = const {},
  List<TextLayer> texts = const [],
  List<ImageLayer> images = const [],
  bool withAudio = true,
}) {
  if (timeline.placements.isEmpty) return null;

  final byId = {for (final clip in clips) clip.id: clip};

  final ordered = <ExportClip>[];
  for (final placement in timeline.placements) {
    // A zero-length placement contributes no frames and no samples. Passing it
    // to the encoder as an empty item is a failure on some codecs and a no-op
    // on others, and neither is worth the inconsistency.
    if (placement.durationMs <= 0) continue;

    final clip = byId[placement.clipId];
    if (clip == null) return null;

    final window = clipWindow(clip);
    ordered.add((
      path: clip.mediaPath,
      startMs: window.startMs,
      endMs: window.endMs,
      captions: captionsByClip[placement.clipId] ?? const [],
      texts: exportTextsFor(
        texts,
        startMs: placement.startMs,
        durationMs: placement.durationMs,
      ),
      images: exportImagesFor(
        images,
        startMs: placement.startMs,
        durationMs: placement.durationMs,
      ),
      framing: ItemTransform(
        x: clip.offsetX,
        y: clip.offsetY,
        scale: clip.scale,
        rotation: clip.rotation,
      ),
      audio: !withAudio || clip.audioMuted
          ? null
          : switch (audioSpan(timeline, clip)) {
              final span? => (
                  startMs: span.mediaStartMs,
                  endMs: span.mediaStartMs + (span.endMs - span.startMs),
                  projectStartMs: span.startMs,
                  inline: clip.audioStartOffsetMs == 0 &&
                      clip.audioEndOffsetMs == 0,
                ),
              null => null,
            },
    ));
  }

  if (ordered.isEmpty) return null;
  return (clips: ordered, totalMs: timeline.totalMs);
}

/// A rendered video, as the device's Downloads collection recorded it.
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
const int maxExportStemLength = 60;

/// Builds the name a rendered video is saved under.
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
class VideoExporter {
  const VideoExporter();

  static const _channel = MethodChannel('argand/video_export');

  /// Renders [clipPaths] end to end and saves the result as [fileName].
  Future<ExportedVideo> export({
    required List<ExportClip> clips,
    required String fileName,
    ExportOptions options = ExportOptions.defaults,
    void Function(int percent)? onProgress,
    bool hideVideo = false,
    bool muteAudio = false,
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
              'startMs': clip.startMs,
              'endMs': clip.endMs,
              'captions': [
                for (final caption in clip.captions)
                  {
                    'startMs': caption.startMs,
                    'endMs': caption.endMs,
                    'text': caption.text,
                    'colorArgb': caption.colorArgb,
                    'label': caption.label,
                    'x': caption.x,
                    'y': caption.y,
                    'scale': caption.scale,
                    'font': caption.look.font.asset,
                    'mode': caption.look.mode.name,
                    'highlightArgb': caption.look.highlightArgb,
                    'highlightBox': caption.look.highlightBox,
                    'backgroundArgb': caption.look.backgroundArgb,
                    'shadow': caption.look.shadow,
                    'words': [
                      for (final word in caption.words)
                        {
                          'text': word.text,
                          'startMs': word.startMs,
                          'endMs': word.endMs,
                        },
                    ],
                  },
              ],
              'texts': [
                for (final text in clip.texts)
                  {
                    'startMs': text.startMs,
                    'endMs': text.endMs,
                    'text': text.text,
                    'x': text.placement.x,
                    'y': text.placement.y,
                    'scale': text.placement.scale,
                    'rotation': text.placement.rotation,
                    'font': text.look.font.asset,
                    'colorArgb': text.look.colorArgb ?? 0xFFFFFFFF,
                    // The bundled faces are display weights already.
                    'bold': text.look.font == LookFont.standard,
                    'backgroundArgb': text.look.backgroundArgb,
                    'shadow': text.look.shadow,
                  },
              ],
              'images': [
                for (final image in clip.images)
                  {
                    'startMs': image.startMs,
                    'endMs': image.endMs,
                    'path': image.path,
                    'widthPx': image.widthPx,
                    'heightPx': image.heightPx,
                    'x': image.placement.x,
                    'y': image.placement.y,
                    'scale': image.placement.scale,
                    'rotation': image.placement.rotation,
                  },
              ],
              'framing': clip.framing.toJson(),
              if (clip.audio case final audio?)
                'audio': {
                  'startMs': audio.startMs,
                  'endMs': audio.endMs,
                  'projectStartMs': audio.projectStartMs,
                  'inline': audio.inline,
                },
            },
        ],
        'fileName': fileName,
        // The timeline's hidden video and audio tracks: black picture (the
        // overlays still drawn on it), and silence.
        'hideVideo': hideVideo,
        'muteAudio': muteAudio,
        // Spread rather than nested, so the native side reads one flat map and
        // an option added later needs no new unwrapping on the way down.
        ...options.encode(),
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

  /// The size [mediaPath] is seen at, rotation applied -- the same size the
  /// render starts from.
  Future<({int width, int height})?> sourceSize(String mediaPath) async {
    try {
      final size = await _channel.invokeMapMethod<String, Object?>(
        'sourceSize',
        {'path': mediaPath},
      );
      final width = size?['width'];
      final height = size?['height'];
      if (width is! int || height is! int) return null;
      return (width: width, height: height);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// A render that did not produce a file.
class VideoExportException implements Exception {
  const VideoExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
