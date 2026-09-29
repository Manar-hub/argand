import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_cue.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/theme/app_controls.dart';
import '../../core/theme/argand_logo.dart';
import '../../core/theme/app_color_picker.dart';
import '../../core/theme/app_icons.dart';
import '../../core/timeline/translation_texts.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transcript/speaker_names.dart';
import '../../core/transcript/speaker_turns.dart';
import '../../core/video/export_options.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'editor_mode_controller.dart';
import 'export_sheet.dart';
import 'video_settings_panel.dart';
import 'video_settings.dart';
import 'media_player_controller.dart';
import 'project_fullscreen.dart';
import 'subtitle_export_controller.dart';
import 'timeline_screen.dart';
import 'transcript_edit_controller.dart';
import 'transcript_repository.dart';
import 'video_export_controller.dart';
import 'video_canvas.dart';

/// One project: its media, and either the transcript as tappable words
/// (Script mode) or the clip/track view (Timeline mode).
class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({
    required this.projectId,
    this.initialMode,
    this.initialSeek,
    super.key,
  });

  final String projectId;

  /// Which mode to open in, chosen by the library's two entry points.
  final EditorMode? initialMode;

  /// Where to put the playhead once the media is ready: a clip and a time in
  /// its own media, as a library search that found words hands over. Null
  /// opens wherever the project normally opens.
  final ({String clipId, int startMs})? initialSeek;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  ProviderSubscription<AsyncValue<VideoPlayerController>>? _seekOnReady;

  @override
  void initState() {
    super.initState();

    if (widget.initialSeek case final at?) {
      Future.microtask(() {
        if (mounted) _openAt(at);
      });
    }

    final initial = widget.initialMode;
    if (initial != null) {
      // Already known -- the entry point decided, so there is nothing to look
      // up.
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(sessionEditorModeProvider(widget.projectId).notifier)
            .select(initial);
      });
      return;
    }

    // Reopened from the list: nothing decided which mode to show, so ask
    // Settings for whatever this project was left in last.
    _restoreLastMode();
  }

  /// Shows [at]'s clip and, once its player has loaded, moves both the media
  /// and the timeline's playhead onto that moment.
  void _openAt(({String clipId, int startMs}) at) {
    ref.read(selectedClipProvider(widget.projectId).notifier).select(at.clipId);
    _seekOnReady = ref.listenManual(
      mediaPlayerProvider(at.clipId),
      (_, next) {
        if (!next.hasValue) return;
        _seekOnReady?.close();
        _seekOnReady = null;
        ref.read(mediaPlayerProvider(at.clipId).notifier).seekToWord(at.startMs);
        final projectMs = ref
            .read(projectTimelineProvider(widget.projectId))
            .projectMsOf(clipId: at.clipId, clipMs: at.startMs);
        if (projectMs != null) {
          ref
              .read(timelinePlayheadProvider(widget.projectId).notifier)
              .moveTo(projectMs);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _seekOnReady?.close();
    super.dispose();
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

    // The video render reports the same way, but separately: it can run for
    // minutes, so its outcome routinely arrives long after the sheet is gone.
    ref.listen(videoExportControllerProvider(widget.projectId),
        (previous, next) {
      final message = switch (next) {
        VideoExportDone(:final video) => l10n.exportVideoSaved(video.name),
        VideoExportEmpty() => l10n.exportVideoEmpty,
        VideoExportFailed() => l10n.exportVideoFailed,
        _ => null,
      };
      if (message == null) return;

      ref
          .read(videoExportControllerProvider(widget.projectId).notifier)
          .reset();
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
          // Export sits in both modes and needs no transcript.
          if (!editing)
            _ExportButton(projectId: widget.projectId),
          // Script mode's own controls. Timeline mode has its own toolbar
          // for Edit and Captions, so none of these apply there.
          if (mode == EditorMode.script) ...[
            // History belongs to editing, so it appears with it. Showing two
            // permanently-disabled buttons during playback would add weight
            // to the bar for a mode in which nothing can be edited or undone.
            if (editing) HistoryControls(projectId: widget.projectId),
            IconButton(
              icon: Icon(editing ? Icons.done : Icons.edit_outlined),
              tooltip: editing ? l10n.editModeDisable : l10n.editModeEnable,
              onPressed: () =>
                  ref.read(transcriptEditModeProvider.notifier).toggle(),
            ),
          ],
        ],
        // No mode switch up here any more.
      ),
      body: project.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CenteredMessage(message: '$error'),
        data: (value) => value == null
            ? _CenteredMessage(message: l10n.errorTitle)
            // A cross-fade rather than a cut. Both modes play through the
            // same shared decoder, keyed by the media file, so the picture
            // does not reload as one mode gives way to the other.
            : AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(mode),
                  child: mode == EditorMode.script
                      ? _ProjectBody(project: value)
                      : TimelineBody(project: value),
                ),
              ),
      ),
    );
  }
}

