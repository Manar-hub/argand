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
import '../../core/timeline/project_timeline.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'clip_transcription_controller.dart';
import 'import_controller.dart' show ImportStage;
import 'media_player_controller.dart';
import 'project_screen.dart' show HistoryControls;
import 'transcript_repository.dart';

/// How wide one second is drawn.
///
/// **The one scale everything on this screen measures with.** The ruler's
/// ticks, each clip's width and the playhead's position all derive from it, so
/// a tick sits over the moment it names rather than near it.
const double _pixelsPerSecond = 24;

/// Height of one track row.
const double _trackHeight = 64;

/// Width of the fixed playhead line.
const double _playheadWidth = 2;

/// Timeline mode: the clip/track view of the editing screen.
///
/// **The track is a true time axis.** A clip's width is exactly its duration
/// times [_pixelsPerSecond] — no minimum width, no gaps between tiles. An
/// earlier pass clamped short clips and spaced them apart, which meant the
/// ruler and the tiles disagreed by a little more with every clip, and nothing
/// drawn at a given millisecond could be trusted to land over the media playing
/// at that millisecond. Clips are separated by a hairline drawn *inside* their
/// own width instead. A very short clip therefore draws very narrow, which is
/// honest: it is short.
///
/// **The playhead is fixed at the centre and the content moves under it.**
/// Leading and trailing padding of half the viewport is what lets both the
/// first and last frame reach it, and scrolling is the scrub gesture — so there
/// is no second scrubber in the player, which would be a different scale
/// claiming to mean the same thing.
///
/// **A project is a list of clips here, not a single file.** The preview and
/// Script mode both follow whichever clip is selected; each carries its own
/// transcript, its own speakers and its own undo history, because word timings
/// are relative to a clip's own media.
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
            // Play sits in the middle with the utilities pushed to the edges,
            // so the one control used constantly is the one under the thumb.
            // A `Stack` rather than spacers because centring by flex would
            // drift as the right-hand group changes width with undo/redo.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.fullscreen),
                        tooltip: l10n.timelineFullscreen,
                        onPressed: _openFullscreen,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.aspect_ratio),
                        tooltip: l10n.timelineAspectToggle,
                        onPressed: hasVideo ? _toggleFit : null,
                      ),
                      if (transcriptId != null)
                        HistoryControls(transcriptId: transcriptId),
                    ],
                  ),
                  IconButton(
                    onPressed: () => ref
                        .read(mediaPlayerProvider(widget.clipId).notifier)
                        .togglePlayback(),
                    icon:
                        Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    iconSize: 32,
                    tooltip:
                        value.isPlaying ? l10n.pauseAction : l10n.playAction,
                  ),
                ],
              ),
            ),
            // Position only. **No progress bar**: the timeline below is the
            // scrubber now, and a second one at a different scale would be two
            // controls claiming to mean the same thing.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_formatPosition(value.position)} / '
                  '${_formatPosition(value.duration)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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

  /// True while the *user* is dragging the track.
  ///
  /// The playhead is driven from two directions — dragging scrubs the player,
  /// and playback scrolls the track — so without a flag each would hear its own
  /// echo and fight the other. Whoever moved last wins, and this says which
  /// that was.
  bool _scrubbing = false;

  /// The position playback last reported, so an unchanged frame does not
  /// re-issue a scroll.
  int _followedMs = -1;

  /// The controller currently being followed.
  ///
  /// Held so the listener can be moved when the selection changes. Following
  /// playback has to be a *listener* rather than a `ref.watch`: watching the
  /// provider yields the controller, and a controller is not rebuilt when its
  /// position advances — only its own `ValueListenable` reports that. Rebuilding
  /// the track on every tick would also mean re-laying out every filmstrip
  /// image sixty times a second, so this deliberately scrolls without setState.
  VideoPlayerController? _followed;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _followed?.removeListener(_onPlaybackTick);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Points the playback listener at [controller], detaching from the previous.
  void _follow(VideoPlayerController? controller) {
    if (identical(controller, _followed)) return;
    _followed?.removeListener(_onPlaybackTick);
    _followed = controller;
    _followed?.addListener(_onPlaybackTick);
  }

  void _onPlaybackTick() {
    final controller = _followed;
    final clipId = widget.selectedId;
    if (controller == null || clipId == null || !mounted) return;

    final timeline = ref.read(projectTimelineProvider(widget.projectId));
    final projectMs = timeline.projectMsOf(
      clipId: clipId,
      clipMs: controller.value.position.inMilliseconds,
    );
    if (projectMs != null) _followPlayback(projectMs);
  }

  /// Turns a scroll offset into a seek.
  ///
  /// The offset *is* the playhead: content is padded by half the viewport, so
  /// the pixel under the centre line is `offset` pixels into the project. Which
  /// clip that lands in, and how far into it, is [ProjectTimeline]'s to answer —
  /// this only has to notice when the answer changes clip, because that is a
  /// selection change as well as a seek.
  void _onScroll() {
    if (!_scroll.hasClients) return;

    final timeline = ref.read(projectTimelineProvider(widget.projectId));
    if (timeline.isEmpty) return;

    final projectMs = (_scroll.offset / _pixelsPerSecond * 1000).round();
    final at = timeline.clipAt(projectMs);
    if (at == null) return;

    // Only a real drag scrubs. A scroll this widget issued itself while
    // following playback must not be fed back as a seek.
    if (!_scrubbing) return;

    if (at.clipId != widget.selectedId) {
      ref.read(selectedClipProvider(widget.projectId).notifier).select(at.clipId);
    }
    ref.read(mediaPlayerProvider(at.clipId).notifier).seekTo(at.clipMs);
  }

  /// Scrolls the track so [projectMs] sits under the playhead.
  void _followPlayback(int projectMs) {
    if (_scrubbing || !_scroll.hasClients) return;
    if (projectMs == _followedMs) return;
    _followedMs = projectMs;

    final target = (projectMs / 1000 * _pixelsPerSecond)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((target - _scroll.offset).abs() < 0.5) return;
    _scroll.jumpTo(target);
  }

  /// A clip's width *is* its duration. See the class doc on [TimelineBody] for
  /// why there is no minimum and no gap.
  double _widthOf(MediaClip clip) =>
      (clip.durationMs ?? 0) / 1000 * _pixelsPerSecond;

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
    final theme = Theme.of(context);
    final adding =
        ref.watch(addClipControllerProvider(widget.projectId)) is AddClipCopying;
    final timeline = ref.watch(projectTimelineProvider(widget.projectId));

    // Follow playback: the player reports a position inside the selected clip,
    // which the timeline turns into a position on the shared axis. Watched
    // here only to learn *which* controller to listen to -- the position
    // itself arrives through the listener, not through a rebuild.
    final selected = widget.selectedId;
    _follow(selected == null
        ? null
        : ref.watch(mediaPlayerProvider(selected)).value);

    final trackWidth = timeline.totalMs / 1000 * _pixelsPerSecond;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Half the viewport at each end, which is what lets the very first and
        // very last frame reach a playhead pinned to the centre.
        final lead = constraints.maxWidth / 2;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
              NotificationListener<ScrollNotification>(
                // Only a drag counts as scrubbing. `jumpTo` while following
                // playback emits no start/end notification, so the flag stays
                // false and the seek loop never closes.
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _scrubbing = true;
                  } else if (notification is ScrollEndNotification) {
                    _scrubbing = false;
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: lead),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TimeRuler(totalMs: timeline.totalMs, width: trackWidth),
                      const SizedBox(height: AppSpacing.xs),
                      SizedBox(
                        height: _trackHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, clip) in widget.clips.indexed)
                              _ClipTile(
                                clip: clip,
                                width: _widthOf(clip),
                                selected: clip.id == widget.selectedId,
                                onTap: () => ref
                                    .read(selectedClipProvider(widget.projectId)
                                        .notifier)
                                    .select(clip.id),
                                onLongPress: () => _showActions(clip, index),
                              ),
                            _AddClipTile(busy: adding, onTap: widget.onAddClip),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                  // Drawn over the tracks rather than scrolling with them: it
                  // marks a place on the screen, not a place in the media.
                  IgnorePointer(
                    child: Container(
                      width: _playheadWidth,
                      height: _rulerHeight + AppSpacing.xs + _trackHeight,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Outside the scroll: this adds a track, it is not one, so it
              // stays put while the timeline moves beneath the playhead.
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
      },
    );
  }
}

