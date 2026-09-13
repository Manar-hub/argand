import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/captions/subtitle_export.dart';
import '../../core/database/database.dart';
import '../../core/text/sentence_units.dart';
import '../../core/transcript/sentence_edit.dart';
import '../../core/transcript/speaker_turns.dart';
import '../../l10n/app_localizations.dart';
import 'media_player_controller.dart';
import 'subtitle_export_controller.dart';
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
    final transcript = ref.watch(projectTranscriptProvider(projectId)).value;

    // Export outcomes are transient, so they are acknowledged rather than
    // rendered -- the same shape the library uses for import results.
    ref.listen(subtitleExporterProvider, (previous, next) {
      final message = switch (next) {
        SubtitleExportSaved(:final fileName) => l10n.exportSaved(fileName),
        SubtitleExportCancelled() => l10n.exportCancelled,
        SubtitleExportEmpty() => l10n.exportEmpty,
        SubtitleExportFailed() => l10n.exportFailed,
        _ => null,
      };
      if (message == null) return;

      ref.read(subtitleExporterProvider.notifier).reset();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          project.value?.title ?? l10n.transcriptTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // History belongs to editing, so it appears with it. Showing two
          // permanently-disabled buttons during playback would add weight to
          // the bar for a mode in which nothing can be edited or undone.
          if (editing && transcript != null)
            _HistoryControls(transcriptId: transcript.id),
          // Not gated behind edit mode: exporting is something you do to a
          // finished transcript, and it is free for every container of the
          // user's own words (CLAUDE.md §2).
          if (!editing && transcript != null)
            _ExportButton(
              transcript: transcript,
              title: project.value?.title ?? '',
            ),
          // The only control the feature adds to the page. Everything else
          // reuses what is already on screen: tapping a line retypes it, and a
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

/// Opens the caption export options.
///
/// Shows a spinner in place of the icon while a file is being written, so a
/// second tap cannot start an overlapping export and open two save dialogs.
class _ExportButton extends ConsumerWidget {
  const _ExportButton({required this.transcript, required this.title});

  final Transcript transcript;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final running = ref.watch(subtitleExporterProvider) is SubtitleExportRunning;

    if (running) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      icon: const Icon(Icons.file_download_outlined),
      tooltip: l10n.exportAction,
      onPressed: () => _chooseFormat(context, ref, l10n),
    );
  }

  Future<void> _chooseFormat(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      builder: (_) => const _ExportSheet(),
    );
    if (choice == null) return;

    await ref.read(subtitleExporterProvider.notifier).export(
          transcriptId: transcript.id,
          title: title,
          language: transcript.language,
          format: choice.format,
          // Built here rather than in the controller: "Speaker 1" is interface
          // text, and CLAUDE.md 4 keeps those out of the service layer.
          speakerLabel: choice.includeSpeakers
              ? (speaker) => l10n.speakerLabel(speaker + 1)
              : null,
        );
  }
}

/// What the export sheet returns: a format, and whether to attribute lines.
class _ExportChoice {
  const _ExportChoice({required this.format, required this.includeSpeakers});

  final SubtitleFormat format;
  final bool includeSpeakers;
}