/// Opens the export sheet.
class _ExportButton extends ConsumerWidget {
  const _ExportButton({required this.projectId});

  /// Every export is project-wide: the video renders the whole timeline, and
  /// the subtitle files follow it, so none of them depends on which clip is
  /// selected.
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final running = ref.watch(subtitleExporterProvider) is SubtitleExportRunning ||
        ref.watch(videoExportControllerProvider(projectId))
            is VideoExportRunning;

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
      icon: const AppIcon(AppGlyph.export),
      tooltip: l10n.exportAction,
      onPressed: () => _export(context, ref, l10n),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final decision = await showExportSheet(context, projectId);
    if (decision == null || !context.mounted) return;

    switch (decision) {
      case VideoExportDecision(:final options):
        await _renderVideo(context, ref, l10n, projectId, options);

      case SubtitleExportDecision(
          :final format,
          :final includeSpeakers,
          :final lineLength,
          :final includeTranslation,
        ):
        await ref.read(subtitleExporterProvider.notifier).export(
              projectId: projectId,
              format: format,
              lineLength: lineLength,
              // Built here rather than in the controller: "Speaker 1" is
              // interface text, and CLAUDE.md 4 keeps those out of the service
              // layer. The controller puts any renamed speaker's name first.
              defaultSpeakerLabel: includeSpeakers
                  ? (speaker) => l10n.speakerLabel(speaker + 1)
                  : null,
              includeTranslation: includeTranslation,
            );
    }
  }
}

/// Renders the video the sheet decided on, with its progress on screen.
Future<void> _renderVideo(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  String projectId,
  ExportOptions options,
) async {
  // **Started without awaiting.** The progress window has to be on screen
  // while the render runs; awaiting the render first would put it up only once
  // there was nothing left to show.
  // The watermark as the preview draws it: the lockup, its hand in the
  // action colour. Only needed when a watermark is burned in.
  final watermarkPng = options.watermark
      ? await ArgandLogo.watermarkPng(
          body: Colors.white,
          hand: Theme.of(context).colorScheme.primary,
          plate: watermarkPlateColor,
          padFraction: watermarkPadFraction,
        )
      : null;
  if (!context.mounted) return;
  final render = ref
      .read(videoExportControllerProvider(projectId).notifier)
      .export(
        options: options,
        defaultSpeakerLabel: (speaker) => l10n.speakerLabel(speaker + 1),
        watermarkPng: watermarkPng,
      );

  final cancelled = await showExportProgress(context, projectId);
  await render;

  if (cancelled && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.exportCancelled)));
  }
}