enum _ClipAction { earlier, later, remove }

/// Height the ruler occupies: ticks plus the labels beneath them.
const double _rulerHeight = 28;

/// A measuring rule: a long tick for each labelled value, short ticks between.
///
/// **The label is centred on its tick**, which an earlier pass got wrong by
/// positioning text from its left edge — the glyphs then sat beside the moment
/// they named rather than on it, and at a glance the whole ruler read as
/// shifted.
///
/// The labelled interval widens until labels cannot collide, so changing
/// [_pixelsPerSecond] (or adding zoom later) needs no change here. Minor ticks
/// subdivide that interval into five.
class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.totalMs, required this.width});

  final int totalMs;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _rulerHeight,
      width: width <= 0 ? 1 : width,
      child: CustomPaint(
        painter: _RulerPainter(
          totalMs: totalMs,
          ink: theme.colorScheme.onSurface,
          textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.totalMs,
    required this.ink,
    required this.textStyle,
  });

  final int totalMs;
  final Color ink;
  final TextStyle textStyle;

  /// Narrowest gap between two labels before they read as one smear.
  static const double _minLabelGap = 64;

  /// Minor ticks per labelled interval.
  static const int _subdivisions = 5;

  static const double _majorTick = 10;
  static const double _minorTick = 5;

  /// Seconds between labelled ticks at the current scale.
  static int stepFor(double pixelsPerSecond) {
    var step = 1;
    while (step * pixelsPerSecond < _minLabelGap) {
      step = step < 5 ? 5 : step + 5;
    }
    return step;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final step = stepFor(_pixelsPerSecond);
    final minorStep = step / _subdivisions;
    final totalSeconds = totalMs / 1000;

    final major = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = ink.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Minor ticks first so a major tick is never half-covered by one landing
    // on the same pixel at the interval boundary.
    for (var second = 0.0; second <= totalSeconds; second += minorStep) {
      final x = second * _pixelsPerSecond;
      if (x > size.width) break;
      final isMajor = (second / step - (second / step).round()).abs() < 0.001;
      if (isMajor) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, _minorTick), minor);
    }

    for (var second = 0; second <= totalSeconds; second += step) {
      final x = second * _pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, _majorTick), major);

      final label = TextPainter(
        text: TextSpan(
          text: _formatPosition(Duration(seconds: second)),
          style: textStyle.copyWith(color: ink.withValues(alpha: 0.7)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Centred on the tick, and nudged inward at the very start so the first
      // label is not half cut off by the padding edge.
      var left = x - label.width / 2;
      if (left < 0) left = 0;
      label.paint(canvas, Offset(left, _majorTick + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      totalMs != oldDelegate.totalMs ||
      ink != oldDelegate.ink ||
      textStyle != oldDelegate.textStyle;
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
          // The border is drawn *inside* the tile's width rather than as a gap
          // beside it. A gap would add pixels the timeline does not have time
          // for, and every clip boundary after the first would sit later than
          // the moment it represents.
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
