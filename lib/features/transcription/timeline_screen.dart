import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
import '../../core/media/thumbnail_service.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'clip_transcription_controller.dart';
import 'import_controller.dart' show ImportStage;
import 'media_player_controller.dart';
import 'project_screen.dart' show HistoryControls;
import 'transcript_repository.dart';

/// How wide one second of a clip is drawn.
///
/// The single scale the ruler and the track both measure with — that is what
/// makes a tick line up with the clip boundary beneath it, instead of the two
/// rows being unrelated decorations. Chosen so one filmstrip frame, sampled
/// roughly every two seconds, lands at a comfortable ~48pt.
const double _pixelsPerSecond = 24;

/// Enough width that a one-second clip is still a tappable target.
const double _minClipWidth = 56;

const double _trackHeight = 64;

/// Timeline mode: the clip/track view of the editing screen.
///
/// **A project is a list of clips here, not a single file.** The preview and
/// Script mode both follow whichever clip is selected; each carries its own
/// transcript, its own speakers and its own undo history, because word timings
/// are relative to a clip's own media and there is no compositor to define a
/// project-wide timebase (`docs/progress.md`, Phase 9).
///
/// **Adding a clip never transcribes it.** "+" copies a file in and nothing
/// more; transcription is minutes of CPU and runs only when the user asks for
/// it on a selected clip. That separation is the whole point of this screen.
class TimelineBody extends ConsumerStatefulWidget {
  const TimelineBody({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends ConsumerState<TimelineBody> {
  /// A visualisation toggle over caption data the app already computes, not a
  /// new editing capability -- see the Captions case in [_BottomToolbar].
  bool _showCaptions = false;

  void _placeholder(String feature) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.timelineComingSoon(feature))));
  }

  Future<void> _addClip() async {
    final added = await ref
        .read(addClipControllerProvider(widget.project.id).notifier)
        .pickAndAdd();
    if (added == null || !mounted) return;

    // Selecting what was just added is the only sensible landing: the user
    // added it to work on it, and an unselected new clip would leave the
    // preview showing something else.
    ref
        .read(selectedClipProvider(widget.project.id).notifier)
        .select(added);
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.project.id;
    final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
    final selectedId = ref.watch(resolvedSelectedClipProvider(projectId));
    final transcript = selectedId == null
        ? null
        : ref.watch(clipTranscriptProvider(selectedId)).value;

    return Column(
      children: [
        if (selectedId == null)
          const _NoClipPreview()
        else
          _TimelinePreview(clipId: selectedId, transcriptId: transcript?.id),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TimelineTrack(
                  projectId: projectId,
                  clips: clips,
                  selectedId: selectedId,
                  onAddClip: _addClip,
                  onAddAudio: () => _placeholder(
                      AppLocalizations.of(context).timelineAddAudio),
                ),
                if (selectedId != null)
                  _SelectedClipStrip(
                    projectId: projectId,
                    clipId: selectedId,
                    hasTranscript: transcript != null,
                  ),
                if (_showCaptions && transcript != null)
                  _CaptionStrip(transcriptId: transcript.id),
              ],
            ),
          ),
        ),
        _BottomToolbar(
          showCaptions: _showCaptions,
          onToggleCaptions: () =>
              setState(() => _showCaptions = !_showCaptions),
          onPlaceholder: _placeholder,
        ),
      ],
    );
  }

}

/// The stage when a project has no clips at all -- what "Create project"
/// leaves behind until the first "+".
class _NoClipPreview extends StatelessWidget {
  const _NoClipPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SizedBox(
      height: 220,
      width: double.infinity,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.timelineNoClips,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}

/// The video stage plus its controls, for the selected clip.
class _TimelinePreview extends ConsumerWidget {
  const _TimelinePreview({required this.clipId, required this.transcriptId});

  final String clipId;
  final String? transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final player = ref.watch(mediaPlayerProvider(clipId));