/// Format picker, with the one option that changes the file's content.
///
/// Stateful because the speaker toggle has to be settable *before* a format is
/// chosen -- tapping a format is what closes the sheet, so the switch cannot
/// come after it.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _includeSpeakers = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      // Scrollable so the sheet still reaches its last option on a short screen
      // or at a large accessibility text scale, rather than overflowing.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                l10n.exportSheetTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            SwitchListTile(
              value: _includeSpeakers,
              onChanged: (value) => setState(() => _includeSpeakers = value),
              title: Text(l10n.exportIncludeSpeakers),
              secondary: const Icon(Icons.record_voice_over_outlined),
            ),
            const Divider(height: 1),
            for (final (format, title, detail) in [
              (SubtitleFormat.srt, l10n.exportSrt, l10n.exportSrtDetail),
              (SubtitleFormat.vtt, l10n.exportVtt, l10n.exportVttDetail),
            ])
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(title),
                subtitle: Text(detail),
                onTap: () => Navigator.of(context).pop(
                  _ExportChoice(
                    format: format,
                    includeSpeakers: _includeSpeakers,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Chooses how much of the transcript one tap opens, and explains the gestures.
///
/// The banner is where a user already looks to learn what editing does, so the
/// choice lives here rather than as a third icon in the app bar.
///
/// **Word is not a convenience setting.** A retyped run keeps the outer span of
/// what it replaced and divides the inside between the new words, so a smaller
/// run means a smaller re-estimate. Editing one word confines any timing change
/// to that word; editing the line spreads it across the line. The hint says so
/// in each mode, because a user cannot pick sensibly without knowing it.
class _EditScopeBanner extends ConsumerWidget {
  const _EditScopeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = ref.watch(transcriptEditScopeSettingProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scrolls rather than shrinking: at a large accessibility text scale
          // two segments plus their labels will not fit a narrow screen, and a
          // clipped control is worse than one the user pushes sideways.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TranscriptEditScope>(
              segments: [
                ButtonSegment(
                  value: TranscriptEditScope.line,
                  icon: const Icon(Icons.notes, size: 18),
                  label: Text(l10n.editScopeLine),
                ),
                ButtonSegment(
                  value: TranscriptEditScope.word,
                  icon: const Icon(Icons.text_fields, size: 18),
                  label: Text(l10n.editScopeWord),
                ),
              ],
              selected: {scope},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => ref
                  .read(transcriptEditScopeSettingProvider.notifier)
                  .select(selection.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            switch (scope) {
              TranscriptEditScope.line => l10n.editModeHintLine,
              TranscriptEditScope.word => l10n.editModeHintWord,
            },
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Undo and redo for the transcript's edit history.
///
/// The history is a table, not a field on this widget, so it survives leaving
/// the project and relaunching the app: reopening a transcript a week later
/// still offers to undo the last correction made to it.
///
/// Each button is disabled rather than hidden when it has nothing to do. A
/// control that vanishes shifts the two beside it, and the app bar would
/// reshuffle under the user's finger as they worked through a history.
class _HistoryControls extends ConsumerWidget {
  const _HistoryControls({required this.transcriptId});

  final String transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Both false until the first frame resolves, which is correct: an empty
    // history and an unread one offer the same actions.
    final history = ref.watch(editHistoryProvider(transcriptId)).value ??
        (canUndo: false, canRedo: false);

    final repository = ref.read(transcriptRepositoryProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: l10n.undoAction,
          onPressed:
              history.canUndo ? () => repository.undo(transcriptId) : null,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: l10n.redoAction,
          onPressed:
              history.canRedo ? () => repository.redo(transcriptId) : null,
        ),
      ],
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
          projectId: project.id,
          transcriptId: transcript.value?.id,
        ),
        const Divider(height: 1),
        Expanded(
          child: transcript.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _CenteredMessage(message: '$error'),
            data: (value) => value == null
                ? _CenteredMessage(message: l10n.transcriptEmpty)
                : _TranscriptView(projectId: project.id, transcript: value),
          ),
        ),
      ],
    );
  }
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane({required this.projectId, required this.transcriptId});

  final String projectId;
  final String? transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(mediaPlayerProvider(projectId));

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
        projectId: projectId,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _Player extends ConsumerWidget {
  const _Player({
    required this.projectId,
    required this.transcriptId,
    required this.controller,
  });

  final String projectId;
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
                      ref.read(mediaPlayerProvider(projectId).notifier).togglePlayback(),
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
  const _TranscriptView({required this.projectId, required this.transcript});

  final String projectId;
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
              child: _WordFlow(projectId: projectId, words: items),
            ),
          ],
        );
      },
    );
  }
}

/// The transcript itself: a reflowing run of words, each one a seek target.
class _WordFlow extends ConsumerWidget {
  const _WordFlow({required this.projectId, required this.words});

  final String projectId;
  final List<Word> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(mediaPlayerProvider(projectId)).value;

    // Without a player there is nothing to highlight against, so the words
    // render as a plain transcript instead of failing.
    if (player == null) {
      return _WordFlowContent(projectId: projectId, words: words, positionMs: null);
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) => _WordFlowContent(
        projectId: projectId,
        words: words,
        positionMs: value.position.inMilliseconds,
      ),
    );
  }
}

class _WordFlowContent extends ConsumerWidget {
  const _WordFlowContent({
    required this.projectId,
    required this.words,
    required this.positionMs,
  });

  final String projectId;
  final List<Word> words;
  final int? positionMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (editing) const _EditScopeBanner(),
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
                        ? () => _correct(context, ref, turn, offset)
                        : () => ref
                            .read(mediaPlayerProvider(projectId).notifier)
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

