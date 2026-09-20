import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_cue.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/captions/subtitle_export.dart';
import '../../core/database/database.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transcript/speaker_names.dart';
import '../../core/transcript/speaker_turns.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'editor_mode_controller.dart';
import 'media_player_controller.dart';
import 'subtitle_export_controller.dart';
import 'timeline_screen.dart';
import 'transcript_edit_controller.dart';
import 'transcript_repository.dart';

/// One project: its media, and either the transcript as tappable words
/// (Script mode) or the clip/track view (Timeline mode).
class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({required this.projectId, this.initialMode, super.key});

  final String projectId;

  /// Which mode to open in, chosen by the library's two entry points.
  /// Null when reopening a project from the list -- that path instead
  /// resolves to whichever mode [SessionEditorMode.select] last recorded for
  /// it, falling back to [EditorMode.script] if nothing was ever recorded.
  final EditorMode? initialMode;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  @override
  void initState() {
    super.initState();

    final initial = widget.initialMode;
    if (initial != null) {
      // Already known -- the entry point decided, so there is nothing to
      // look up. Deferred to a microtask because Riverpod forbids modifying
      // a provider synchronously from `initState` -- that still runs while
      // Flutter's build phase for this frame is in progress, even though it
      // is this widget's *own* first build. A microtask runs right after,
      // before the frame is painted, so there is still no flash of the
      // wrong mode.
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(sessionEditorModeProvider(widget.projectId).notifier)
            .select(initial);
      });
      return;
    }

    // Reopened from the list: nothing decided which mode to show, so ask
    // Settings for whatever this project was left in last. Losing the race
    // with the first frame is fine -- Script mode is the default either way,
    // and this only nudges the mode if the stored value differs from it.
    _restoreLastMode();
  }

  Future<void> _restoreLastMode() async {
    final db = ref.read(appDatabaseProvider);
    final stored = await readStoredEditorMode(db, widget.projectId);
    if (!mounted || stored == null) return;
    ref
        .read(sessionEditorModeProvider(widget.projectId).notifier)
        .select(stored);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(projectByIdProvider(widget.projectId));

    final editing = ref.watch(transcriptEditModeProvider);
    // Both modes follow the same selected clip, so the app bar's export and
    // history controls act on exactly what is on screen.
    final selectedClip =
        ref.watch(resolvedSelectedClipProvider(widget.projectId));
    // The app bar acts on whichever range is in front of the user. With one
    // transcript on the clip -- the ordinary case -- that is simply it.
    final transcript = selectedClip == null
        ? null
        : (ref.watch(clipTranscriptsProvider(selectedClip)).value ?? const [])
            .firstOrNull;
    final mode = ref.watch(sessionEditorModeProvider(widget.projectId));

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
          // Script mode's own controls. Timeline mode has its own toolbar for
          // Edit and Captions, so none of these apply there.
          if (mode == EditorMode.script) ...[
            // History belongs to editing, so it appears with it. Showing two
            // permanently-disabled buttons during playback would add weight
            // to the bar for a mode in which nothing can be edited or undone.
            if (editing && transcript != null)
              HistoryControls(transcriptId: transcript.id),
            // Not gated behind edit mode: exporting is something you do to a
            // finished transcript, and it is free for every container of the
            // user's own words (CLAUDE.md §2).
            if (!editing && transcript != null)
              _ExportButton(
                transcript: transcript,
                title: project.value?.title ?? '',
              ),
            IconButton(
              icon: Icon(editing ? Icons.done : Icons.edit_outlined),
              tooltip: editing ? l10n.editModeDisable : l10n.editModeEnable,
              onPressed: () =>
                  ref.read(transcriptEditModeProvider.notifier).toggle(),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: _SegmentRow<EditorMode>(
              selected: mode,
              items: {
                EditorMode.script: l10n.editorModeScript,
                EditorMode.timeline: l10n.editorModeTimeline,
              },
              onSelected: (value) => ref
                  .read(sessionEditorModeProvider(widget.projectId).notifier)
                  .select(value),
            ),
          ),
        ),
      ),
      body: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CenteredMessage(message: '$error'),
        data: (value) => value == null
            ? _CenteredMessage(message: l10n.errorTitle)
            : mode == EditorMode.script
                ? _ProjectBody(project: value)
                : TimelineBody(project: value),
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
    final names = ref.read(speakerNamesProvider(transcript.id));

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
              ? (speaker) => names.labelFor(
                    speaker,
                    defaultLabel: l10n.speakerLabel(speaker + 1),
                  )
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
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
/// The hairline this screen rules everything with.
///
/// One value, used by the separator between two caption lines and by the edit
/// control's own borders. They sit within a few pixels of each other on the
/// page, so any difference between them reads as a mistake rather than as a
/// distinction.
Color _hairline(ThemeData theme) =>
    theme.colorScheme.outline.withValues(alpha: 0.18);

const double _hairlineWidth = 1;

