import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/transcript/speaker_turns.dart';
import '../../l10n/app_localizations.dart';
import 'media_player_controller.dart';
import 'transcript_edit_controller.dart';
import 'transcript_repository.dart';

/// One project: its media, and the transcript as tappable words.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(projectByIdProvider(projectId));

    final editing = ref.watch(transcriptEditModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          project.value?.title ?? l10n.transcriptTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // The only control the feature adds to the page. Everything else
          // reuses what is already on screen: a word edits its own text, a
          // speaker label reassigns its own turn.
          IconButton(
            icon: Icon(editing ? Icons.done : Icons.edit_outlined),
            tooltip: editing ? l10n.editModeDisable : l10n.editModeEnable,
            onPressed: () =>
                ref.read(transcriptEditModeProvider.notifier).toggle(),
          ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final editing = ref.watch(transcriptEditModeProvider);
    final activeIndex =
        positionMs == null || editing ? -1 : _activeWordIndex(words, positionMs!);

    final turns = groupIntoSpeakerTurns(words);

    // Every speaker this transcript actually contains, in the order they first
    // appear. That is the set a turn can be reassigned to: inventing a speaker
    // who never spoke would produce a colour and a label with nothing behind
    // them.
    final speakers = <int>{
      for (final word in words)
        if (int.tryParse(word.speakerId ?? '') case final int speaker) speaker,
    }.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.editModeHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final turn in turns) ...[
            // Absent on a transcript that was never diarized, in which case
            // this renders as the single uninterrupted run of words it was
            // before speakers existed.
            if (turn.speaker != null)
              _SpeakerLabel(
                speaker: turn.speaker!,
                // The label is the control. In edit mode tapping it reassigns
                // the whole turn, which adds no chrome to the page -- the thing
                // you tap is the thing you are changing.
                onTap: editing && speakers.length > 1
                    ? () => _reassignTurn(context, ref, turn, speakers)
                    : null,
              ),
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
                    editing: editing,
                    onTap: editing
                        ? () => _correctWord(context, ref, word)
                        : () => ref
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

  Future<void> _correctWord(
    BuildContext context, WidgetRef ref, Word word) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => _WordEditor(word: word),
    );
    if (text == null || text.isEmpty || text == word.word) return;
    await ref.read(transcriptRepositoryProvider).updateWordText(word.id, text);
  }

  Future<void> _reassignTurn(
    BuildContext context,
    WidgetRef ref,
    SpeakerTurn turn,
    List<int> speakers,
  ) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => _SpeakerPicker(
        speakers: speakers,
        current: turn.speaker,
      ),
    );
    if (chosen == null || chosen == turn.speaker) return;

    // Addressed by position: a turn is a contiguous run, and the correction
    // applies to all of it. Reassigning one half of a wrongly-split sentence
    // makes the two turns merge back on the next rebuild, with no separate
    // merge action needed.
    await ref.read(transcriptRepositoryProvider).reassignSpeaker(
          transcriptId: turn.words.first.transcriptId,
          fromPosition: turn.words.first.position,
          toPosition: turn.words.last.position,
          speaker: chosen,
        );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    required this.active,
    required this.onTap,
    this.editing = false,
  });

  final Word word;
  final bool active;
  final VoidCallback onTap;

  /// In edit mode a word is a target rather than a seek point, so it carries a
  /// faint outline. Without it there is nothing to say the same tap now does
  /// something different.
  final bool editing;

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
          border: editing
              ? Border.all(color: theme.colorScheme.outlineVariant)
              : null,
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
  const _SpeakerLabel({required this.speaker, this.onTap});

  final int speaker;

  /// Set in edit mode, where the label doubles as the control for reassigning
  /// its turn. Null while reading, so the label stays inert.
  final VoidCallback? onTap;

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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // Engine indices are 0-based; people count from one.
                l10n.speakerLabel(speaker + 1),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Corrects a single word's text.
///
/// Only the text. The word keeps its `startMs`/`endMs`, which is what the
/// caption boundaries, the playback highlight and tap-to-seek are all built
/// from — a correction fixes what the engine misheard, not when it was said.
/// The note under the field says so, because a user retyping a longer word has
/// every reason to wonder.
class _WordEditor extends StatefulWidget {
  const _WordEditor({required this.word});

  final Word word;

  @override
  State<_WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<_WordEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.word.word);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.editWordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.editWordTimingNote,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.editCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.editSave),
        ),
      ],
    );
  }
}

/// Lists the speakers this transcript contains, so a turn can be moved onto the
/// right one.
///
/// Only speakers who actually appear: offering one who never spoke would put a
/// colour and a label on screen with nothing behind them. Each entry carries
/// the same palette colour used by the transcript and the captions, so the
/// choice looks like what it will produce.
class _SpeakerPicker extends StatelessWidget {
  const _SpeakerPicker({required this.speakers, required this.current});

  final List<int> speakers;
  final int? current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.reassignSpeakerTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final speaker in speakers)
            ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: SpeakerPalette.colorFor(
                  speaker,
                  fallback: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              title: Text(l10n.speakerLabel(speaker + 1)),
              trailing: speaker == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(speaker),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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