    return player.when(
      loading: () => const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => SizedBox(
        height: 300,
        child: Center(child: Text(l10n.playerUnavailable)),
      ),
      data: (controller) => _TimelinePlayer(
        clipId: clipId,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _TimelinePlayer extends ConsumerStatefulWidget {
  const _TimelinePlayer({
    required this.clipId,
    required this.transcriptId,
    required this.controller,
  });

  final String clipId;
  final String? transcriptId;
  final VideoPlayerController controller;

  @override
  ConsumerState<_TimelinePlayer> createState() => _TimelinePlayerState();
}

class _TimelinePlayerState extends ConsumerState<_TimelinePlayer> {
  BoxFit _fit = BoxFit.contain;

  void _toggleFit() => setState(
      () => _fit = _fit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenPlayer(controller: widget.controller),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transcriptId = widget.transcriptId;

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasVideo = value.size.width > 0 && value.size.height > 0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              // An audio clip has no picture to letterbox, so it gets a short
              // stage instead of 300pt of empty ground -- the same call Script
              // mode's player makes.
              height: hasVideo ? 300 : 120,
              width: double.infinity,
              child: ColoredBox(
                color: hasVideo ? Colors.black : Colors.transparent,
                child: Center(
                  child: hasVideo
                      ? SizedBox.expand(
                          child: FittedBox(
                            fit: _fit,
                            child: SizedBox(
                              width: value.size.width,
                              height: value.size.height,
                              child: VideoPlayer(widget.controller),
                            ),
                          ),
                        )
                      // Theme ink, not white: the stage behind this is
                      // transparent when there is no video, so white text sits
                      // on the page's own light ground and disappears.
                      : Text(
                          l10n.audioOnlyLabel,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    tooltip: l10n.timelineFullscreen,
                    onPressed: _openFullscreen,
                  ),
                  IconButton(
                    onPressed: () => ref
                        .read(mediaPlayerProvider(widget.clipId).notifier)
                        .togglePlayback(),
                    icon:
                        Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    tooltip:
                        value.isPlaying ? l10n.pauseAction : l10n.playAction,
                  ),
                  IconButton(
                    icon: const Icon(Icons.aspect_ratio),
                    tooltip: l10n.timelineAspectToggle,
                    onPressed: hasVideo ? _toggleFit : null,
                  ),
                  const Spacer(),
                  if (transcriptId != null)
                    HistoryControls(transcriptId: transcriptId),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xxs,
              ),
              child: Row(
                children: [
                  Text(
                    '${_formatPosition(value.position)} / '
                    '${_formatPosition(value.duration)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: VideoProgressIndicator(widget.controller,
                        allowScrubbing: true),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Pushed by the preview's fullscreen button. Reuses the same controller --
/// there is exactly one player per clip, owned by [mediaPlayerProvider], so
/// opening this route does not start a second decoder.
class _FullscreenPlayer extends StatelessWidget {
  const _FullscreenPlayer({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ruler and the clip row, sharing one horizontal scroll and one scale.
///
/// **Sharing the controller is what makes this a timeline.** Two independently
/// scrolling rows measured in different units would be a ruler drawn near some
/// clips; one scroll offset and one [_pixelsPerSecond] means the tick above a
/// clip boundary is genuinely the time that boundary falls at.
class _TimelineTrack extends ConsumerStatefulWidget {
  const _TimelineTrack({
    required this.projectId,
    required this.clips,
    required this.selectedId,
    required this.onAddClip,
    required this.onAddAudio,
  });

  final String projectId;
  final List<MediaClip> clips;
  final String? selectedId;
  final VoidCallback onAddClip;
  final VoidCallback onAddAudio;

  @override
  ConsumerState<_TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<_TimelineTrack> {
  final _scroll = ScrollController();
  final _rulerScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Driven rather than shared: two viewports cannot attach to one
    // ScrollController, so the ruler mirrors the track's offset instead.
    _scroll.addListener(() {
      if (!_rulerScroll.hasClients) return;
      if (_rulerScroll.offset == _scroll.offset) return;
      _rulerScroll.jumpTo(_scroll.offset.clamp(
        0,
        _rulerScroll.position.maxScrollExtent,
      ));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _rulerScroll.dispose();
    super.dispose();
  }

  double _widthOf(MediaClip clip) {
    final seconds = (clip.durationMs ?? 0) / 1000;
    final width = seconds * _pixelsPerSecond;
    return width < _minClipWidth ? _minClipWidth : width;
  }

  Future<void> _showActions(MediaClip clip, int index) async {
    final l10n = AppLocalizations.of(context);
    final editor = ref.read(clipEditorProvider);
    final clips = widget.clips;

    // A sheet rather than a drag. Reordering by dragging a variable-width tile
    // inside a horizontally scrolling strip fights the scroll gesture, and
    // long-press is already spoken for by removal -- so both operations are
    // offered explicitly, where they can also be labelled.
    final action = await showModalBottomSheet<_ClipAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: Text(l10n.clipMoveEarlier),
              enabled: index > 0,
              onTap: () => Navigator.of(context).pop(_ClipAction.earlier),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: Text(l10n.clipMoveLater),
              enabled: index < clips.length - 1,
              onTap: () => Navigator.of(context).pop(_ClipAction.later),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.clipRemove),
              onTap: () => Navigator.of(context).pop(_ClipAction.remove),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _ClipAction.earlier:
        await editor.move(
          projectId: widget.projectId,
          clips: clips,
          from: index,
          to: index - 1,
        );
      case _ClipAction.later:
        await editor.move(
          projectId: widget.projectId,
          clips: clips,
          from: index,
          to: index + 1,
        );
      case _ClipAction.remove:
        await _confirmRemove(clip);
    }
  }

  Future<void> _confirmRemove(MediaClip clip) async {
    final l10n = AppLocalizations.of(context);

    // Confirmed because it is not recoverable: the media is hard-deleted, the
    // same bargain `deleteProject` makes and says out loud.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clipRemoveTitle),
        content: Text(l10n.clipRemoveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.editCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.clipRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(clipEditorProvider).remove(clip.id);
    if (!mounted) return;
    // The removed clip may have been the selection; clearing lets the timeline
    // fall back to the first remaining one rather than pointing at a tombstone.
    if (ref.read(selectedClipProvider(widget.projectId)) == clip.id) {
      ref.read(selectedClipProvider(widget.projectId).notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final adding =
        ref.watch(addClipControllerProvider(widget.projectId)) is AddClipCopying;

    final totalMs = widget.clips
        .fold<int>(0, (sum, clip) => sum + (clip.durationMs ?? 0));
    final trackWidth = widget.clips
        .fold<double>(0, (sum, clip) => sum + _widthOf(clip) + AppSpacing.xxs);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20,
            child: SingleChildScrollView(
              controller: _rulerScroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _TimeRuler(totalMs: totalMs, width: trackWidth),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: _trackHeight,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, clip) in widget.clips.indexed) ...[
                    _ClipTile(
                      clip: clip,
                      width: _widthOf(clip),
                      selected: clip.id == widget.selectedId,
                      onTap: () => ref
                          .read(selectedClipProvider(widget.projectId).notifier)
                          .select(clip.id),
                      onLongPress: () => _showActions(clip, index),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  _AddClipTile(busy: adding, onTap: widget.onAddClip),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _AddAudioRow(
              label: l10n.timelineAddAudio,
              onTap: widget.onAddAudio,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ClipAction { earlier, later, remove }

/// MM:SS ticks across the project's whole running time.
///
/// Spaced by [_pixelsPerSecond] like everything else on the track, with the
/// interval widened until labels stop colliding — so zooming later changes one
/// constant rather than this widget.
class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.totalMs, required this.width});

  final int totalMs;
  final double width;

  /// Narrowest gap between two labels before they read as one smear.
  static const double _minLabelGap = 64;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (totalMs <= 0 || width <= 0) {
      return SizedBox(
        width: width <= 0 ? 1 : width,
        child: Text('00:00', style: theme.textTheme.labelSmall),
      );
    }

    var step = 1;
    while (step * _pixelsPerSecond < _minLabelGap) {
      step = step < 5 ? 5 : step + 5;
    }

    final totalSeconds = totalMs / 1000;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          for (var second = 0; second <= totalSeconds; second += step)
            Positioned(
              left: second * _pixelsPerSecond,
              top: 0,
              child: Text(
                _formatPosition(Duration(seconds: second)),
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// One clip on the track, filled with frames sampled from its own media.
class _ClipTile extends ConsumerWidget {
  const _ClipTile({
    required this.clip,
    required this.width,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaClip clip;
  final double width;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final radius = BorderRadius.circular(6);

    final duration = Duration(milliseconds: clip.durationMs ?? 0);
    final count = ThumbnailService.frameCountFor(duration);
    final frames = ref
            .watch(clipFramesProvider(
              mediaPath: clip.mediaPath,
              cacheDir: ref
                  .watch(mediaConverterProvider)
                  .thumbnailDirFor(clipId: clip.id, mediaPath: clip.mediaPath),
              count: count,
            ))
            .value ??
        const <String>[];

    return Semantics(
      selected: selected,
      label: clip.title,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              // The selected clip takes the theme's own call to action, the
              // same signal `_Segment` uses for a chosen option.
              color: selected ? theme.colorScheme.primary : surface.outline,
              width: selected ? surface.borderWidth : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: frames.isEmpty
              // No frames: an audio-only clip, or extraction that did not
              // land. The tile still shows and still works.
              ? Icon(
                  Icons.graphic_eq,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                )
              : Row(
                  children: [
                    for (final frame in frames)
                      Expanded(
                        child: Image.file(
                          File(frame),
                          fit: BoxFit.cover,
                          height: _trackHeight,
                          // A frame that vanished under us is a gap, never a
                          // red error box across the timeline.
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AddClipTile extends StatelessWidget {
  const _AddClipTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;

    return Semantics(
      button: true,
      label: l10n.clipAdd,
      child: InkWell(
        borderRadius: surface.borderRadius,
        onTap: busy ? null : onTap,
        child: Container(
          width: 56,
          decoration: surface.decoration(
            fill: busy
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            raised: false,
          ),
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(Icons.add, color: theme.colorScheme.onPrimary),
        ),
      ),
    );
  }
}

class _AddAudioRow extends StatelessWidget {
  const _AddAudioRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;

    return InkWell(
      borderRadius: surface.borderRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          borderRadius: surface.borderRadius,
          border:
              Border.all(color: surface.outline, width: surface.borderWidth),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: theme.colorScheme.onSurface),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// The selected clip's transcription state, and the action that starts it.
///
/// **This is where the split becomes visible.** A clip sits untranscribed until
/// someone decides it is worth the minutes; this strip is that decision, and
/// afterwards it reports the engine's own stages rather than a bare spinner, so
/// a long run reads as progress instead of a hang.
class _SelectedClipStrip extends ConsumerWidget {
  const _SelectedClipStrip({
    required this.projectId,
    required this.clipId,
    required this.hasTranscript,
  });

  final String projectId;
  final String clipId;
  final bool hasTranscript;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(clipTranscriptionControllerProvider(clipId));

    final child = switch (status) {
      ClipTranscriptionRunning(:final stage, :final percent) => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                percent == null
                    ? _stageLabel(l10n, stage)
                    : '${_stageLabel(l10n, stage)} $percent%',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ClipTranscriptionFailed() => Row(
          children: [
            Expanded(
              child: Text(
                l10n.clipTranscribeFailed,
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => ref
                  .read(clipTranscriptionControllerProvider(clipId).notifier)
                  .transcribe(),
              child: Text(l10n.retryAction),
            ),
          ],
        ),
      _ when hasTranscript => Row(
          children: [
            Icon(Icons.check, size: 18, color: theme.colorScheme.onSurface),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.clipTranscribed,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      _ => Row(
          children: [
            Expanded(
              child: Text(
                l10n.clipNotTranscribed,
                style: theme.textTheme.bodySmall,
              ),
            ),
            FilledButton(
              onPressed: () => ref
                  .read(clipTranscriptionControllerProvider(clipId).notifier)
                  .transcribe(),
              child: Text(l10n.clipTranscribe),
            ),
          ],
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: child,
    );
  }
}

String _stageLabel(AppLocalizations l10n, ImportStage stage) =>
    switch (stage) {
      ImportStage.preparingModel => l10n.stagePreparingModel,
      ImportStage.copyingMedia => l10n.stageCopyingMedia,
      ImportStage.extractingAudio => l10n.stageExtractingAudio,
      ImportStage.transcribing => l10n.stageTranscribing,
      ImportStage.identifyingSpeakers => l10n.stageIdentifyingSpeakers,
      ImportStage.saving => l10n.stageSaving,
    };

/// The caption list shown when the Captions toolbar button is toggled on.
/// Reads `clipTranscriptProvider`'s cues, exactly what `_CaptionOverlay` in
/// Script mode reads -- a visualisation over data the app already computes,
/// not new editing capability.
class _CaptionStrip extends ConsumerWidget {
  const _CaptionStrip({required this.transcriptId});

  final String transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cues = ref.watch(captionCuesProvider(transcriptId)).value;

    if (cues == null || cues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(l10n.transcriptEmpty, style: theme.textTheme.bodySmall),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.timelineCaptionsLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          for (final cue in cues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Text(
                '${_formatPosition(Duration(milliseconds: cue.startMs))}  '
                '${cue.text}',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// The seven icon-over-label buttons at the foot of the screen.
class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.showCaptions,
    required this.onToggleCaptions,
    required this.onPlaceholder,
  });

  final bool showCaptions;
  final VoidCallback onToggleCaptions;
  final void Function(String feature) onPlaceholder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.content_cut,
                  label: l10n.timelineToolEdit,
                  onTap: () => onPlaceholder(l10n.timelineToolEdit),
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.audiotrack_outlined,
                  label: l10n.timelineToolAudio,
                  onTap: () => onPlaceholder(l10n.timelineToolAudio),
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.text_fields,
                  label: l10n.timelineToolText,
                  onTap: () => onPlaceholder(l10n.timelineToolText),
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.auto_fix_high_outlined,
                  label: l10n.timelineToolEffects,
                  onTap: () => onPlaceholder(l10n.timelineToolEffects),
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.layers_outlined,
                  label: l10n.timelineToolOverlay,
                  onTap: () => onPlaceholder(l10n.timelineToolOverlay),
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.subtitles_outlined,
                  label: l10n.timelineToolCaptions,
                  active: showCaptions,
                  onTap: onToggleCaptions,
                ),
              ),
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.tune,
                  label: l10n.timelineToolFilter,
                  onTap: () => onPlaceholder(l10n.timelineToolFilter),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Whether this button represents a toggled-on state (only Captions uses
  /// this today) rather than a one-shot action.
  final bool active;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = widget.active
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final ink = widget.active
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: PressableSurface(
        selected: _pressed || widget.active,
        fill: fill,
        border: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // `PressableSurface` already supplies the feedback.
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: ink, size: 22),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    widget.label,
                    style: theme.textTheme.labelSmall?.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

String _formatPosition(Duration position) {
  final minutes = position.inMinutes.toString().padLeft(2, '0');
  final seconds = (position.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
