import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../l10n/app_localizations.dart';
import 'media_player_controller.dart';
import 'transcript_repository.dart';

/// One project: its media, and the transcript as tappable words.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(projectByIdProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          project.value?.title ?? l10n.transcriptTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CenteredMessage(message: '$error'),
        data: (value) => value == null
            ? _CenteredMessage(message: l10n.errorTitle)
            : _ProjectBody(project: value),
      ),
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final transcript = ref.watch(projectTranscriptProvider(project.id));

    return Column(
      children: [
        // The player needs the transcript id to draw captions over the video.
        // Null until the transcript loads, and null forever for a project that
        // produced no speech -- the overlay simply does not appear.
        _PlayerPane(
          mediaPath: project.mediaPath,
          transcriptId: transcript.value?.id,
        ),
        const Divider(height: 1),
        Expanded(
          child: transcript.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _CenteredMessage(message: '$error'),
            data: (value) => value == null
                ? _CenteredMessage(message: l10n.transcriptEmpty)
                : _TranscriptView(mediaPath: project.mediaPath, transcript: value),
          ),
        ),
      ],
    );
  }
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane({required this.mediaPath, required this.transcriptId});

  final String mediaPath;
  final String? transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(mediaPlayerProvider(mediaPath));

    return player.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => SizedBox(
        height: 200,
        child: _CenteredMessage(message: l10n.playerUnavailable),
      ),
      data: (controller) => _Player(
        mediaPath: mediaPath,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _Player extends ConsumerWidget {
  const _Player({
    required this.mediaPath,
    required this.transcriptId,
    required this.controller,
  });

  final String mediaPath;
  final String? transcriptId;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Audio-only files still load through the platform player but report
        // no video size, so a placeholder stands in for the empty surface
        // rather than collapsing the pane to nothing.
        final hasVideo = value.size.width > 0 && value.size.height > 0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A fixed-height black stage, with the picture letterboxed inside
            // it. The height cap stops a portrait video pushing the transcript
            // off screen; the black is what makes the caption bar below read as
            // part of the player. Without it the caption floats over page
            // background beside a narrow portrait video, which looks like a
            // stray tooltip rather than a caption.
            SizedBox(
              height: hasVideo ? 240 : 120,
              width: double.infinity,
              child: ColoredBox(
                color: hasVideo ? Colors.black : Colors.transparent,
                child: Stack(
                  // Captions sit over the picture, which is where they will be
                  // burned in at export -- but they are live widgets here,
                  // never rasterized (docs/engine-architecture.md).
                  children: [
                    Center(
                      child: hasVideo
                          ? AspectRatio(
                              aspectRatio: value.aspectRatio,
                              child: VideoPlayer(controller),
                            )
                          : _CenteredMessage(message: l10n.audioOnlyLabel),
                    ),
                    if (transcriptId != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _CaptionOverlay(
                          transcriptId: transcriptId!,
                          positionMs: value.position.inMilliseconds,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      ref.read(mediaPlayerProvider(mediaPath).notifier).togglePlayback(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  tooltip: value.isPlaying ? l10n.pauseAction : l10n.playAction,
                ),
                Expanded(
                  child: VideoProgressIndicator(controller, allowScrubbing: true),
                ),
                const SizedBox(width: 12),
                Text(_formatPosition(value.position)),
                const SizedBox(width: 12),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The caption for the current playback position, drawn over the video.
///
/// This is the Tier 1 caption surface: one grouping mode, coloured by speaker,
/// and structured all the way down — the cue keeps its words, so nothing here
/// has flattened the caption into pixels or even into a bare string.
class _CaptionOverlay extends ConsumerWidget {
  const _CaptionOverlay({
    required this.transcriptId,
    required this.positionMs,
  });

  final String transcriptId;
  final int positionMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cues = ref.watch(captionCuesProvider(transcriptId)).value;
    if (cues == null || cues.isEmpty) return const SizedBox.shrink();

    final cue = cueAt(cues, positionMs);
    // Nothing is being said right now. Rendering an empty box rather than a
    // blank scrim keeps the picture clear between lines, the way captions
    // actually behave.
    if (cue == null) return const SizedBox.shrink();

    final color = SpeakerPalette.colorFor(cue.speaker, fallback: Colors.white);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A scrim rather than a solid bar: enough to keep text legible over
          // a bright frame without hiding the video behind it.
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            cue.text,
            textAlign: TextAlign.center,
            // Bounded so a large accessibility text scale cannot grow the
            // caption past the video and shove the controls off screen.
            // Truncation is close to unreachable in practice because grouping
            // already caps a cue at CaptionStyle.maxCharacters.
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  // Captions land on unpredictable frames, so the scrim alone
                  // is not always enough separation.
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black87),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptView extends ConsumerWidget {
  const _TranscriptView({required this.mediaPath, required this.transcript});

  final String mediaPath;
  final Transcript transcript;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final words = ref.watch(transcriptWordsProvider(transcript.id));

    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CenteredMessage(message: '$error'),
      data: (items) {
        if (items.isEmpty) return _CenteredMessage(message: l10n.transcriptEmpty);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.wordCount(items.length),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Expanded(
              child: _WordFlow(mediaPath: mediaPath, words: items),
            ),
          ],
        );
      },
    );
  }
}

/// The transcript itself: a reflowing run of words, each one a seek target.
class _WordFlow extends ConsumerWidget {
  const _WordFlow({required this.mediaPath, required this.words});

  final String mediaPath;
  final List<Word> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(mediaPlayerProvider(mediaPath)).value;

    // Without a player there is nothing to highlight against, so the words
    // render as a plain transcript instead of failing.
    if (player == null) {
      return _WordFlowContent(mediaPath: mediaPath, words: words, positionMs: null);
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) => _WordFlowContent(
        mediaPath: mediaPath,
        words: words,
        positionMs: value.position.inMilliseconds,
      ),
    );
  }
}

class _WordFlowContent extends ConsumerWidget {
  const _WordFlowContent({
    required this.mediaPath,
    required this.words,
    required this.positionMs,
  });

  final String mediaPath;
  final List<Word> words;
  final int? positionMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = positionMs == null ? -1 : _activeWordIndex(words, positionMs!);

    final turns = _groupIntoTurns(words);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final turn in turns) ...[
            // Absent on a transcript that was never diarized, in which case
            // this renders as the single uninterrupted run of words it was
            // before speakers existed.
            if (turn.speaker != null)
              _SpeakerLabel(speaker: turn.speaker!),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (offset, word) in turn.words.indexed)
                  _WordChip(
                    word: word,
                    // The highlight is driven by position in the whole
                    // transcript, so turns have to contribute their own offset
                    // rather than restarting the count.
                    active: turn.startIndex + offset == activeIndex,
                    onTap: () => ref
                        .read(mediaPlayerProvider(mediaPath).notifier)
                        .seekToWord(word.startMs),
                  ),
              ],
            ),
            if (turn.speaker != null) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.active,
    required this.onTap,
  });

  final Word word;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: active ? theme.colorScheme.primaryContainer : Colors.transparent,
        ),
        child: Text(
          word.word,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: active ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}