  /// Opens the word at [offset] within [turn], or the sentence containing it.
  ///
  /// **Which one is the user's choice, and it is a real one.** A retyped run
  /// keeps the outer span of what it replaced and divides the inside between
  /// the new words, so the run is exactly the blast radius of any re-estimated
  /// timing. Line is the default because the corrections people actually make
  /// often span a word boundary — "brainbeats" for "praying beads" cannot be
  /// typed one word at a time — and seeing the line gives the context being
  /// corrected against. Word is there for when the timing matters more, and
  /// confines the change to that one word's box.
  ///
  /// In line mode the unit is the sentence **within this turn**, not across the
  /// transcript. A turn is one voice by construction, so every word the editor
  /// can add inherits an unambiguous speaker — a sentence that straddled a
  /// handover would have no such answer.
  Future<void> _correct(
    BuildContext context,
    WidgetRef ref,
    SpeakerTurn turn,
    int offset,
  ) async {
    final scope = ref.read(transcriptEditScopeSettingProvider);

    final slice = switch (scope) {
      TranscriptEditScope.word => [turn.words[offset]],
      TranscriptEditScope.line => _sentenceAround(turn, offset),
    };

    final text = await showDialog<String>(
      context: context,
      builder: (context) => _SentenceEditor(words: slice, scope: scope),
    );
    if (text == null) return;

    // The repository decides whether anything actually changed, so a dialog
    // dismissed with the text untouched costs no undo slot. A single-word range
    // needs no special case: `replaceSentence` takes `from == to`, and the
    // planner then divides that one word's span and nothing else.
    await ref.read(transcriptRepositoryProvider).replaceSentence(
          transcriptId: slice.first.transcriptId,
          fromPosition: slice.first.position,
          toPosition: slice.last.position,
          text: text,
        );
  }

  /// The words of the sentence containing [offset], within [turn].
  List<Word> _sentenceAround(SpeakerTurn turn, int offset) {
    final units = sentenceUnitsOf([
      for (final word in turn.words)
        (text: word.word, startMs: word.startMs, endMs: word.endMs),
    ]);

    final unit = units.firstWhere(
      (candidate) => offset >= candidate.first && offset <= candidate.last,
      // A turn always produces at least one unit -- `sentenceUnitsOf` closes
      // the final run even with no terminator -- so this is unreachable rather
      // than a real fallback, and is here so the lookup cannot throw.
      orElse: () => units.last,
    );

    return turn.words.sublist(unit.first, unit.last + 1);
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

/// Retypes a whole sentence.
///
/// One free-text field rather than a word in a box, because a correction is
/// usually a phrase: the engine hears "brainbeats" where the speaker said
/// "praying beads", and no per-word editor can express that. Seeing the line
/// whole also shows the context being corrected against.
///
/// **The sentence keeps its own span**, however many words come back —
/// `planSentenceEdit` divides the time between them and leaves the words the
/// user did not touch on their original timestamps. That is what the note under
/// the field promises, and a user retyping a longer line has every reason to
/// wonder, because caption boundaries, the playback highlight and tap-to-seek
/// are all built on those numbers.
class _SentenceEditor extends StatefulWidget {
  const _SentenceEditor({required this.words, required this.scope});

  final List<Word> words;

  /// Only changes the wording. Both scopes retype free text and both are
  /// contained; what differs is how much span the result may redivide, and the
  /// note under the field is where that gets said.
  final TranscriptEditScope scope;

  @override
  State<_SentenceEditor> createState() => _SentenceEditorState();
}

class _SentenceEditorState extends State<_SentenceEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: sentenceTextOf([
      for (final word in widget.words)
        (
          id: word.id,
          text: word.word,
          startMs: word.startMs,
          endMs: word.endMs,
        ),
    ]),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final word = widget.scope == TranscriptEditScope.word;

    return AlertDialog(
      title: Text(word ? l10n.editWordTitle : l10n.editSentenceTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              // Grows with the text instead of scrolling a single line
              // sideways: the point of editing a sentence is seeing it.
              maxLines: null,
              minLines: 2,
              keyboardType: TextInputType.multiline,
              // Deliberately not `TextInputAction.done`: a newline in a
              // sentence is plausible typing, and submitting on the return key
              // would close the dialog mid-thought. Save is the explicit action.
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 12),
            Text(
              word ? l10n.editWordTimingNote : l10n.editSentenceTimingNote,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.editCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
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