/// A full-width row of choices, divided evenly.
///
/// **Replaces a `SegmentedButton` in a horizontal scroller**, which was the
/// wrong shape twice over: Material's pill sits in the middle of the page with
/// air either side, and the scroller meant the third choice could be off
/// screen with nothing saying so. Splitting the full width gives the control a
/// fixed, obvious extent, and a fourth choice costs a narrower column rather
/// than a layout decision. Labels ellipsize instead of scrolling, so a large
/// text scale shortens a word rather than hiding a whole option.
///
/// **Drawn as part of the page, not as a card on top of it.** It takes the
/// page's own background and the same hairline the transcript separates its
/// lines with — an earlier pass gave it the card fill and the full 2pt outline
/// every raised surface uses, which made a control sitting inside a list of
/// text look like a slab dropped onto it. Nothing here is raised, so nothing
/// here gets a raised surface's weight.
///
/// Generic over the value so the next one of these is a map literal, not a
/// second copy of this widget.
class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rule = _hairline(theme);
    final entries = items.entries.toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: rule, width: _hairlineWidth),
        borderRadius: BorderRadius.circular(context.surface.radius),
      ),
      // Without this the selected segment's fill is a plain rectangle that
      // overruns the rounded border at the ends, so choosing Line or Speakers
      // squares off that corner. A `DecoratedBox` cannot clip, which is how it
      // was lost.
      clipBehavior: Clip.antiAlias,
      // The dividers need a height to stretch to, and the row's height comes
      // from its tallest label. One intrinsic pass on a three-item row is
      // cheap and it is what keeps the rules full-height at any text scale.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0)
                SizedBox(
                  width: _hairlineWidth,
                  child: ColoredBox(color: rule),
                ),
              Expanded(
                child: _Segment(
                  label: entry.value,
                  selected: entry.key == selected,
                  onTap: () => onSelected(entry.key),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableSurface(
      selected: selected,
      // The theme's own call to action: yellow on paper, blue on near-black.
      // Selection used `secondary`, which is the pair the other way round and
      // put blue on the light theme where yellow leads.
      fill: selected ? theme.colorScheme.primary : Colors.transparent,
      // No rounding here: `_SegmentRow` clips the whole row to its own
      // corners, and a segment is a rectangular slice of it, not a card of
      // its own.
      borderRadius: BorderRadius.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // `PressableSurface` already shows the press; Material's own
          // splash/highlight would be a second, conflicting kind of feedback
          // on top of it.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                // Plain weight. The transcript beside it is set for reading, and
                // a bold control next to body text claims a priority it does not
                // have.
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditScopeBanner extends ConsumerWidget {
  const _EditScopeBanner({
    required this.transcriptId,
    required this.speakers,
    required this.inlineFieldKey,
  });

  final String transcriptId;

  /// Speakers the transcript already contains, in first-appearance order.
  final List<int> speakers;

  /// Owned by `_TranscriptViewState`; see `_CueLine.inlineFieldKey`.
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = ref.watch(transcriptEditScopeSettingProvider);
    final anchor = ref.watch(speakerRangeAnchorProvider);

    // Opaque, and its own gutters. It floats over the transcript now, so
    // without a background the text would scroll visibly through it; and it no
    // longer sits inside the scroll view, so it has to supply the margins that
    // padding used to give it.
    //
    // The shadow is the app's usual one — hard, no blur, straight down — and
    // it is what stops the transcript looking sheared off where it passes
    // beneath. Full width, so it reads as an edge rather than as a card.
    final surface = context.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: surface.shadow,
            // One point, matching [_EdgeShadow], so that when the bar slides
            // fully out its shadow lands precisely on the player's line rather
            // than beside it.
            offset: const Offset(0, _hairlineWidth),
            blurRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SegmentRow<TranscriptEditScope>(
              selected: scope,
              items: {
                TranscriptEditScope.line: l10n.editScopeLine,
                TranscriptEditScope.word: l10n.editScopeWord,
                TranscriptEditScope.speakers: l10n.editScopeSpeakers,
              },
              onSelected: (value) {
                // Neither a pending anchor nor an open field may survive the
                // scope it was made in: the anchor would turn the next tap
                // anywhere into a range assignment, and the field would be
                // editing by a rule the user has just changed. Flush the
                // field before closing it -- see
                // `_InlineFieldState.dispose()`.
                ref.read(speakerRangeAnchorProvider.notifier).clear();
                inlineFieldKey.currentState?.flush();
                ref.read(inlineEditProvider.notifier).close();
                ref
                    .read(transcriptEditScopeSettingProvider.notifier)
                    .select(value);
              },
            ),
            if (scope == TranscriptEditScope.speakers) ...[
              const SizedBox(height: 8),
              _SpeakerPalette(transcriptId: transcriptId, speakers: speakers),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (scope) {
                      TranscriptEditScope.line => l10n.editModeHintLine,
                      TranscriptEditScope.word => l10n.editModeHintWord,
                      TranscriptEditScope.speakers => anchor == null
                          ? l10n.editModeHintSpeakers
                          : l10n.editModeHintSpeakersAnchored,
                    },
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                // Only reachable while a half-made selection exists, which is the
                // only time there is anything to cancel.
                if (scope == TranscriptEditScope.speakers && anchor != null)
                  TextButton(
                    onPressed: () =>
                        ref.read(speakerRangeAnchorProvider.notifier).clear(),
                    child: Text(l10n.editCancel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The speakers a tap can assign, and the one it will.
///
/// Offers the transcript's own speakers plus **one more**, up to
/// `SpeakerPalette.length`. Without that extra slot a block diarization gave
/// entirely to one person could never be split: the second speaker has no words
/// yet, so nothing would offer them. A speaker added this way has no acoustic
/// evidence behind it, which is fine for the same reason reassignment exists at
/// all — the person listening is the authority.
class _SpeakerPalette extends ConsumerWidget {
  const _SpeakerPalette({required this.transcriptId, required this.speakers});

  final String transcriptId;
  final List<int> speakers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = ref.watch(selectedSpeakerProvider);
    final names = ref.watch(speakerNamesProvider(transcriptId));

    final available = [...speakers]..sort();
    final next = _nextFreeSpeaker(available);
    final options = [...available, ?next];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final speaker in options) ...[
            _SpeakerChip(
              selected: speaker == selected,
              label: names.labelFor(
                speaker,
                defaultLabel: l10n.speakerLabel(speaker + 1),
              ),
              color: SpeakerPalette.colorFor(
                speaker,
                fallback: theme.colorScheme.surfaceContainerHighest,
              ),
              onTap: () =>
                  ref.read(selectedSpeakerProvider.notifier).select(speaker),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// The lowest index the transcript does not use, or null once the palette's
  /// distinguishable colours are exhausted.
  static int? _nextFreeSpeaker(List<int> used) {
    for (var candidate = 0; candidate < SpeakerPalette.length; candidate++) {
      if (!used.contains(candidate)) return candidate;
    }
    return null;
  }
}

/// One speaker in the Speakers-scope palette.
///
/// Chosen fills with **that speaker's own colour**, not the theme's generic
/// selection tint (`ChoiceChip`'s default, which this replaces) — picking a
/// name should look like picking that person, the same signal the transcript
/// and the caption overlay already give, not like picking any other option in
/// the app. `AppTheme.inkOn` keeps the label readable against whichever
/// colour that turns out to be, the same way it already does for the accent
/// buttons.
class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({
    required this.selected,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final radius = BorderRadius.circular(surface.radius);

    return PressableSurface(
      selected: selected,
      fill: selected ? color : theme.colorScheme.surfaceContainerHighest,
      border: true,
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          // `PressableSurface` already shows the press; Material's own
          // splash/highlight would be a second, conflicting kind of feedback
          // on top of it.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 8, backgroundColor: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? AppTheme.inkOn(color)
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
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
/// Undo/redo for a transcript's edit history. Public because Timeline mode
/// reuses it verbatim in its own preview controls (`timeline_screen.dart`)
/// rather than duplicating it.
class HistoryControls extends ConsumerWidget {
  const HistoryControls({super.key, required this.transcriptId});

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

class _ProjectBody extends ConsumerStatefulWidget {
  const _ProjectBody({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectBody> createState() => _ProjectBodyState();
}

class _ProjectBodyState extends ConsumerState<_ProjectBody> {
  /// Which of the clip's transcribed ranges is showing, when it has several.
  ///
  /// Null, or an id no longer present, both fall back to the first range —
  /// which is what keeps this sane when the selected range is re-transcribed
  /// or its layer removed out from under the screen.
  String? _selectedRangeId;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final l10n = AppLocalizations.of(context);
    // Script mode shows the clip the timeline has selected. A project with no
    // clips has nothing to show and nothing to play.
    final clipId = ref.watch(resolvedSelectedClipProvider(project.id));
    if (clipId == null) {
      return _CenteredMessage(message: l10n.timelineNoClips);
    }

    final transcripts = ref.watch(clipTranscriptsProvider(clipId));
    final ranges = transcripts.value ?? const <Transcript>[];
    // Which range is showing. Kept as plain widget state rather than a
    // provider: it is a cursor within one screen, and there is nothing else
    // that needs to read it.
    final selected = ranges.isEmpty
        ? null
        : ranges.firstWhere(
            (t) => t.id == _selectedRangeId,
            orElse: () => ranges.first,
          );

    return Column(
      children: [
        // The player needs the transcript id to draw captions over the video.
        // Null until the transcript loads, and null forever for a clip nobody
        // has transcribed -- the overlay simply does not appear.
        //
        // Deliberately the *selected* range rather than all of them merged:
        // each range is its own diarization run, so a merged overlay would
        // show one person in two colours and two names as the playhead crossed
        // a boundary.
        _PlayerPane(
          clipId: clipId,
          transcriptId: selected?.id,
        ),
        // Only when there is a choice to make. A clip with one transcript --
        // every clip until layers are used -- looks exactly as it did before.
        if (ranges.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: _SegmentRow<String>(
              selected: selected!.id,
              items: {
                for (final range in ranges)
                  range.id: _rangeLabel(range),
              },
              onSelected: (id) => setState(() => _selectedRangeId = id),
            ),
          ),
        // The player casts no shadow of its own — the transcript draws it,
        // from inside its own stack. Two reasons. A column sibling paints
        // before the one that follows it, so anything cast here would be
        // covered by the transcript anyway. And putting it at the top of the
        // transcript's viewport is what lets it *merge* with the edit bar's
        // shadow: when the bar has slid fully away its own shadow lands on
        // exactly that line, so the two become one instead of stacking into a
        // double rule.
        Expanded(
          child: transcripts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _CenteredMessage(message: '$error'),
            // A clip nobody has asked to transcribe yet. Says so plainly and
            // points at where the action lives, rather than implying the
            // engine found no speech -- which is a different outcome entirely.
            data: (_) => selected == null
                ? _CenteredMessage(message: l10n.clipNotTranscribedScript)
                : _TranscriptView(clipId: clipId, transcript: selected),
          ),
        ),
      ],
    );
  }
}

/// A transcript's clip-relative range, for the range selector.
///
/// A null range means the whole clip — what a transcript written before layers
/// existed carries — so it gets the plain label rather than a fabricated span.
String _rangeLabel(Transcript transcript) {
  final start = transcript.clipStartMs;
  final end = transcript.clipEndMs;
  if (start == null || end == null) return _formatPosition(Duration.zero);
  return '${_formatPosition(Duration(milliseconds: start))}'
      '–${_formatPosition(Duration(milliseconds: end))}';
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane({required this.clipId, required this.transcriptId});

  final String clipId;
  final String? transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(mediaPlayerProvider(clipId));

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
        clipId: clipId,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _Player extends ConsumerWidget {
  const _Player({
    required this.clipId,
    required this.transcriptId,
    required this.controller,
  });

  final String clipId;
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
                        child: CaptionOverlay(
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
                      ref.read(mediaPlayerProvider(clipId).notifier).togglePlayback(),
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
/// **Shared by both modes.** Script mode and the timeline draw the same
/// overlay from the same [captionCuesProvider], so a sentence edited in one is
/// already edited in the other -- there is no syncing step because there is
/// only ever one set of cues, derived from the word rows both modes read.
///
/// This is the Tier 1 caption surface: one grouping mode, coloured by speaker,
/// and structured all the way down — the cue keeps its words, so nothing here
/// has flattened the caption into pixels or even into a bare string.
class CaptionOverlay extends ConsumerWidget {
  const CaptionOverlay({
    super.key,
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

class _TranscriptView extends ConsumerStatefulWidget {
  const _TranscriptView({required this.clipId, required this.transcript});

  final String clipId;
  final Transcript transcript;

  @override
  ConsumerState<_TranscriptView> createState() => _TranscriptViewState();
}

/// Holds the transcript's scroll, because the edit bar above it has to follow.
///
/// **The bar slides, it does not collapse.** A first pass shrank its height as
/// you scrolled, which reads as the page eating a control rather than as the
/// control leaving. It now moves up by exactly the distance the transcript
/// moves, so it travels at the speed of the text and disappears under the
/// player — and comes straight back the moment you scroll the other way,
/// without a trip to the top.
///
/// It is **stacked over** the transcript rather than sitting above it in a
/// column, which is what makes the one-to-one tracking possible. It also fixes
/// a bug the collapsing version had: shrinking a widget in the column changed
/// the viewport height, which changed `maxScrollExtent`, which could clamp the
/// offset back to zero — and zero reads as "at the top", so the bar reopened,
/// the viewport shrank again, and the two chased each other for as long as a
/// finger was down. An overlay never touches the scroll extent, so that loop
/// cannot form.
class _TranscriptViewState extends ConsumerState<_TranscriptView>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _barKey = GlobalKey();

  /// Reaches whichever `_InlineField` is currently open, from outside the
  /// widget that owns it, so it can be flushed *before* something replaces or
  /// clears `InlineEdit`'s span -- see `_InlineFieldState.dispose()` for why
  /// that can't happen reactively instead. Shared with `_EditScopeBanner` and
  /// `_WordFlowContent`, the other two places that mutate that span.
  final _inlineFieldKey = GlobalKey<_InlineFieldState>();

  /// Drives the bar in and out when edit mode is entered or left.
  ///
  /// Separate from the scroll, which moves the bar too. Entering edit mode used
  /// to make the control appear from nothing between two frames, which reads as
  /// a glitch rather than as a thing arriving; it now slides down into place
  /// and pushes the transcript down with it, and reverses on the way out.
  late final AnimationController _toggle = AnimationController(
    duration: const Duration(milliseconds: 220),
    vsync: this,
  )..addListener(() => setState(() {}));

  late final Animation<double> _shown = CurvedAnimation(
    parent: _toggle,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// How much of the bar the *scroll* has taken off the top, between zero and
  /// [_barHeight]. Independent of [_toggle], which handles arriving and
  /// leaving.
  double _hidden = 0;

  /// Measured after layout, because the bar's height depends on the scope —
  /// picking Speakers adds a row of swatches — and on the text scale.
  double _barHeight = 0;

  double _lastPixels = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
    // Opening a project already in edit mode should not play an entrance.
    if (ref.read(transcriptEditModeProvider)) _toggle.value = 1;
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_followScroll)
      ..dispose();
    _toggle.dispose();
    super.dispose();
  }

  void _followScroll() {
    if (!_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;
    final delta = pixels - _lastPixels;
    _lastPixels = pixels;

    // Overscrolling past the top always brings it fully back, so a flick that
    // lands at the top cannot leave the controls stranded off screen.
    final next = pixels <= 0 ? 0.0 : (_hidden + delta).clamp(0.0, _barHeight);
    if (next != _hidden) setState(() => _hidden = next);
  }

  /// Re-reads the bar's height after every layout.
  ///
  /// Cheap, and it has to be every time: the bar grows when the Speakers scope
  /// reveals its swatches and when the system text scale changes, and a stale
  /// height would leave the transcript padded for the wrong thing.
  void _measureBar() {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? _barHeight;
    if (height == _barHeight) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _barHeight = height;
        _hidden = _hidden.clamp(0.0, height);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final words = ref.watch(transcriptWordsProvider(widget.transcript.id));

    // `listen` rather than `watch`: starting an animation is a side effect, and
    // a controller told to run during a build would rebuild inside its own
    // build. This fires after the frame instead.
    ref.listen<bool>(transcriptEditModeProvider, (_, editing) {
      if (editing) {
        _hidden = 0;
        _toggle.forward();
      } else {
        // An open field that outlived edit mode would hold the keyboard up
        // over a transcript that is no longer editable. Flush it first, while
        // it is still mounted -- see `_InlineFieldState.dispose()`.
        _inlineFieldKey.currentState?.flush();
        ref.read(inlineEditProvider.notifier).close();
        _toggle.reverse();
      }
    });

    final shown = _shown.value;
    // Stays mounted through the exit animation, and through the entrance
    // before the first frame of it has been measured.
    final barPresent = shown > 0 || ref.watch(transcriptEditModeProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBar());

    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CenteredMessage(message: '$error'),
      data: (items) {
        if (items.isEmpty) {
          return _CenteredMessage(message: l10n.transcriptEmpty);
        }

        // Every speaker this transcript actually contains, in the order they
        // first appear. That is the set a turn can be reassigned to: inventing
        // a speaker who never spoke would produce a colour and a label with
        // nothing behind them.
        final speakers = <int>{
          for (final word in items)
            if (int.tryParse(word.speakerId ?? '') case final int speaker)
              speaker,
        }.toList();

        // The word count scrolls with the text rather than being pinned above
        // it. Pinned, it put a second horizontal edge between the player and
        // the transcript, so the one shadow that should mark that boundary
        // became two bands forty pixels apart. It is a fact about the
        // transcript, not a control, and nothing is lost by letting it go.
        return Stack(
                children: [
                  Positioned.fill(
                    child: _WordFlow(
                      clipId: widget.clipId,
                      words: items,
                      controller: _scroll,
                      heading: l10n.wordCount(items.length),
                      // Starts the text below the bar rather than behind it.
                      // Constant while scrolling, which is precisely why the
                      // scroll extent cannot move underneath the gesture; it
                      // only changes while the bar is arriving or leaving, and
                      // then the text travels with it.
                      topInset: _barHeight * shown,
                      inlineFieldKey: _inlineFieldKey,
                    ),
                  ),
                  if (barPresent)
                    Positioned(
                      left: 0,
                      right: 0,
                      // Two movements on one axis: how far the scroll has
                      // pushed it up, plus how far it still is from having
                      // arrived.
                      top: -(_hidden + _barHeight * (1 - shown)),
                      child: KeyedSubtree(
                        key: _barKey,
                        child: _EditScopeBanner(
                          transcriptId: widget.transcript.id,
                          speakers: speakers,
                          inlineFieldKey: _inlineFieldKey,
                        ),
                      ),
                    ),
          ],
        );
      },
    );
  }
}

/// The transcript itself: a reflowing run of words, each one a seek target.
class _WordFlow extends ConsumerWidget {
  const _WordFlow({
    required this.clipId,
    required this.words,
    required this.controller,
    required this.topInset,
    required this.heading,
    required this.inlineFieldKey,
  });

  final String clipId;
  final List<Word> words;

  /// Owned by [_TranscriptViewState], which needs it to drive the edit bar.
  final ScrollController controller;

  /// Room at the top for the overlaid edit bar.
  final double topInset;

  /// The word count, as the first thing in the scroll.
  final String heading;

  /// Owned by [_TranscriptViewState] and shared with [_EditScopeBanner]; see
  /// `_CueLine.inlineFieldKey`.
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(mediaPlayerProvider(clipId)).value;

    // Without a player there is nothing to highlight against, so the words
    // render as a plain transcript instead of failing.
    if (player == null) {
      return _WordFlowContent(
        clipId: clipId,
        words: words,
        positionMs: null,
        controller: controller,
        topInset: topInset,
        heading: heading,
        inlineFieldKey: inlineFieldKey,
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) => _WordFlowContent(
        clipId: clipId,
        words: words,
        positionMs: value.position.inMilliseconds,
        controller: controller,
        topInset: topInset,
        heading: heading,
        inlineFieldKey: inlineFieldKey,
      ),
    );
  }
}

class _WordFlowContent extends ConsumerWidget {
  const _WordFlowContent({
    required this.clipId,
    required this.words,
    required this.positionMs,
    required this.controller,
    required this.topInset,
    required this.heading,
    required this.inlineFieldKey,
  });

  final String clipId;
  final List<Word> words;
  final int? positionMs;
  final ScrollController controller;
  final double topInset;
  final String heading;
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(transcriptEditModeProvider);
    // Only meaningful in Speakers scope, and null everywhere else, so a stale
    // anchor cannot mark a word after the mode has moved on.
    final anchor = editing &&
            ref.watch(transcriptEditScopeSettingProvider) ==
                TranscriptEditScope.speakers
        ? ref.watch(speakerRangeAnchorProvider)
        : null;
    final activeIndex =
        positionMs == null || editing ? -1 : _activeWordIndex(words, positionMs!);

    final turns = groupIntoSpeakerTurns(words);

    final speakers = <int>{
      for (final word in words)
        if (int.tryParse(word.speakerId ?? '') case final int speaker) speaker,
    }.toList();

    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs + topInset,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              heading,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          ..._cueRows(
            context,
            ref,
            turns: turns,
            speakers: speakers,
            activeIndex: activeIndex,
            editing: editing,
            anchor: anchor,
          ),
        ],
      ),
    );
  }

  /// Every caption line in the transcript, in order, separated by one rule.
  ///
  /// **Flat on purpose.** An earlier pass nested the lines under a per-turn
  /// widget with a speaker chip above each group and extra air between groups.
  /// That gave the page two rhythms — a tight one inside a turn and a loose one
  /// between turns — so the eye read the gaps as structure and the transcript
  /// came out lumpy. Every line now sits the same distance from its neighbours
  /// whether or not the speaker changed, and **the timestamp carries the
  /// speaker** instead: coloured from the same `SpeakerPalette` the captions use,
  /// so who is talking is legible without a label taking up a line.
  ///
  /// The unit is a caption cue, not a paragraph and not a sentence.
  /// `groupIntoCues` is the identical call the caption overlay makes, so a row
  /// here is exactly one line as it appears over the video — same punctuation
  /// breaks, same length and gap limits. Cues never straddle a speaker, since
  /// that grouping breaks on speaker change before anything else, so slicing per
  /// turn gives the same answer as grouping the whole transcript.
  /// Whether [open] covers the whole of [cue].
bool _covers(({int from, int to})? open, CaptionCue cue) =>
    open != null &&
    open.from <= cue.words.first.position &&
    open.to >= cue.words.last.position;

List<Widget> _cueRows(
      BuildContext context,
      WidgetRef ref, {
      required List<SpeakerTurn> turns,
      required List<int> speakers,
      required int activeIndex,
      required bool editing,
      required int? anchor,
    }) {
      final scope = ref.watch(transcriptEditScopeSettingProvider);
      final open = ref.watch(inlineEditProvider);
      final rows = <Widget>[];

    for (final turn in turns) {
      final cues = groupIntoCues(turn.words);

      // `groupIntoCues` partitions the words in order and drops none, so a
      // running total is the offset of each cue's first word within the turn.
      var offset = 0;
      for (final cue in cues) {
        final base = offset;
        if (rows.isNotEmpty) rows.add(const _CueRule());

        rows.add(
          _CueLine(
            cue: cue,
            baseOffset: base,
            open: open,
            inlineFieldKey: inlineFieldKey,
            // Captured from this build's `open`, not re-read live: this field
            // can be flushed pre-emptively (see `_correct`) after the
            // provider has already moved on to a different span, and reading
            // the provider at that point would commit this text into the
            // *new* span instead of the one this field was opened for.
            onCommit: (text) => _commit(
              ref,
              transcriptId: turn.words.first.transcriptId,
              from: open!.from,
              to: open.to,
              text: text,
            ),
            turnStartIndex: turn.startIndex,
            activeIndex: activeIndex,
            editing: editing,
            anchor: anchor,
            speaker: turn.speaker,
            // In Line scope the unit is the row, so the row is the target
            // — including the empty space after a short line. Tapping to the
            // right of "right?" did nothing before, because a `TextSpan`'s
            // recogniser only covers its own glyphs.
            //
            // Null in Word scope, where empty space names no word, and null on
            // the row already open, where the taps belong to the field.
            onRowTap: editing &&
                    scope == TranscriptEditScope.line &&
                    !_covers(open, cue)
                ? () => _correct(context, ref, turn, base, cue: cue)
                : null,
            onWordTap: (o) => editing
                ? _correct(context, ref, turn, o, cue: cue)
                : ref
                    .read(mediaPlayerProvider(clipId).notifier)
                    .seekToWord(turn.words[o].startMs),
            // The timestamp is the speaker signal, so in edit mode it is also
            // the speaker control -- the thing you tap is the thing you are
            // changing, which is the same rule the removed chip followed. It is
            // the only route to reassigning a turn and to renaming a speaker,
            // both of which used to hang off that chip.
            onStampTap: editing && speakers.length > 1
                ? () => _reassignTurn(context, ref, turn, speakers)
                : () => ref
                    .read(mediaPlayerProvider(clipId).notifier)
                    .seekToWord(cue.startMs),
          ),
        );
        offset += cue.words.length;
      }
    }

    return rows;
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
    int offset, {
    required CaptionCue cue,
  }) async {
    final scope = ref.read(transcriptEditScopeSettingProvider);

    if (scope == TranscriptEditScope.speakers) {
      await _assignSpeaker(ref, turn.words[offset]);
      return;
    }

    // **Line means the row, not the sentence.** It used to mean the sentence
    // containing the tapped word, which was right when the transcript was one
    // undivided run of prose. Now a row is a caption cue, and a sentence can
    // span two of them — so a sentence-sized target opened a field on *both*
    // rows, each holding half the span and each able to commit over the other.
    // The unit the user points at is the unit they should get.
    final slice = switch (scope) {
      TranscriptEditScope.word => [turn.words[offset]],
      TranscriptEditScope.line => cue.words,
      TranscriptEditScope.speakers => const <Word>[],
    };
    if (slice.isEmpty) return;

    // Tapping straight from one word/line to another replaces the open span
    // without the first field ever losing focus, so nothing else would
    // commit it. Flush it now, while it is still mounted and a `ref.read`
    // inside its `onCommit` is safe -- `dispose()` explains why this can't
    // be left to happen reactively once the span has already moved on.
    inlineFieldKey.currentState?.flush();

    ref.read(inlineEditProvider.notifier).open(
          from: slice.first.position,
          to: slice.last.position,
        );
  }

  /// Writes a retyped span back, and closes the editor.
  ///
  /// The repository decides whether anything actually changed, so a field
  /// dismissed with the text untouched costs no undo slot. A single-word span
  /// needs no special case: `replaceSentence` takes `from == to`, and the
  /// planner then divides that one word's span and nothing else.
  static Future<void> _commit(
    WidgetRef ref, {
    required String transcriptId,
    required int from,
    required int to,
    required String text,
  }) async {
    ref.read(inlineEditProvider.notifier).close();
    await ref.read(transcriptRepositoryProvider).replaceSentence(
          transcriptId: transcriptId,
          fromPosition: from,
          toPosition: to,
          text: text,
        );
  }

  /// One half of a two-tap speaker range.
  ///
  /// The first tap remembers where the range starts; the second applies it and
  /// forgets. Tapping the anchor itself assigns that one word, which is the
  /// common case of moving a single stray word off the wrong speaker.
  ///
  /// Two taps rather than a drag because the transcript scrolls vertically and
  /// a paint stroke would fight the scroll gesture. The range spans the
  /// transcript rather than being clamped to a turn: splitting means taking
  /// *part* of a turn, and sweeping across two half-turns to merge them is
  /// equally legitimate.
  Future<void> _assignSpeaker(WidgetRef ref, Word word) async {
    final anchor = ref.read(speakerRangeAnchorProvider);
    if (anchor == null) {
      ref.read(speakerRangeAnchorProvider.notifier).set(word.position);
      return;
    }

    final from = anchor < word.position ? anchor : word.position;
    final to = anchor < word.position ? word.position : anchor;
    ref.read(speakerRangeAnchorProvider.notifier).clear();

    // One call, so one undo step for the whole range. `SpeakerEdit` records the
    // prior speaker of every position it covers, which is what lets undo put a
    // split back together even though the range was never uniform.
    await ref.read(transcriptRepositoryProvider).reassignSpeaker(
          transcriptId: word.transcriptId,
          fromPosition: from,
          toPosition: to,
          speaker: ref.read(selectedSpeakerProvider),
        );
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
        transcriptId: turn.words.first.transcriptId,
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

/// The hairline between two cues.
///
/// Faded rather than a full-strength divider. The page already carries speaker
/// chips and a playhead highlight; a solid rule between every line would
/// out-shout both and turn the transcript back into a grid. This should read
/// as a seam, not as a border.
class _CueRule extends StatelessWidget {
  const _CueRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ColoredBox(
        color: _hairline(Theme.of(context)),
        child: const SizedBox(height: _hairlineWidth, width: double.infinity),
      ),
    );
  }
}

/// One caption line: its start time, then its words.
///
/// The timestamp is a control rather than a label — tapping it seeks there,
/// which is how a transcript panel is expected to behave. It works in edit
/// mode too, since moving the playhead never changes the transcript.
///
/// State exists only to own the tap recognisers. A `TapGestureRecognizer` holds
/// a gesture-arena entry and must be disposed, and there is one per word.
class _CueLine extends StatefulWidget {
  const _CueLine({
    required this.cue,
    required this.baseOffset,
    required this.turnStartIndex,
    required this.activeIndex,
    required this.editing,
    required this.anchor,
    required this.speaker,
    required this.open,
    required this.onRowTap,
    required this.onWordTap,
    required this.onStampTap,
    required this.onCommit,
    required this.inlineFieldKey,
  });

  final CaptionCue cue;

  /// Offset of this cue's first word within its turn.
  final int baseOffset;

  /// Index of the turn's first word within the whole transcript.
  final int turnStartIndex;

  /// Index *within the whole transcript* of the word under the playhead.
  final int activeIndex;

  final bool editing;
  final int? anchor;

  /// Diarization's speaker index, or null on a transcript that was never
  /// diarized — in which case the timestamp stays plain, because a colour
  /// standing for nothing is worse than no colour.
  final int? speaker;

  /// The span of positions open for retyping anywhere in the transcript, or
  /// null. Compared against this cue's own words to decide whether the row
  /// draws text or a field.
  final ({int from, int to})? open;

  /// Opens this row for retyping from anywhere in it, or null when a tap on
  /// empty space should do nothing.
  final VoidCallback? onRowTap;

  final void Function(int offset) onWordTap;
  final VoidCallback onStampTap;
  final ValueChanged<String> onCommit;

  /// Shared across every `_InlineField` this transcript can build. At most
  /// one is ever open at a time (`InlineEdit` holds a single span), so one
  /// key is enough to let a caller reach the live field and flush it before
  /// replacing it — see `_WordFlowContent._correct`.
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  @override
  State<_CueLine> createState() => _CueLineState();
}

class _CueLineState extends State<_CueLine> {
  /// Room for `mm:ss`, scaled with the text so a large accessibility setting
  /// cannot clip it. Every row has to agree on the same gutter or the left
  /// edge of the transcript goes ragged, so this is a shared constant rather
  /// than an intrinsic measurement.
  static const double _stampWidth = 46;

  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _releaseRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    // The spans are rebuilt every frame the playhead moves, so the previous
    // frame's recognisers go with them. Holding them instead would leak one
    // gesture-arena entry per word per frame.
    _releaseRecognizers();

    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          // Opaque, so the whole gutter is the target rather than the five
          // glyphs of the timestamp.
          behavior: HitTestBehavior.opaque,
          onTap: widget.onStampTap,
          child: SizedBox(
            width: scaler.scale(_stampWidth),
            child: Padding(
              // Nudged down so the smaller timestamp sits with the first line
              // of transcript rather than above it.
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                _formatPosition(Duration(milliseconds: widget.cue.startMs)),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _stampColour(theme),
                  fontWeight:
                      widget.speaker == null ? null : FontWeight.w700,
                  // Says the stamp is actionable in edit mode, matching the
                  // words beside it, which are underlined for the same reason.
                  decoration:
                      widget.editing ? TextDecoration.underline : null,
                  decorationStyle: TextDecorationStyle.dotted,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: widget.onRowTap == null
              ? _body(theme)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onRowTap,
                  child: _body(theme),
                ),
        ),
      ],
    );
  }

  /// Either the cue's words, or a field standing in for the part being
  /// retyped.
  ///
  /// Two shapes, because the two scopes mean different things. Retyping a
  /// **line** replaces the row wholesale: the correction usually spans several
  /// words -- "brainbeats" for "praying beads" cannot be typed one word at a
  /// time -- so the field has to hold the run. Retyping a **word** leaves the
  /// rest of the line set as prose and opens a box around that one word, which
  /// keeps the sentence readable while its one wrong word is fixed.
  Widget _body(ThemeData theme) {
    final open = widget.open;
    final words = widget.cue.words;

    if (open != null &&
        open.from <= words.first.position &&
        open.to >= words.last.position) {
      return _InlineField(
        key: widget.inlineFieldKey,
        sessionKey: (open.from, open.to),
        initial: words.map((w) => w.word).join(' '),
        style: theme.textTheme.bodyLarge!,
        onCommit: widget.onCommit,
      );
    }

    return Text.rich(TextSpan(children: _spans(theme)));
  }

  /// The speaker's colour, in the version that can be read as text.
  ///
  /// Two passes got this wrong in opposite directions. Fitting each hue by
  /// blending it toward black made the light theme readable and muddy — amber
  /// went olive, cyan went teal — because blending with black desaturates.
  /// Using the raw fills in both themes kept them vivid and left amber at
  /// 1.28:1 on the cream ground, which is close to invisible.
  ///
  /// `SpeakerPalette.textColorFor` is the third answer: a purpose-built set
  /// for the light ground, full saturation at the lightest tone that clears
  /// 4.5:1, with the dark theme still using the fills unchanged.
  Color _stampColour(ThemeData theme) {
    return SpeakerPalette.textColorFor(
      widget.speaker,
      brightness: theme.brightness,
      fallback: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );
  }

  List<InlineSpan> _spans(ThemeData theme) {
    final base = theme.textTheme.bodyLarge!;
    final words = widget.cue.words;
    final spans = <InlineSpan>[];

    for (final (offset, word) in words.indexed) {
      final index = widget.turnStartIndex + widget.baseOffset + offset;
      final active = index == widget.activeIndex;
      final anchored = word.position == widget.anchor;

      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWordTap(widget.baseOffset + offset);
      _recognizers.add(recognizer);

      // A single word open for retyping becomes a field in the middle of the
      // prose. `WidgetSpan` is what makes that possible: it takes part in line
      // breaking like any other word, so the sentence still wraps correctly
      // around the box.
      if (widget.open case final open?
          when open.from == word.position && open.to == word.position) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: IntrinsicWidth(
              child: _InlineField(
                key: widget.inlineFieldKey,
                sessionKey: (open.from, open.to),
                initial: word.word,
                style: base,
                onCommit: widget.onCommit,
              ),
            ),
          ),
        );
        if (offset != words.length - 1) {
          spans.add(TextSpan(text: ' ', style: base));
        }
        continue;
      }

      spans.add(
        TextSpan(
          text: word.word,
          recognizer: recognizer,
          style: base.copyWith(
            backgroundColor: switch ((anchored, active)) {
              // Selection, so it takes the selection colour rather than the
              // call-to-action fill.
              (true, _) => theme.colorScheme.secondary,
              (false, true) => theme.colorScheme.primaryContainer,
              _ => null,
            },
            color: switch ((anchored, active)) {
              (true, _) => theme.colorScheme.onSecondary,
              (false, true) => theme.colorScheme.onPrimaryContainer,
              _ => null,
            },
            fontWeight: anchored ? FontWeight.w700 : null,
            // Edit mode has to say "these words are targets, not seek points".
            // A per-word tint did that when words were tiles and cannot here:
            // the gaps between them stay untinted, so a line comes out
            // striped. An underline is the text-native way to say it and
            // leaves the page reading as prose.
            decoration: widget.editing && !anchored
                ? TextDecoration.underline
                : null,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: theme.colorScheme.outline.withValues(alpha: 0.55),
          ),
        ),
      );

      // Plain spaces between words, matching how the caption and export paths
      // already join them. Kept outside the word spans so a highlight ends
      // where the word does instead of trailing into the gap.
      if (offset != words.length - 1) {
        spans.add(TextSpan(text: ' ', style: base));
      }
    }

    return spans;
  }
}

/// The transcript line, or word, being retyped — in place.
///
/// **No dialog.** Retyping is a keyboard task and a keyboard already covers
/// half the screen; a modal on top of that hides the very context the
/// correction is being made against. Here the surrounding lines stay put and
/// readable, and the only new thing on screen is the keyboard.
///
/// Set in the transcript's own type so the words do not jump size or weight
/// the moment they become editable.
class _InlineField extends StatefulWidget {
  const _InlineField({
    super.key,
    required this.sessionKey,
    required this.initial,
    required this.style,
    required this.onCommit,
  });

  /// Identifies *which* span this field is editing -- `(from, to)` works,
  /// since records compare by value.
  ///
  /// Every `_InlineField` in the transcript shares one `GlobalKey` (see
  /// `_CueLine.inlineFieldKey`), so a caller elsewhere can reach and flush
  /// whichever one is currently open. That means a tap that moves straight
  /// from one word to another **reuses this State object** for what is
  /// logically a new editing session, rather than disposing it and creating
  /// a fresh one -- Flutter has no way to know the two widgets aren't the
  /// same field just because their `initial` text differs. `didUpdateWidget`
  /// compares this key and resets the session when it changes.
  final Object sessionKey;

  final String initial;
  final TextStyle style;
  final ValueChanged<String> onCommit;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      // Opens with the run selected, so the common case — the engine heard the
      // wrong thing entirely — is one gesture: start typing and it is replaced.
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  final _focus = FocusNode();

  /// Guards the two scrolls, each of which must happen once per opening rather
  /// than on every rebuild the playhead causes.
  bool _shown = false;
  bool _raised = false;

  /// Guards against committing twice: once through the normal blur/submit
  /// path, and again if a caller also calls [flush] pre-emptively before
  /// tearing the field down.
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);

    // Bring the row into view straight away, keyboard or not. A row can be
    // half off the bottom when it is tapped, and on a device whose keyboard
    // floats -- Gboard's floating mode, a physical keyboard -- no inset ever
    // arrives to trigger the second scroll below.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shown) return;
      _shown = true;
      _bringIntoView();
    });
  }

  @override
  void didUpdateWidget(covariant _InlineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionKey == oldWidget.sessionKey) return;

    // The shared `GlobalKey` handed this widget the *previous* field's
    // State. Start a fresh session rather than carrying over its text,
    // commit flag and scroll guards -- otherwise the box for the new word
    // would open still showing the old one's (possibly edited) content.
    _committed = false;
    _shown = false;
    _raised = false;
    _controller
      ..text = widget.initial
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      );
    // `autofocus` only fires when an element is first inserted, and this one
    // is being reused, so the keyboard has to be asked to stay up explicitly.
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shown) return;
      _shown = true;
      _bringIntoView();
    });
  }

  @override
  void dispose() {
    // Deliberately does **not** flush here. A field can be torn down without
    // ever losing focus first -- tapping a different word or line, switching
    // Line/Word/Speakers scope, and leaving edit mode all replace or clear
    // `InlineEdit`'s span directly -- and committing needs `ref.read`, which
    // Flutter refuses to run during `dispose()` ("Looking up a deactivated
    // widget's ancestor is unsafe"). Those three call sites flush *this*
    // field through [flush], via `inlineFieldKey`, before they touch the
    // provider -- i.e. while the field is still fully mounted and a lookup is
    // safe -- so by the time `dispose()` runs there is nothing left to do.
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Losing focus commits rather than discards.
  ///
  /// Tapping away from a half-typed correction almost always means "that will
  /// do", not "throw it away", and there is no visible Save to press instead.
  /// Nothing is risked by being wrong: the repository compares the text and
  /// spends no undo slot when it is unchanged, and a real change is one undo
  /// away.
  void _onFocusChange() {
    if (!_focus.hasFocus && mounted) flush();
  }

  /// Commits whatever is typed, once.
  ///
  /// Called from the normal blur/submit path, and pre-emptively (via
  /// `inlineFieldKey.currentState?.flush()`) by anything about to replace or
  /// clear the open span — see `dispose()` for why it can't wait and do this
  /// itself. Idempotent, so a normal blur followed by the field's own
  /// teardown never double-commits.
  void flush() {
    if (_committed) return;
    _committed = true;
    widget.onCommit(_controller.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Again once the keyboard has taken its space, because that changes what
    // "visible" means: the scaffold shrinks the body, and a row that was in
    // view a moment ago can now be underneath the keys. Gated on a real inset,
    // so a floating keyboard -- which covers nothing -- does not scroll the
    // page for no reason.
    if (_raised || MediaQuery.viewInsetsOf(context).bottom == 0) return;
    _raised = true;

    WidgetsBinding.instance.addPostFrameCallback((_) => _bringIntoView());
  }

  void _bringIntoView() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      // A third of the way down rather than centred: the line being corrected
      // reads better with the lines that precede it still in view above it.
      alignment: 0.3,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      style: widget.style,
      // Grows with the text rather than scrolling a line sideways: the point
      // of retyping a line is seeing the whole of it.
      maxLines: null,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => flush(),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        // A box, not a fill. The fill used to carry the "this is being
        // edited" signal, but it borrowed `primaryContainer` -- the same
        // colour the playhead highlight uses for "this is playing" -- so the
        // two unrelated meanings read as one. The border alone is enough, and
        // it uses the accent (`colorScheme.primary`): already tuned per
        // theme against its own ground (`AppTheme._yellow` / `_blue`, chosen
        // in `AppTheme.light/dark`), so it never has to share a colour with
        // anything else on screen.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.xs),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

/// The speakers a tap can assign, and the one it will.
///
/// Offers the transcript's own speakers plus **one more**, up to
/// `SpeakerPalette.length`. Without that extra slot a block diarization gave
/// entirely to one person could never be split: the second speaker has no
/// words yet, so nothing would offer them. A speaker added this way has no
/// acoustic evidence behind it, which is fine for the same reason reassignment
/// exists at all — the person listening is the authority.
class _SpeakerPicker extends ConsumerWidget {
  const _SpeakerPicker({
    required this.speakers,
    required this.current,
    required this.transcriptId,
  });

  final List<int> speakers;
  final int? current;
  final String transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = ref.watch(speakerNamesProvider(transcriptId));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
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
              title: Text(
                names.labelFor(
                  speaker,
                  defaultLabel: l10n.speakerLabel(speaker + 1),
                ),
              ),
              // Two actions on one row: the row assigns, the pencil renames.
              // Renaming lives here because this sheet is already where a user
              // comes to think about who is who.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (speaker == current) const Icon(Icons.check),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: l10n.renameSpeakerAction,
                    onPressed: () => _rename(context, ref, speaker, names),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).pop(speaker),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Gives one speaker a name, or clears it back to the numbered default.
  ///
  /// Not routed through the undo log. The log replays edits to word rows; a
  /// name lives on the transcript, and retyping it is its own undo. Putting it
  /// in the history would also mean undoing a typo had to step back through a
  /// renaming first.
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    int speaker,
    SpeakerNames names,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _SpeakerNameEditor(
        speaker: speaker,
        initial: names[speaker] ?? '',
      ),
    );
    if (name == null) return;

    await ref.read(transcriptRepositoryProvider).renameSpeaker(
          transcriptId: transcriptId,
          speaker: speaker,
          name: name,
        );
    // The label the export and the transcript will now use.
    debugPrint('Renamed speaker ${speaker + 1} to '
        '"${name.trim().isEmpty ? l10n.speakerLabel(speaker + 1) : name.trim()}"');
  }
}

/// One text field for a speaker's name.
///
/// An empty field is meaningful rather than invalid: it clears the name and
/// restores `Speaker N`, which the note under the field says outright so the
/// user does not have to discover it.
class _SpeakerNameEditor extends StatefulWidget {
  const _SpeakerNameEditor({required this.speaker, required this.initial});

  final int speaker;
  final String initial;

  @override
  State<_SpeakerNameEditor> createState() => _SpeakerNameEditorState();
}

class _SpeakerNameEditorState extends State<_SpeakerNameEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

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
      title: Text(l10n.renameSpeakerTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.renameSpeakerHint(widget.speaker + 1),
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
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.editSave),
        ),
      ],
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