/// Who is talking, above the run of words they said.
///
/// Deliberately modest: a name and a colour drawn from the theme, keyed off the
/// engine's speaker index. Real speaker records — editable names, a stable
/// colour per person, colours that survive into exported captions — are the
/// Phase 4 captions data model. This exists so Phase 3's output is visible and
/// checkable at all, which it was not when diarization first shipped.
class _SpeakerLabel extends StatelessWidget {
  const _SpeakerLabel({required this.speaker});

  final int speaker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Same palette the captions use, so a speaker is the same colour whether
    // you are reading the transcript or watching the video. That consistency
    // is the whole reason the colour exists.
    final background =
        SpeakerPalette.colorFor(speaker, fallback: theme.colorScheme.surfaceContainerHighest);
    final foreground =
        SpeakerPalette.onColorFor(speaker, fallback: theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          // Engine indices are 0-based; people count from one.
          l10n.speakerLabel(speaker + 1),
          style: theme.textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A run of consecutive words sharing one speaker.
class _Turn {
  _Turn({required this.speaker, required this.startIndex});

  /// Null when the transcript carries no speaker information at all.
  final int? speaker;

  /// Where this run begins in the flat word list, so the active-word
  /// highlight keeps working across turns.
  final int startIndex;

  final List<Word> words = [];
}

/// Splits [words] wherever the speaker changes.
///
/// A transcript with no diarization yields exactly one unlabelled turn, so the
/// rendering path is shared rather than branched.
List<_Turn> _groupIntoTurns(List<Word> words) {
  final turns = <_Turn>[];
  String? currentId;

  for (final (index, word) in words.indexed) {
    if (turns.isEmpty || word.speakerId != currentId) {
      currentId = word.speakerId;
      turns.add(
        _Turn(speaker: int.tryParse(word.speakerId ?? ''), startIndex: index),
      );
    }
    turns.last.words.add(word);
  }

  return turns;
}

/// Index of the word being spoken at [positionMs], or -1 before the first one.
///
/// Falls back to the most recent word that has already started rather than
/// requiring an exact span match: DTW timestamps leave small gaps between
/// consecutive words, and an exact test would make the highlight flicker off
/// in each gap.
int _activeWordIndex(List<Word> words, int positionMs) {
  var candidate = -1;
  for (var i = 0; i < words.length; i++) {
    if (words[i].startMs > positionMs) break;
    candidate = i;
  }
  return candidate;
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

String _formatPosition(Duration position) {
  final minutes = position.inMinutes.toString().padLeft(2, '0');
  final seconds = (position.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