/// Chooses how much of the transcript one tap opens, and explains the gestures.
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

    // Opaque, and its own gutters.
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
            offset: const Offset(0, appHairlineWidth),
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
            AppSegmentRow<TranscriptEditScope>(
              selected: scope,
              items: {
                TranscriptEditScope.line: l10n.editScopeLine,
                TranscriptEditScope.word: l10n.editScopeWord,
                TranscriptEditScope.speakers: l10n.editScopeSpeakers,
              },
              onSelected: (value) {
                // Neither a pending anchor nor an open field may survive the
                // scope it was made in: the anchor would turn the next tap
                // anywhere into a range assignment.
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
              _SpeakerNamesToggle(transcriptId: transcriptId),
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
                  AppPressDown(
                    child: TextButton(
                      onPressed: () => ref
                          .read(speakerRangeAnchorProvider.notifier)
                          .clear(),
                      child: Text(l10n.editCancel),
                    ),
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

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
          for (final speaker in options)
            _SpeakerChip(
              selected: speaker == selected,
              label: names.labelFor(
                speaker,
                defaultLabel: l10n.speakerLabel(speaker + 1),
              ),
              color: SpeakerPalette.colorFor(
                speaker,
                fallback: theme.colorScheme.surfaceContainerHighest,
                custom: names.colorOf(speaker),
              ),
              onTap: () =>
                  ref.read(selectedSpeakerProvider.notifier).select(speaker),
              // Every chip, the spare speaker too: it can be named and
              // coloured before any words are given to it.
              onLongPress: () => editSpeaker(
                context,
                ref,
                transcriptId: transcriptId,
                speaker: speaker,
              ),
            ),
          // Edits the speaker that is selected -- whichever chip that is.
          IconButton(
            tooltip: l10n.editSpeakerTitle,
            icon: const Icon(Icons.edit_outlined, size: 22),
            onPressed: () => editSpeaker(
              context,
              ref,
              transcriptId: transcriptId,
              speaker: selected,
            ),
          ),
      ],
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

/// Whether captions carry their speaker's name, in the preview and export.
class _SpeakerNamesToggle extends ConsumerWidget {
  const _SpeakerNamesToggle({required this.transcriptId});

  final String transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final projectId =
        ref.watch(transcriptByIdProvider(transcriptId)).value?.projectId;
    final settings = projectId == null
        ? null
        : ref.watch(projectVideoSettingsProvider(projectId)).value;
    final on = settings?.showSpeakerNames ?? false;
    void flip() => ref
        .read(projectVideoSettingsProvider(projectId!).notifier)
        .change(settings!.copyWith(showSpeakerNames: !on));

    return MergeSemantics(
      child: InkWell(
        onTap: settings == null ? null : flip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.showSpeakerNamesOnVideo,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      l10n.showSpeakerNamesOnVideoDetail,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppToggle(
                value: on,
                onChanged: settings == null ? null : (_) => flip(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One speaker in the Speakers-scope palette.
class _SpeakerChip extends StatelessWidget {
  const _SpeakerChip({
    required this.selected,
    required this.label,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  final bool selected;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final radius = BorderRadius.circular(surface.radius);

    // A flat box: the speaker's colour fills it when it is the one chosen.
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          // Dark draws no outlines, so there the box is a tone instead.
          color: selected
              ? color
              : surface.outlined
                  ? Colors.transparent
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: radius,
          border: surface.outlined
              ? Border.all(color: surface.outline, width: surface.borderWidth)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!selected) ...[
                    SizedBox.square(
                      dimension: 12,
                      child: ColoredBox(color: color),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
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
      ),
    );
  }
}

/// Undo and redo for the transcript's edit history.
class HistoryControls extends ConsumerWidget {
  const HistoryControls({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Both false until the first frame resolves, which is correct: an empty
    // history and an unread one offer the same actions.
    final history = ref.watch(projectHistoryStateProvider(projectId)).value ??
        (canUndo: false, canRedo: false);

    final repository = ref.read(transcriptRepositoryProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const AppIcon(AppGlyph.undo),
          tooltip: l10n.undoAction,
          onPressed:
              history.canUndo ? () => repository.undoProject(projectId) : null,
        ),
        IconButton(
          icon: const AppIcon(AppGlyph.redo),
          tooltip: l10n.redoAction,
          onPressed:
              history.canRedo ? () => repository.redoProject(projectId) : null,
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
  String? _selectedRangeId;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final l10n = AppLocalizations.of(context);
    // Script mode shows the clip the timeline has selected. A project with no
    // clips has nothing to show and nothing to play.
    final clipId = ref.watch(resolvedSelectedClipProvider(project.id));
    if (clipId == null) {
      // The gear on its own. The panel is also where the mode switches, so
      // without it an empty project would be stuck in Script mode.
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerRight,
              child: VideoSettingsGear(projectId: project.id),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _CenteredMessage(message: l10n.timelineNoClips),
                Positioned.fill(
                  child: VideoSettingsPanel(
                    projectId: project.id,
                    mode: EditorMode.script,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // The whole project, in timeline order.
    final script = ref.watch(projectScriptProvider(project.id));

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
        _PlayerPane(
          projectId: project.id,
          clipId: clipId,
          transcriptId: selected?.id,
        ),
        // Everything under the player sits beneath the video settings panel,
        // which dims and blurs it while open and is absent while closed.
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
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
                    child: AppSegmentRow<String>(
                      selected: selected!.id,
                      items: {
                        for (final range in ranges)
                          range.id: _rangeLabel(range),
                      },
                      onSelected: (id) => setState(() => _selectedRangeId = id),
                    ),
                  ),
                // The player casts no shadow of its own — the transcript draws
                // it, from inside its own stack. Two reasons.
                Expanded(
                  child: transcripts.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _CenteredMessage(message: '$error'),
                    // A clip nobody has asked to transcribe yet. Says so plainly and
                    // points at where the action lives, rather than implying the
                    // engine found no speech -- which is a different outcome entirely.
                    data: (_) => script.words.isEmpty
                        ? _CenteredMessage(message: l10n.clipNotTranscribedScript)
                        : _TranscriptView(
                            clipId: clipId,
                            // Still the clip's own range: it is what the edit scope,
                            // the speaker palette and undo/redo act on. Only the words
                            // on screen are project-wide.
                            transcript: selected ?? ranges.firstOrNull,
                            script: script,
                          ),
                  ),
                ),
                ],
              ),
              Positioned.fill(
                child: VideoSettingsPanel(
                  projectId: project.id,
                  mode: EditorMode.script,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A transcript's clip-relative range, for the range selector.
String _rangeLabel(Transcript transcript) {
  final start = transcript.clipStartMs;
  final end = transcript.clipEndMs;
  if (start == null || end == null) return _formatPosition(Duration.zero);
  return '${_formatPosition(Duration(milliseconds: start))}'
      '–${_formatPosition(Duration(milliseconds: end))}';
}

class _PlayerPane extends ConsumerWidget {
  const _PlayerPane({
    required this.projectId,
    required this.clipId,
    required this.transcriptId,
  });

  final String projectId;
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
        projectId: projectId,
        clipId: clipId,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _Player extends ConsumerWidget {
  const _Player({
    required this.projectId,
    required this.clipId,
    required this.transcriptId,
    required this.controller,
  });

  /// Whose video settings frame the stage.
  final String projectId;

  final String clipId;
  final String? transcriptId;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

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
            // it.
            SizedBox(
              // The same stage as the timeline's, so switching modes does not
              // shrink the picture.
              height: hasVideo ? stageHeight : 120,
              width: double.infinity,
              // The output's frame, as the timeline draws it.
              child: hasVideo
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: ProjectStageCanvas(
                          projectId: projectId,
                          clipId: clipId,
                          sourceSize: value.size,
                          picture: VideoPlayer(controller),
                          mediaPositionMs: value.position.inMilliseconds,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        Center(
                          child:
                              _CenteredMessage(message: l10n.audioOnlyLabel),
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
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      ref.read(mediaPlayerProvider(clipId).notifier).togglePlayback(),
                  icon: AppIcon(
                    value.isPlaying ? AppGlyph.pause : AppGlyph.play,
                  ),
                  tooltip: value.isPlaying ? l10n.pauseAction : l10n.playAction,
                ),
                Expanded(
                  // What has played in the action colour, as the timeline's
                  // playhead is; the rest in the page's own ink, thinly.
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: Theme.of(context).colorScheme.primary,
                      bufferedColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.22),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_formatPosition(value.position)),
                // The same fullscreen preview as the timeline's: the whole
                // edited frame, not the bare video.
                if (hasVideo)
                  IconButton(
                    tooltip: l10n.timelineFullscreen,
                    icon: const AppIcon(AppGlyph.fullscreen),
                    onPressed: () => showProjectFullscreen(
                      context,
                      projectId: projectId,
                      clipId: clipId,
                      controller: controller,
                    ),
                  ),
                VideoSettingsGear(projectId: projectId),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The caption for the current playback position, drawn over the video.
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

    final color = SpeakerPalette.colorFor(
      cue.speaker,
      fallback: Colors.white,
      custom: ref.watch(speakerNamesProvider(transcriptId)).colorOf(cue.speaker),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A scrim rather than a solid bar: enough to keep text legible over
          // a bright frame without hiding the video behind it.
          color: Colors.black.withValues(alpha: 0.62),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            cue.text,
            textAlign: TextAlign.center,
            // Bounded so a large accessibility text scale cannot grow the
            // caption past the video and shove the controls off screen.
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
  const _TranscriptView({
    required this.clipId,
    required this.transcript,
    required this.script,
  });

  final String clipId;

  /// The range the *controls* act on -- edit scope, speaker names, undo.
  final Transcript? transcript;

  /// Every word in the project, and which clip each transcript sits on.
  final ProjectScript script;

  @override
  ConsumerState<_TranscriptView> createState() => _TranscriptViewState();
}

/// Holds the transcript's scroll, because the edit bar above it has to follow.
class _TranscriptViewState extends ConsumerState<_TranscriptView>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _barKey = GlobalKey();

  /// Reaches whichever `_InlineField` is currently open, from outside the
  /// widget that owns it, so it can be flushed *before* something replaces or
  /// clears `InlineEdit`'s span.
  final _inlineFieldKey = GlobalKey<_InlineFieldState>();

  /// Drives the bar in and out when edit mode is entered or left.
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
    final words = widget.script.words;

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
    // Stays mounted through the exit animation, and through the entrance before
    // the first frame of it has been measured. Also needs a range to act on.
    final barPresent = widget.transcript != null &&
        (shown > 0 || ref.watch(transcriptEditModeProvider));

    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBar());

    final items = words;
    if (items.isEmpty) {
      return _CenteredMessage(message: l10n.transcriptEmpty);
    }

    {

        // Every speaker this transcript actually contains, in the order they
        // first appear.
        final speakers = <int>{
          for (final word in items)
            if (int.tryParse(word.speakerId ?? '') case final int speaker)
              speaker,
        }.toList();

        // The word count scrolls with the text rather than being pinned above
        // it.
        return Stack(
                children: [
                  Positioned.fill(
                    child: _WordFlow(
                      clipId: widget.clipId,
                      words: items,
                      clipOfTranscript: widget.script.clipOfTranscript,
                      controller: _scroll,
                      heading: l10n.wordCount(items.length),
                      // Starts the text below the bar rather than behind it.
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
                          transcriptId: widget.transcript!.id,
                          speakers: speakers,
                          inlineFieldKey: _inlineFieldKey,
                        ),
                      ),
                    ),
          ],
        );
    }
  }
}

/// The transcript itself: a reflowing run of words, each one a seek target.
class _WordFlow extends ConsumerWidget {
  const _WordFlow({
    required this.clipId,
    required this.words,
    required this.clipOfTranscript,
    required this.controller,
    required this.topInset,
    required this.heading,
    required this.inlineFieldKey,
  });

  final String clipId;
  final List<Word> words;

  /// Which clip each transcript sits on.
  final Map<String, String> clipOfTranscript;

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
        clipOfTranscript: clipOfTranscript,
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
        clipOfTranscript: clipOfTranscript,
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
    required this.clipOfTranscript,
    required this.positionMs,
    required this.controller,
    required this.topInset,
    required this.heading,
    required this.inlineFieldKey,
  });

  final String clipId;
  final List<Word> words;

  /// Which clip each transcript sits on.
  final Map<String, String> clipOfTranscript;

  final int? positionMs;
  final ScrollController controller;
  final double topInset;
  final String heading;
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  /// Plays the clip this word actually belongs to.
  void _seekToWord(WidgetRef ref, Word word) {
    final owner = clipOfTranscript[word.transcriptId] ?? clipId;
    ref.read(mediaPlayerProvider(owner).notifier).seekToWord(word.startMs);
  }

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

    // Each transcript's translation lines; which caption row each goes under
    // is worked out with the rows (see `_cueRows`).
    final translations = <String, List<TranslationLine>>{
      for (final transcriptId in {for (final w in words) w.transcriptId})
        transcriptId: ref
                .watch(transcriptTranslationProvider(transcriptId))
                .value ??
            const <TranslationLine>[],
    };
    final hasTranslation = translations.values.any((l) => l.isNotEmpty);
    final showTranslation =
        hasTranslation && ref.watch(showTranslationProvider);

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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    heading,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                // Only once there is something to show.
                if (hasTranslation)
                  MergeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => ref
                          .read(showTranslationProvider.notifier)
                          .set(!showTranslation),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context).showTranslation,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          AppToggle(
                            value: showTranslation,
                            onChanged: (value) => ref
                                .read(showTranslationProvider.notifier)
                                .set(value),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ..._cueRows(
            context,
            ref,
            translations: showTranslation ? translations : const {},
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
bool _covers(({int from, int to})? open, CaptionCue cue) =>
    open != null &&
    open.from <= cue.words.first.position &&
    open.to >= cue.words.last.position;

List<Widget> _cueRows(
      BuildContext context,
      WidgetRef ref, {
      required Map<String, List<TranslationLine>> translations,
      required List<SpeakerTurn> turns,
      required List<int> speakers,
      required int activeIndex,
      required bool editing,
      required int? anchor,
    }) {
      final scope = ref.watch(transcriptEditScopeSettingProvider);
      final open = ref.watch(inlineEditProvider);
      final rows = <Widget>[];

    // Each translation line under the caption row it overlaps most, in its own
    // transcript -- by time, not word position, so retyping the transcript
    // (which renumbers its words) never moves a translation to the wrong row.
    final cuesOf = {for (final turn in turns) turn: groupIntoCues(turn.words)};
    final rowsOf = <String, List<CaptionCue>>{};
    for (final MapEntry(key: turn, value: cues) in cuesOf.entries) {
      (rowsOf[turn.words.first.transcriptId] ??= []).addAll(cues);
    }
    final linesUnder = <CaptionCue, List<TranslationLine>>{};
    for (final MapEntry(key: transcriptId, value: lines)
        in translations.entries) {
      final cues = rowsOf[transcriptId] ?? const <CaptionCue>[];
      if (cues.isEmpty) continue;
      for (final line in lines) {
        CaptionCue? bestCue;
        var bestScore = double.negativeInfinity;
        for (final cue in cues) {
          final overlap = math.min(line.endMs, cue.endMs) -
              math.max(line.startMs, cue.startMs);
          // Nothing overlapping: the nearest, by the gap between them.
          final score = overlap > 0
              ? overlap.toDouble()
              : -((line.startMs + line.endMs) / 2 -
                      (cue.startMs + cue.endMs) / 2)
                  .abs();
          if (score > bestScore) {
            bestScore = score;
            bestCue = cue;
          }
        }
        (linesUnder[bestCue!] ??= []).add(line);
      }
    }
    final showing = translations.isNotEmpty;

    for (final turn in turns) {
      final cues = cuesOf[turn]!;

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
            // can be flushed pre-emptively (see `_correct`) after the provider
            // has already moved on to a different span.
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
            speakerColor: ref
                .watch(speakerNamesProvider(turn.words.first.transcriptId))
                .colorOf(turn.speaker),
            // In Line scope the unit is the row, so the row is the target —
            // including the empty space after a short line.
            onRowTap: editing &&
                    scope == TranscriptEditScope.line &&
                    !_covers(open, cue)
                ? () => _correct(context, ref, turn, base, cue: cue)
                : null,
            onWordTap: (o) => editing
                ? _correct(context, ref, turn, o, cue: cue)
                : _seekToWord(ref, turn.words[o]),
            // The timestamp is the speaker signal, so in edit mode it is also
            // the speaker control -- the thing you tap is the thing you are
            // changing, which is the same rule the removed chip followed.
            onStampTap: editing && speakers.length > 1
                ? () => _reassignTurn(context, ref, turn, speakers)
                : () => _seekToWord(ref, cue.words.first),
          ),
        );
        offset += cue.words.length;

        // Its translation, under it -- or, while editing, a place to add
        // one. Edited on its own: the transcript's words are never touched.
        final lines = linesUnder[cue] ?? const <TranslationLine>[];
        if (showing && (lines.isNotEmpty || editing)) {
          rows.add(_TranslationLine(
            key: ValueKey(('translation', cue.words.first.id)),
            text: lines.isEmpty
                ? null
                : [for (final line in lines) line.content].join(' '),
            editable: editing,
            onCommit: (text) =>
                ref.read(transcriptRepositoryProvider).setCueTranslation(
                      transcriptId: cue.words.first.transcriptId,
                      lineIds: [for (final line in lines) line.id],
                      firstWord: cue.words.first.position,
                      lastWord: cue.words.last.position,
                      startMs: cue.startMs,
                      endMs: cue.endMs,
                      content: text,
                    ),
          ));
        }
      }
    }

    return rows;
  }

  /// Opens the word at [offset] within [turn], or the sentence containing it.
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

    // Line means the row, not the sentence. It used to mean the sentence
    // containing the tapped word, which was right when the transcript was one
    // undivided run of prose.
    final slice = switch (scope) {
      TranscriptEditScope.word => [turn.words[offset]],
      TranscriptEditScope.line => cue.words,
      TranscriptEditScope.speakers => const <Word>[],
    };
    if (slice.isEmpty) return;

    // Tapping straight from one word/line to another replaces the open span
    // without the first field ever losing focus, so nothing else would commit
    // it.
    inlineFieldKey.currentState?.flush();

    ref.read(inlineEditProvider.notifier).open(
          from: slice.first.position,
          to: slice.last.position,
        );
  }

  /// Writes a retyped span back, and closes the editor.
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
    // applies to all of it.
    await ref.read(transcriptRepositoryProvider).reassignSpeaker(
          transcriptId: turn.words.first.transcriptId,
          fromPosition: turn.words.first.position,
          toPosition: turn.words.last.position,
          speaker: chosen,
        );
  }
}

/// The hairline between two cues.
class _TranslationLine extends StatefulWidget {
  const _TranslationLine({
    super.key,
    required this.text,
    required this.editable,
    required this.onCommit,
  });

  /// Null while the caption row has no translation.
  final String? text;

  /// Script's edit mode: a tap retypes it, or adds one where there is none.
  final bool editable;
  final ValueChanged<String> onCommit;

  @override
  State<_TranslationLine> createState() => _TranslationLineState();
}

/// A caption row's translation, under it: a short rule, then the line.
class _TranslationLineState extends State<_TranslationLine> {
  TextEditingController? _field;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _field != null) _commit();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _field?.dispose();
    super.dispose();
  }

  void _open() {
    final text = widget.text ?? '';
    setState(() {
      _field = TextEditingController(text: text)
        ..selection = TextSelection.collapsed(offset: text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    final field = _field;
    if (field == null) return;
    final typed = field.text.trim();
    setState(() => _field = null);
    field.dispose();
    if (typed != (widget.text ?? '').trim()) widget.onCommit(typed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indent =
        MediaQuery.textScalerOf(context).scale(_CueLineState._stampWidth);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 17,
      height: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final text = widget.text;
    final field = _field;

    final Widget line;
    if (field != null) {
      line = TextField(
        controller: field,
        focusNode: _focus,
        style: style,
        maxLines: null,
        textInputAction: TextInputAction.done,
        textDirection: translationDirectionOf(field.text),
        decoration: const InputDecoration(
          isCollapsed: true,
          // Explicitly none: a collapsed field still takes the theme's
          // padding, which moved the words when the field opened.
          contentPadding: EdgeInsets.zero,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onSubmitted: (_) => _focus.unfocus(),
        onTapOutside: (_) => _focus.unfocus(),
      );
    } else if (text == null) {
      line = Text(
        AppLocalizations.of(context).translationAdd,
        style: style?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
      );
    } else {
      line = Text(
        text,
        textDirection: translationDirectionOf(text),
        style: style,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: indent, top: AppSpacing.xs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.editable && field == null ? _open : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Across the text column, from the words' edge: the length of
            // what it separates, and short of the row rule (`_CueRule`),
            // which also runs under the timestamps.
            ColoredBox(
              color: appHairline(theme),
              child: const SizedBox(height: appHairlineWidth),
            ),
            // Room for the edit box, open or not, so opening it moves
            // nothing.
            const SizedBox(height: AppSpacing.sm),
            if (field == null)
              line
            else
              // Script's edit box -- the action colour, 2pt, square -- drawn
              // *around* the text rather than padding it, so the words stay
              // exactly where they were when the field opens.
              CustomPaint(
                foregroundPainter: _EditBoxPainter(
                  color: theme.colorScheme.primary,
                ),
                child: line,
              ),
          ],
        ),
      ),
    );
  }
}

/// The inline edit box's outline, painted outside the child's bounds: as far
/// out as `_InlineField`'s padding and border reach, without taking any room.
class _EditBoxPainter extends CustomPainter {
  _EditBoxPainter({required this.color});

  final Color color;

  static const _stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    const dx = AppSpacing.xs + _stroke / 2;
    const dy = AppSpacing.xxs + _stroke / 2;
    final rect =
        Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _EditBoxPainter old) => old.color != color;
}

class _CueRule extends StatelessWidget {
  const _CueRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: ColoredBox(
        color: appHairline(Theme.of(context)),
        child: const SizedBox(height: appHairlineWidth, width: double.infinity),
      ),
    );
  }
}

/// One caption line: its start time, then its words.
class _CueLine extends StatefulWidget {
  const _CueLine({
    required this.cue,
    required this.baseOffset,
    required this.turnStartIndex,
    required this.activeIndex,
    required this.editing,
    required this.anchor,
    required this.speaker,
    this.speakerColor,
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

  /// The speaker's own colour (ARGB), when one was chosen.
  final int? speakerColor;

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

  /// Shared across every `_InlineField` this transcript can build.
  final GlobalKey<_InlineFieldState> inlineFieldKey;

  @override
  State<_CueLine> createState() => _CueLineState();
}

class _CueLineState extends State<_CueLine> {
  /// Room for `mm:ss`, scaled with the text so a large accessibility setting
  /// cannot clip it.
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

    // Baseline-aligned, so the smaller timestamp sits on the same line as
    // the first line of words -- a fixed nudge put it visibly above them.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        GestureDetector(
          // Opaque, so the whole gutter is the target rather than the five
          // glyphs of the timestamp.
          behavior: HitTestBehavior.opaque,
          onTap: widget.onStampTap,
          child: SizedBox(
            width: scaler.scale(_stampWidth),
            child: Padding(
              padding: EdgeInsets.zero,
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

  /// The words' style: larger than body text and with room between lines,
  /// because every word here is something to tap, and a finger needs more
  /// than a reading size to land on one.
  TextStyle _lineStyle(ThemeData theme) =>
      theme.textTheme.bodyLarge!.copyWith(fontSize: 19, height: 1.7);

  /// Either the cue's words, or a field standing in for the part being retyped.
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
        style: _lineStyle(theme),
        onCommit: widget.onCommit,
      );
    }

    return Text.rich(TextSpan(children: _spans(theme)));
  }

  /// The speaker's colour, in the version that can be read as text.
  Color _stampColour(ThemeData theme) {
    return SpeakerPalette.textColorFor(
      widget.speaker,
      custom: widget.speakerColor,
      brightness: theme.brightness,
      fallback: theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );
  }

  List<InlineSpan> _spans(ThemeData theme) {
    final base = _lineStyle(theme);
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
      // prose.
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
              // Selection, so it takes the selection colour.
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
            // the gaps between them stay untinted, so a line comes out striped.
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
class _InlineField extends StatefulWidget {
  const _InlineField({
    super.key,
    required this.sessionKey,
    required this.initial,
    required this.style,
    required this.onCommit,
  });

  /// Identifies *which* span this field is editing -- `(from, to)` works, since
  /// records compare by value.
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

    // Bring the row into view straight away, keyboard or not.
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

    // The shared `GlobalKey` handed this widget the *previous* field's State.
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
    // Deliberately does not flush here.
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Losing focus commits rather than discards.
  void _onFocusChange() {
    if (!_focus.hasFocus && mounted) flush();
  }

  /// Commits whatever is typed, once.
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
    // view a moment ago can now be underneath the keys.
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
        // A box, not a fill.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

/// The speakers a tap can assign, and the one it will.
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
                  custom: names.colorOf(speaker),
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
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    int speaker,
    SpeakerNames names,
  ) =>
      editSpeaker(context, ref, transcriptId: transcriptId, speaker: speaker);
}

/// Edits one speaker: its name and its colour, saved together.
Future<void> editSpeaker(
  BuildContext context,
  WidgetRef ref, {
  required String transcriptId,
  required int speaker,
}) async {
  final names = ref.read(speakerNamesProvider(transcriptId));
  final result = await showDialog<({String name, int? color})>(
    context: context,
    builder: (context) => _SpeakerEditor(
      speaker: speaker,
      initialName: names[speaker] ?? '',
      initialColor: names.colorOf(speaker),
    ),
  );
  if (result == null) return;
  final repository = ref.read(transcriptRepositoryProvider);
  await repository.renameSpeaker(
    transcriptId: transcriptId,
    speaker: speaker,
    name: result.name,
  );
  await repository.recolorSpeaker(
    transcriptId: transcriptId,
    speaker: speaker,
    argb: result.color,
  );
}

class _SpeakerEditor extends StatefulWidget {
  const _SpeakerEditor({
    required this.speaker,
    required this.initialName,
    required this.initialColor,
  });

  final int speaker;
  final String initialName;
  final int? initialColor;

  @override
  State<_SpeakerEditor> createState() => _SpeakerEditorState();
}

class _SpeakerEditorState extends State<_SpeakerEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  late int? _color = widget.initialColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop((name: _controller.text, color: _color));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AppDialog(
      title: l10n.editSpeakerTitle,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.renameSpeakerHint(widget.speaker + 1),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.speakerColor, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            // The Style panel's picker; Default is the speaker's palette colour.
            AppColorPicker(
              current: _color,
              defaultLabel: l10n.styleColorDefault,
              onChanged: (argb) => setState(() => _color = argb),
            ),
          ],
        ),
      ),
      actions: [
        AppDialogAction(
          label: l10n.editSave,
          emphasis: AppDialogEmphasis.primary,
          onPressed: _save,
        ),
        AppDialogAction(
          label: l10n.editCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Index of the word being spoken at [positionMs], or -1 before the first one.
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
