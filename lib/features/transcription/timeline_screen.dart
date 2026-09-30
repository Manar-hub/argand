import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio/waveform.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
import '../../core/media/thumbnail_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_surface.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/layer_drag.dart';
import '../../core/timeline/pinch_tracker.dart';
import '../../core/timeline/timeline_items.dart';
import '../../core/timeline/timeline_selection.dart';
import '../../core/timeline/timeline_zoom.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'editor_mode_controller.dart';
import 'layer_transcription_controller.dart';
import 'import_controller.dart' show ImportStage;
import 'media_player_controller.dart';
import 'project_fullscreen.dart';
import 'project_screen.dart' show CaptionOverlay, HistoryControls;
import 'stage_editor.dart';
import 'timeline_blocks.dart';
import 'style_panel.dart';
import 'timeline_history.dart';
import '../../core/timeline/audio_window.dart';
import '../../core/timeline/translation_texts.dart';
import 'transcript_repository.dart';
import 'translate_sheet.dart';
import 'transcription_options.dart';
import 'video_settings_panel.dart';

part 'timeline_lanes.dart';

/// Height of every track row.
const double _trackHeight = 68;

/// Height of the preview stage, in every state it can be in.
const double _stageHeight = stageHeight;

/// Width of the fixed playhead line.
const double _playheadWidth = 2;

/// Corner radius shared by everything that sits *on* a track -- clip tiles, the
/// "+" tile, layer rectangles.
final BorderRadius _tileRadius = BorderRadius.zero;

/// Timeline mode: the clip/track view of the editing screen.
class TimelineBody extends ConsumerStatefulWidget {
  const TimelineBody({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends ConsumerState<TimelineBody> {
  /// Whether the zoom slider is showing above the toolbar.
  bool _zoomOpen = false;

  /// Whether the style panel is showing above the toolbar.
  bool _styleOpen = false;

  /// What the Zoom and Rotate tools act on: whatever is selected -- captions, a
  /// translation, texts, pictures, clips -- or, with nothing selected, the clip
  /// on the stage.
  List<TimelineItem> _toolItems(String? clipOnStage, {bool select = true}) {
    final projectId = widget.project.id;
    final chosen = [
      for (final item in ref.read(timelineSelectionProvider(projectId)))
        if (item.kind != TimelineItemKind.audio) item,
    ];
    if (chosen.isNotEmpty || clipOnStage == null) return chosen;

    final clip = (kind: TimelineItemKind.clip, id: clipOnStage);
    if (select) {
      ref.read(timelineSelectionProvider(projectId).notifier).selectOnly(clip);
    }
    return [clip];
  }

  /// A quarter turn clockwise on each item the tool acts on, as one step.
  /// Captions and translations stay level -- a turned subtitle is a puzzle,
  /// not a style -- so only clips, texts and pictures turn.
  Future<void> _rotate(String? clipOnStage) async {
    final projectId = widget.project.id;
    final turnable = [
      for (final item in _toolItems(clipOnStage))
        if (item.kind == TimelineItemKind.clip ||
            item.kind == TimelineItemKind.text ||
            item.kind == TimelineItemKind.image)
          item,
    ];
    final changes = <PlacementChange>[
      for (final MapEntry(key: item, value: at)
          in selectedPlacements(ref, projectId, turnable).entries)
        (
          kind: item.kind,
          id: item.id,
          before: at.own,
          after: at.from.quarterTurned(),
        ),
    ];
    await ref
        .read(transcriptRepositoryProvider)
        .applyPlacements(projectId: projectId, changes: changes);
  }

  /// Puts a text on the picture at the playhead and opens it for typing.
  Future<void> _addText() async {
    final projectId = widget.project.id;
    final words = AppLocalizations.of(context).textPlaceholder;

    final timeline = ref.read(projectTimelineProvider(projectId));
    final playheadMs = ref.read(timelinePlayheadProvider(projectId));
    // Three seconds from the playhead, pulled back from the end so a text
    // added there is still long enough to read.
    final total = timeline.totalMs;
    var start = playheadMs;
    if (total > 0 && start + _defaultTextMs > total) {
      start = math.max(0, total - _defaultTextMs);
    }

    final id = await ref.read(transcriptRepositoryProvider).addTextLayer(
          projectId: projectId,
          startMs: start,
          endMs: start + _defaultTextMs,
          content: words,
        );
    if (id == null || !mounted) return;

    // Shown if it landed on a hidden track, or typing would go nowhere.
    final text = (await ref
            .read(transcriptRepositoryProvider)
            .textLayersForProject(projectId))
        .where((t) => t.id == id)
        .firstOrNull;
    if (!mounted) return;
    if (text?.trackId case final trackId?) {
      ref.read(hiddenTracksProvider(projectId).notifier).show(trackId);
    }
    final item = (kind: TimelineItemKind.text, id: id);
    ref.read(timelineSelectionProvider(projectId).notifier).selectOnly(item);
    ref
        .read(stageEditingProvider(projectId).notifier)
        .start(item, fresh: true);
  }

  void _placeholder(String feature) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.timelineComingSoon(feature))));
  }

  /// Picks a picture and puts it at the playhead, selected.
  Future<void> _addImage() async {
    final projectId = widget.project.id;
    final id = await pickAndAddImage(
      ref.read(transcriptRepositoryProvider),
      projectId: projectId,
      atMs: ref.read(timelinePlayheadProvider(projectId)),
      totalMs: ref.read(projectTimelineProvider(projectId)).totalMs,
    );
    if (id == null || !mounted) return;
    ref
        .read(timelineSelectionProvider(projectId).notifier)
        .selectOnly((kind: TimelineItemKind.image, id: id));
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

  /// Cuts everything selected, at the playhead.
  Future<void> _splitSelection(int projectMs) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(transcriptRepositoryProvider);
    final selection = ref.read(timelineSelectionProvider(widget.project.id));

    if (selection.isEmpty) {
      _say(l10n.splitNothingSelected);
      return;
    }

    final timeline = ref.read(projectTimelineProvider(widget.project.id));
    var cut = 0;
    var refused = 0;

    for (final item in selection) {
      switch (item.kind) {
        case TimelineItemKind.clip:
          final at = timeline.placementOf(item.id);
          // The playhead has to be inside the clip to cut it. One outside is
          // not an error, it simply has nothing to say about this clip.
          if (at == null) continue;
          if (projectMs <= at.startMs ||
              projectMs >= at.startMs + at.durationMs) {
            continue;
          }

          final made = await repository.splitClip(
            clipId: item.id,
            atClipMs: projectMs - at.startMs,
          );
          made == null ? refused++ : cut++;

        case TimelineItemKind.layer:
          final made = await repository.splitLayer(
            layerId: item.id,
            atProjectMs: projectMs,
          );
          made == null ? refused++ : cut++;

        case TimelineItemKind.text:
        case TimelineItemKind.sentence:
        case TimelineItemKind.audio:
        case TimelineItemKind.translation:
        case TimelineItemKind.image:
          // A text is short and placed by hand, a sentence is cut by
          // retyping it, and a clip's sound is cut with its picture; none is
          // something Split is asked to do on its own.
          continue;
      }
    }

    if (!mounted) return;

    // Refused rather than clamped when a piece would be too short to be worth
    // anything, so the message says what happened instead of a cut appearing
    // to land somewhere the playhead was not.
    _say(
      cut > 0
          ? l10n.splitDone
          : refused > 0
              ? l10n.splitTooClose
              : l10n.splitNotUnderPlayhead,
    );
  }

  /// The Transcribe tool: runs the selected transcribe layer, or draws one over
  /// the selected clip -- or the clip on screen -- and runs that.
  Future<void> _transcribeHere(String? clipOnStage) async {
    final projectId = widget.project.id;
    final selection = ref.read(timelineSelectionProvider(projectId));

    // A layer already under the playhead is the one to run: drawing a second
    // over it would only fail against the overlap rule.
    final playheadMs = ref.read(timelinePlayheadProvider(projectId));
    final underPlayhead = (ref.read(projectLayersProvider(projectId)).value ??
            const <TranscribeLayer>[])
        .where((l) => l.startMs <= playheadMs && playheadMs < l.endMs)
        .firstOrNull
        ?.id;

    final layerId = idsOfKind(selection, TimelineItemKind.layer).firstOrNull ??
        underPlayhead ??
        await _addLayer(
          context,
          ref,
          projectId: projectId,
          clipId: idsOfKind(selection, TimelineItemKind.clip).firstOrNull ??
              clipOnStage,
        );
    if (layerId == null || !mounted) return;

    ref
        .read(timelineSelectionProvider(projectId).notifier)
        .selectOnly((kind: TimelineItemKind.layer, id: layerId));
    await _transcribeLayer(context, ref, layerId);
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.project.id;
    final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
    final timeline = ref.watch(projectTimelineProvider(projectId));
    final playheadMs = ref.watch(timelinePlayheadProvider(projectId));
    final selection = ref.watch(timelineSelectionProvider(projectId));

    // A removed clip or layer must not stay selected: the tools would act on
    // nothing and report success. Pruned from a listener rather than during
    // build, because a notifier must not be written to while it is being read.
    ref.listen(projectClipsProvider(projectId), (_, next) {
      final ids = <String>{
        for (final clip in next.value ?? const <MediaClip>[]) clip.id,
      };
      ref.read(timelineSelectionProvider(projectId).notifier).prune(
            clipIds: ids,
            layerIds: idsOfKind(
              ref.read(timelineSelectionProvider(projectId)),
              TimelineItemKind.layer,
            ),
          );
    });

    // The preview follows the playhead, not the selection. Selection now means
    // "what the tools act on" and can hold several things at once, so it cannot
    // also mean "what is on screen".
    final selectedId = timeline.clipAt(playheadMs)?.clipId ??
        (clips.isEmpty ? null : clips.first.id);
    // The first range on the clip, for the caption strip and the "is this
    // transcribed" state. Script mode is where a clip's several ranges are
    // chosen between; the timeline only needs to know whether any exist.
    final transcript = selectedId == null
        ? null
        : (ref.watch(clipTranscriptsProvider(selectedId)).value ?? const [])
            .firstOrNull;

    return Column(
      children: [
        if (selectedId == null)
          _NoClipPreview(projectId: projectId)
        else
          _TimelinePreview(
            projectId: projectId,
            clipId: selectedId,
            mediaPath: clips
                .firstWhere((clip) => clip.id == selectedId)
                .mediaPath,
            transcriptId: transcript?.id,
          ),
        // Everything below the stage sits under the video settings panel,
        // which dims and blurs it while open and is absent while closed.
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      // Locked with the seek while something is selected, so
                      // a drag moves it up and down rather than the tracks.
                      physics: selection.isNotEmpty
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: AppSpacing.xs),
                            child: _TimelineTrack(
                              projectId: projectId,
                              clips: clips,
                              selectedId: selectedId,
                              onAddClip: _addClip,
                              onAddTrack: () {},
                              onAddText: _addText,
                              onAddImage: _addImage,
                              onTrackUnavailable: _placeholder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Pinned, not scrolled with the tracks.
                  _SelectionStrip(projectId: projectId),
                  AnimatedSize(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    // One docked panel at a time: Zoom and Style each put
                    // the other away.
                    child: _zoomOpen
                        ? _ZoomBar(
                            projectId: projectId,
                            items: _toolItems(selectedId, select: false),
                          )
                        : _styleOpen
                            ? StylePanel(
                                projectId: projectId,
                                // Linked down to the toolbar's Style button.
                                anchor: (
                                  count: _BottomToolbar.toolCount,
                                  index: _BottomToolbar.styleIndex,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                  ),
                  _BottomToolbar(
                    onSplit: () => _splitSelection(playheadMs),
                    zoomOpen: _zoomOpen,
                    styleOpen: _styleOpen,
                    onZoom: () {
                      if (!_zoomOpen) _toolItems(selectedId);
                      setState(() {
                        _zoomOpen = !_zoomOpen;
                        _styleOpen = false;
                      });
                    },
                    onStyle: () => setState(() {
                      _styleOpen = !_styleOpen;
                      _zoomOpen = false;
                    }),
                    onRotate: () => _rotate(selectedId),
                    onText: _addText,
                    onTranscribe: () => _transcribeHere(selectedId),
                  ),
                ],
              ),
              Positioned.fill(
                child: VideoSettingsPanel(
                  projectId: projectId,
                  mode: EditorMode.timeline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

/// The stage when a project has no clips at all -- what "Create project"
/// leaves behind until the first "+".
class _NoClipPreview extends StatelessWidget {
  const _NoClipPreview({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          // The same stage every other state reserves, so adding the first
          // clip does not shift the timeline under the user's finger.
          height: _stageHeight,
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
        ),
        // The player's controls, where they will be once there is a clip:
        // inactive, apart from the gear (the mode switch lives in its panel)
        // and history, which can bring back a clip just removed.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  HiddenWhileSettingsOpen(
                    projectId: projectId,
                    child: IconButton(
                      icon: const AppIcon(AppGlyph.fullscreen),
                      tooltip: l10n.timelineFullscreen,
                      onPressed: null,
                    ),
                  ),
                  const Spacer(),
                  VideoSettingsGear(projectId: projectId),
                  HiddenWhileSettingsOpen(
                    projectId: projectId,
                    child: HistoryControls(projectId: projectId),
                  ),
                ],
              ),
              IconButton(
                onPressed: null,
                icon: const AppIcon(AppGlyph.play),
                iconSize: 32,
                tooltip: l10n.playAction,
              ),
            ],
          ),
        ),
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
              '${_formatPosition(Duration.zero)} / '
              '${_formatPosition(Duration.zero)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// The video stage plus its controls, for whatever the playhead is over.
class _TimelinePreview extends ConsumerWidget {
  const _TimelinePreview({
    required this.projectId,
    required this.clipId,
    required this.mediaPath,
    required this.transcriptId,
  });

  final String projectId;
  final String clipId;

  /// What the stage is keyed by, rather than [clipId].
  final String mediaPath;

  final String? transcriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Kept alive so the duration repair still runs and the actions elsewhere
    // resolve to this same controller; its loading state is not what the
    // stage waits on.
    ref.watch(mediaPlayerProvider(clipId));
    final player = ref.watch(mediaControllerProvider(mediaPath));

    return player.when(
      loading: () => const SizedBox(
        height: _stageHeight,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => SizedBox(
        height: _stageHeight,
        child: Center(child: Text(l10n.playerUnavailable)),
      ),
      data: (controller) => _TimelinePlayer(
        projectId: projectId,
        clipId: clipId,
        transcriptId: transcriptId,
        controller: controller,
      ),
    );
  }
}

class _TimelinePlayer extends ConsumerStatefulWidget {
  const _TimelinePlayer({
    required this.projectId,
    required this.clipId,
    required this.transcriptId,
    required this.controller,
  });

  /// Undo is project-wide, so the transport needs to know which project it is
  /// looking at rather than only which clip.
  final String projectId;

  final String clipId;
  final String? transcriptId;
  final VideoPlayerController controller;

  @override
  ConsumerState<_TimelinePlayer> createState() => _TimelinePlayerState();
}

class _TimelinePlayerState extends ConsumerState<_TimelinePlayer> {
  void _openFullscreen() => showProjectFullscreen(
        context,
        projectId: widget.projectId,
        clipId: widget.clipId,
        controller: widget.controller,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final transcriptId = widget.transcriptId;

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasVideo = value.size.width > 0 && value.size.height > 0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              // One height, whatever is on it.
              height: _stageHeight,
              width: double.infinity,
              child: hasVideo
                  // The output's frame, not the clip's.
                  ? ColoredBox(
                      // Ground around the frame in a different tone from the
                      // frame's own black, so its edges -- the edges of the
                      // exported video -- are visible.
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        // Captions and texts are drawn inside the frame where
                        // they will be burned in -- but as live widgets here,
                        // never rasterized (docs/engine-architecture.md).
                        child: ProjectStageCanvas(
                          projectId: widget.projectId,
                          clipId: widget.clipId,
                          sourceSize: value.size,
                          picture: VideoPlayer(widget.controller),
                          mediaPositionMs: value.position.inMilliseconds,
                          editable: true,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        // Theme ink, not white: with no video there is no
                        // frame behind this, so white text would sit on the
                        // page's own ground and vanish in the light theme.
                        Center(
                          child: Text(
                            l10n.audioOnlyLabel,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (transcriptId != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: CaptionOverlay(
                          transcriptId: transcriptId,
                          positionMs: value.position.inMilliseconds,
                        ),
                          ),
                      ],
                    ),
            ),
            // Play sits in the middle with the utilities pushed to the edges,
            // so the one control used constantly is the one under the thumb.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      // Fullscreen and history step aside while the video
                      // settings are open: the panel below is about the frame.
                      HiddenWhileSettingsOpen(
                        projectId: widget.projectId,
                        child: IconButton(
                          icon: const AppIcon(AppGlyph.fullscreen),
                          tooltip: l10n.timelineFullscreen,
                          onPressed: _openFullscreen,
                        ),
                      ),
                      const Spacer(),
                      VideoSettingsGear(projectId: widget.projectId),
                      // Not gated on the selected clip having a transcript.
                      HiddenWhileSettingsOpen(
                        projectId: widget.projectId,
                        child: HistoryControls(projectId: widget.projectId),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => ref
                        .read(mediaPlayerProvider(widget.clipId).notifier)
                        .togglePlayback(),
                    icon: AppIcon(
                      value.isPlaying ? AppGlyph.pause : AppGlyph.play,
                    ),
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
class _TimelineTrack extends ConsumerStatefulWidget {
  const _TimelineTrack({
    required this.projectId,
    required this.clips,
    required this.selectedId,
    required this.onAddClip,
    required this.onAddTrack,
    required this.onAddText,
    required this.onAddImage,
    required this.onTrackUnavailable,
  });

  final String projectId;
  final List<MediaClip> clips;
  final String? selectedId;
  final VoidCallback onAddClip;
  final VoidCallback onAddTrack;

  /// Adds a text layer at the playhead, as the Text tool does.
  final VoidCallback onAddText;
  final ValueChanged<String> onTrackUnavailable;

  /// Picks a picture and puts it on the timeline.
  final VoidCallback onAddImage;

  @override
  ConsumerState<_TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<_TimelineTrack> {
  final _scroll = ScrollController();

  /// How wide one second is drawn, now that it is the user's to change.
  double _pps = defaultPixelsPerSecond;

  /// The scale when the current pinch began, and the project time that was
  /// under the playhead at that moment.
  double _pinchStartPps = defaultPixelsPerSecond;
  int _pinchAnchorMs = 0;

  /// The fingers on the track, and what scale they are asking for.
  final _pinch = PinchTracker();

  /// True while the *user* is dragging the track.
  bool _scrubbing = false;

  /// The position playback last reported, so an unchanged frame does not
  /// re-issue a scroll.
  int _followedMs = -1;

  /// The controller currently being followed.
  VideoPlayerController? _followed;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _followed?.removeListener(_onPlaybackTick);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Project time currently under the playhead.
  int get _playheadMs => _scroll.hasClients
      ? msAtOffset(offset: _scroll.offset, pixelsPerSecond: _pps)
      : 0;

  void _onPointerDown(PointerDownEvent event) {
    if (_pinch.down(event.pointer, event.position)) _restartPinch();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final scale = _pinch.move(event.pointer, event.position);
    if (scale != null) _applyZoom(scale);
  }

  void _onPointerFinished(PointerEvent event) {
    if (_pinch.up(event.pointer)) _restartPinch();
  }

  /// Scrubs by [dx] pixels from the ruler, locked or not: `jumpTo` ignores
  /// the scroll physics a selection sets.
  void _scrubBy(double dx) {
    if (!_scroll.hasClients) return;
    final next = (_scroll.offset + dx)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (next == _scroll.offset) return;
    // Raised around each step, not once for the drag: every `jumpTo` ends
    // with a scroll-end notification, which lowers the flag again, and the
    // steps after the first would then move the ruler without seeking.
    _scrubbing = true;
    _scroll.jumpTo(next);
    _scrubbing = false;
  }

  /// Seeks to the moment [x] points into the ruler, as a scrub would.
  void _seekToX(double x) {
    if (!_scroll.hasClients) return;
    _scrubbing = true;
    _scroll.jumpTo(x.clamp(0.0, _scroll.position.maxScrollExtent));
    _scrubbing = false;
  }

  /// Captures what the pinch now measures from.
  void _restartPinch() {
    _pinchStartPps = _pps;
    _pinchAnchorMs = _playheadMs;
    setState(() {});
  }

  void _applyZoom(double scale) {
    final next = scalePixelsPerSecond(_pinchStartPps, scale);
    if (next == _pps) return;

    setState(() => _pps = next);

    // Re-anchor after the layout that the new scale forces, or the offset would
    // be applied against the old content width and the playhead would slide off
    // the moment it was holding.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = offsetForAnchor(
        anchorMs: _pinchAnchorMs,
        pixelsPerSecond: _pps,
        maxScrollExtent: _scroll.position.maxScrollExtent,
      );
      if ((target - _scroll.offset).abs() < 0.5) return;
      // Not a scrub: the media has not moved, only the ruler it is drawn
      // against, so this must not be allowed to seek the player.
      _scrubbing = false;
      _scroll.jumpTo(target);
    });
  }

  /// The file the followed decoder is playing, so its position can be placed.
  String? _followedPath;

  /// Points the playback listener at [controller], detaching from the previous.
  void _follow(VideoPlayerController? controller, String? mediaPath) {
    _followedPath = mediaPath;
    if (identical(controller, _followed)) return;
    _followed?.removeListener(_onPlaybackTick);
    _followed = controller;
    _followed?.addListener(_onPlaybackTick);
  }

  void _onPlaybackTick() {
    final controller = _followed;
    final path = _followedPath;
    if (controller == null || path == null || !mounted) return;

    final positionMs = controller.value.position.inMilliseconds;

    // The clip that is playing, not the one the playhead is over. Both halves
    // of a split share one decoder, and its position is in media time.
    for (final clip in widget.clips) {
      if (clip.mediaPath != path) continue;

      final window = clipWindow(clip);
      if (positionMs < window.startMs || positionMs >= window.endMs) continue;

      final projectMs = ref
          .read(projectTimelineProvider(widget.projectId))
          .projectMsOf(clipId: clip.id, clipMs: positionMs);
      if (projectMs != null) _followPlayback(projectMs);
      return;
    }

    // Past the last clip's out-point, where the file plays on under words
    // still on the timeline: the playhead goes on with it.
    final timeline = ref.read(projectTimelineProvider(widget.projectId));
    final last = timeline.placements.lastOrNull;
    final lastClip = last == null
        ? null
        : widget.clips.where((c) => c.id == last.clipId).firstOrNull;
    if (lastClip == null ||
        lastClip.mediaPath != path ||
        positionMs < clipWindow(lastClip).endMs) {
      return;
    }
    final projectMs =
        timeline.projectMsOf(clipId: lastClip.id, clipMs: positionMs);
    if (projectMs != null &&
        projectMs <= ref.read(projectRunMsProvider(widget.projectId))) {
      _followPlayback(projectMs);
    }
  }

  /// Turns a scroll offset into a seek.
  void _onScroll() {
    if (!_scroll.hasClients) return;

    final timeline = ref.read(projectTimelineProvider(widget.projectId));
    if (timeline.isEmpty) return;

    final projectMs = _playheadMs;

    // Published whether this was a drag or playback following itself: the
    // preview and the toolbar both ask where the playhead is, and it is just
    // as true when the timeline moved on its own.
    ref
        .read(timelinePlayheadProvider(widget.projectId).notifier)
        .moveTo(projectMs);

    // Past the clips, the last one's file plays on under the words still
    // there -- see `ProjectTimeline.runMsWith`.
    final at = timeline.tailAt(
          projectMs,
          runMs: ref.read(projectRunMsProvider(widget.projectId)),
        ) ??
        timeline.clipAt(projectMs);
    if (at == null) return;

    // Script mode reads this, so it has to keep moving.
    if (at.clipId != ref.read(selectedClipProvider(widget.projectId))) {
      ref
          .read(selectedClipProvider(widget.projectId).notifier)
          .select(at.clipId);
    }

    // Only a real drag scrubs. A scroll this widget issued itself while
    // following playback must not be fed back as a seek.
    if (!_scrubbing) return;

    // `clipMs` is media time, so this is already past a trimmed clip's
    // in-point -- see `ProjectTimeline.clipAt`.
    ref.read(mediaPlayerProvider(at.clipId).notifier).seekTo(at.clipMs);
  }

  /// Scrolls the track so [projectMs] sits under the playhead.
  void _followPlayback(int projectMs) {
    if (_scrubbing || !_scroll.hasClients) return;
    if (projectMs == _followedMs) return;
    _followedMs = projectMs;

    final target = (projectMs / 1000 * _pps)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((target - _scroll.offset).abs() < 0.5) return;
    _scroll.jumpTo(target);
  }

  /// The clip being trimmed, and where its edges currently sit.
  String? _trimmingId;
  ClipWindow? _trimmed;
  ClipEdge _trimEdge = ClipEdge.end;
  double _trimPixels = 0;

  ClipWindow _windowOf(MediaClip clip) {
    if (clip.id == _trimmingId && _trimmed != null) return _trimmed!;
    if (clip.id == _partnerId && _partnerWindow != null) {
      return _partnerWindow!;
    }
    return clipWindow(clip);
  }

  /// A clip's width *is* its duration -- the trimmed one. See the class doc on
  /// [TimelineBody] for why there is no minimum and no gap.
  double _widthOf(MediaClip clip) {
    final window = _windowOf(clip);
    return (window.endMs - window.startMs) / 1000 * _pps;
  }

  /// The clip on the other side of this edge, when the two are one cut.
  MediaClip? _partnerAcross(MediaClip clip, ClipEdge edge) {
    final index = widget.clips.indexWhere((other) => other.id == clip.id);
    if (index < 0) return null;

    final neighbourIndex = edge == ClipEdge.end ? index + 1 : index - 1;
    if (neighbourIndex < 0 || neighbourIndex >= widget.clips.length) {
      return null;
    }

    final neighbour = widget.clips[neighbourIndex];
    final left = edge == ClipEdge.end ? clip : neighbour;
    final right = edge == ClipEdge.end ? neighbour : clip;
    return sharesACut(left, right) ? neighbour : null;
  }

  /// The partner's previewed window during a roll, so both sides move at once.
  String? _partnerId;
  ClipWindow? _partnerWindow;

  void _startTrim(MediaClip clip, ClipEdge edge) {
    final partner = _partnerAcross(clip, edge);
    setState(() {
      _trimmingId = clip.id;
      _trimEdge = edge;
      _trimPixels = 0;
      _trimmed = clipWindow(clip);
      _partnerId = partner?.id;
      _partnerWindow = partner == null ? null : clipWindow(partner);
    });
  }

  void _updateTrim(MediaClip clip, double deltaPixels) {
    if (_trimmingId != clip.id) return;

    _trimPixels += deltaPixels;
    final deltaMs = (_trimPixels / _pps * 1000).round();

    final partnerId = _partnerId;
    if (partnerId != null) {
      // Rolling, not resizing. Extending one half of a split back over the
      // other made the project longer than the file it came from and played the
      // overlap twice.
      final partner =
          widget.clips.firstWhere((other) => other.id == partnerId);
      final left = _trimEdge == ClipEdge.end ? clip : partner;
      final right = _trimEdge == ClipEdge.end ? partner : clip;
      final rolled = rollCut(
        left: left,
        right: right,
        deltaMs: _trimEdge == ClipEdge.end ? deltaMs : -deltaMs,
      );

      setState(() {
        _trimmed = _trimEdge == ClipEdge.end ? rolled.left : rolled.right;
        _partnerWindow = _trimEdge == ClipEdge.end ? rolled.right : rolled.left;
      });
      return;
    }

    setState(() {
      _trimmed = applyTrim(clip: clip, edge: _trimEdge, deltaMs: deltaMs);
    });
  }

  Future<void> _endTrim(MediaClip clip) async {
    final window = _trimmed;
    final partnerId = _partnerId;
    final partnerWindow = _partnerWindow;
    final edge = _trimEdge;

    setState(() {
      _trimmingId = null;
      _trimmed = null;
      _trimPixels = 0;
      _partnerId = null;
      _partnerWindow = null;
    });

    if (window == null || window == clipWindow(clip)) return;
    final repository = ref.read(transcriptRepositoryProvider);

    if (partnerId != null && partnerWindow != null) {
      await repository.rollCut(
        leftClipId: edge == ClipEdge.end ? clip.id : partnerId,
        rightClipId: edge == ClipEdge.end ? partnerId : clip.id,
        cut: edge == ClipEdge.end
            ? (left: window, right: partnerWindow)
            : (left: partnerWindow, right: window),
      );
      return;
    }

    await repository.trimClip(clipId: clip.id, window: window);
  }

  /// The video track: one tile per clip, plus the button that adds another.
  Widget _clipRow() {
    final selection = ref.watch(timelineSelectionProvider(widget.projectId));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, clip) in widget.clips.indexed)
          KeyedSubtree(
            key: ValueKey(clip.id),
            child: _movable(
            (kind: TimelineItemKind.clip, id: clip.id),
            selection,
            dx: _move?.clipId == clip.id ? _move!.clipDx : 0,
            child: _ClipTile(
            clip: clip,
            width: _widthOf(clip),
            window: _windowOf(clip),
            first: index == 0,
            // **Selection is what the tools act on, not what is playing.**
            // The preview follows the playhead now, so a highlighted clip
            // means "Split and Trim will touch this" and nothing else.
            selected: selection.contains(
              (kind: TimelineItemKind.clip, id: clip.id),
            ),
            handles: _resizable(
              ref,
              widget.projectId,
              (kind: TimelineItemKind.clip, id: clip.id),
            ),
            onTap: () => ref
                .read(timelineSelectionProvider(widget.projectId).notifier)
                .tap((kind: TimelineItemKind.clip, id: clip.id)),
            onLongPress: () => _longPress(
              (kind: TimelineItemKind.clip, id: clip.id),
            ),
            onTrimStart: (edge) => _startTrim(clip, edge),
            onTrimUpdate: (delta) => _updateTrim(clip, delta),
            onTrimEnd: () => _endTrim(clip),
          ),
          ),
          ),
        _AddClipTile(
          busy: ref.watch(addClipControllerProvider(widget.projectId))
              is AddClipCopying,
          onTap: widget.onAddClip,
        ),
      ],
    );
  }

  /// The audio track: each clip's sound, drawn at where it plays.
  Widget _audioRow(double trackWidth) {
    final timeline = ref.watch(projectTimelineProvider(widget.projectId));
    double x(int ms) => ms / 1000 * _pps;

    final entries = [
      for (final clip in widget.clips)
        if (audioSpan(
          timeline,
          clip,
          offsets: clip.id == _audioDragId
              ? _audioDragged
              : _plannedOffsets(clip),
        )
            case final span?)
          (clip: clip, span: span),
    ];
    final lanes = packLanes(
      entries,
      startOf: (e) => e.span.startMs,
      endOf: (e) => e.span.endMs,
    );
    final rowHeight = _trackHeight / math.max(1, lanes.length);

    return SizedBox(
      width: trackWidth <= 0 ? 1 : trackWidth,
      height: _trackHeight,
      child: Stack(
        children: [
          for (final (row, lane) in lanes.indexed)
            for (final (index, entry) in lane.indexed)
              Positioned(
                // Keyed, so a sound slid into another row keeps its drag.
                key: ValueKey(entry.clip.id),
                left: x(entry.span.startMs),
                width: math.max(x(entry.span.endMs - entry.span.startMs), 2),
                top: row * rowHeight,
                height: rowHeight,
                child: _movable(
                  _audioItem(entry.clip),
                  ref.watch(timelineSelectionProvider(widget.projectId)),
                  child: _AudioBlock(
                  clip: entry.clip,
                  mediaStartMs: entry.span.mediaStartMs,
                  lengthMs: entry.span.endMs - entry.span.startMs,
                  // A divider where it meets the sound before it in its row.
                  divided: index > 0 &&
                      lane[index - 1].span.endMs >= entry.span.startMs,
                  selected: ref
                      .watch(timelineSelectionProvider(widget.projectId))
                      .contains(_audioItem(entry.clip)),
                  handles: _resizable(
                    ref,
                    widget.projectId,
                    _audioItem(entry.clip),
                  ),
                  onTap: () => ref
                      .read(timelineSelectionProvider(widget.projectId)
                          .notifier)
                      .tap(_audioItem(entry.clip)),
                  onLongPress: () => _longPress(_audioItem(entry.clip)),
                  onTrimStart: (edge) => _startAudioTrim(entry.clip, edge),
                  onTrimUpdate: (dx) => _updateAudioTrim(entry.clip, dx),
                  onTrimEnd: () => _endAudioTrim(entry.clip),
                ),
                ),
              ),
        ],
      ),
    );
  }

  /// [child] answering a drag when [item] is selected: the whole selection
  /// moves -- a clip alone reorders, drawn [dx] off while it does.
  Widget _movable(
    TimelineItem item,
    Set<TimelineItem> selection, {
    double dx = 0,
    required Widget child,
  }) {
    final draggable = selection.contains(item);
    return GestureDetector(
      onPanStart: draggable ? (d) => _startMove(d.globalPosition) : null,
      onPanUpdate: draggable ? (d) => _updateMove(d.globalPosition) : null,
      onPanEnd: draggable ? (_) => _endMove() : null,
      onPanCancel: draggable ? _endMove : null,
      // Always the same wrappers, whatever the offset: a tree that changed
      // shape as the drag began would drop the drag.
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Opacity(opacity: dx == 0 ? 1 : 0.85, child: child),
      ),
    );
  }

  /// Where a sound being slid with a drag would sit against its picture.
  AudioOffsets? _plannedOffsets(MediaClip clip) {
    final item = _audioItem(clip);
    final planned =
        _move?.plan?.blocks.where((b) => b.item == item).firstOrNull;
    if (planned == null) return null;
    final block = _contents.blocks.where((b) => b.item == item).firstOrNull;
    if (block == null) return null;
    final shift = planned.startMs - block.startMs;
    return (
      startOffsetMs: clip.audioStartOffsetMs + shift,
      endOffsetMs: clip.audioEndOffsetMs + shift,
    );
  }

  TimelineItem _audioItem(MediaClip clip) =>
      (kind: TimelineItemKind.audio, id: clip.id);

  /// The sound being dragged, and where its ends currently sit. Held here
  /// while the finger is down and written once on release, as clip trims are.
  String? _audioDragId;
  ClipEdge _audioEdge = ClipEdge.end;
  double _audioPixels = 0;
  AudioOffsets? _audioDragged;

  void _startAudioTrim(MediaClip clip, ClipEdge edge) {
    setState(() {
      _audioDragId = clip.id;
      _audioEdge = edge;
      _audioPixels = 0;
      _audioDragged = (
        startOffsetMs: clip.audioStartOffsetMs,
        endOffsetMs: clip.audioEndOffsetMs,
      );
    });
  }

  void _updateAudioTrim(MediaClip clip, double dx) {
    if (_audioDragId != clip.id) return;
    final timeline = ref.read(projectTimelineProvider(widget.projectId));
    final placement = timeline.placementOf(clip.id);
    if (placement == null) return;
    _audioPixels += dx;
    setState(() {
      _audioDragged = applyAudioTrim(
        clip: clip,
        edge: _audioEdge,
        deltaMs: (_audioPixels / _pps * 1000).round(),
        placementStartMs: placement.startMs,
        totalMs: timeline.totalMs,
      );
    });
  }

  Future<void> _endAudioTrim(MediaClip clip) async {
    final result = _audioDragged;
    setState(() {
      _audioDragId = null;
      _audioDragged = null;
      _audioPixels = 0;
    });
    if (result == null) return;
    await ref
        .read(transcriptRepositoryProvider)
        .trimAudio(clipId: clip.id, offsets: result);
  }

  /// A long press: the item joins a multi-selection, with a tick of haptic
  /// feedback so the hold is felt to have landed.
  void _longPress(TimelineItem item) {
    HapticFeedback.selectionClick();
    ref
        .read(timelineSelectionProvider(widget.projectId).notifier)
        .longPress(item);
  }

  // ---------------------------------------------------------------------------
  // Moving and resizing, the same for every kind of item.

  /// The Column holding the ruler and the lanes, for finding which lane a
  /// finger is over; and the visible strip, for its edges.
  final _lanesKey = GlobalKey();
  final _viewportKey = GlobalKey();

  _Move? _move;
  _Resize? _resize;
  Timer? _edgeTimer;
  double _edgeSpeed = 0;

  /// The lanes as last built, so a drag can tell which one a finger is over.
  List<_TrackSpec> _specs = const [];

  TimelineContents get _contents =>
      ref.read(timelineContentsProvider(widget.projectId));

  List<TrackSlot> get _slots => [
        for (final spec in _specs)
          if (spec.newTrack == null) (id: spec.trackId, kind: spec.kind),
      ];

  /// Whether a drag starting on [block] moves the selection: it is selected,
  /// or it is a sentence riding on a selected transcription.
  bool _draggable(TimelineBlock block, Set<TimelineItem> selection) =>
      selection.contains(block.item) ||
      (block.follows &&
          block.layerId != null &&
          selection.contains((kind: TimelineItemKind.layer, id: block.layerId!)));

  /// Which lane, counted from the top, is under [globalY]: -1 above the
  /// first, the lane count anywhere below the last -- which is where a drop
  /// makes a new track.
  int? _rowAt(double globalY) {
    final box = _lanesKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    var y = box.globalToLocal(Offset(0, globalY)).dy -
        _rulerHeight -
        AppSpacing.xs;
    if (y < 0) return -1;
    final lanes = _slots.length;
    var row = 0;
    for (final spec in _specs) {
      if (spec.newTrack != null) continue;
      final bottom = spec.height + AppSpacing.xs;
      if (y < bottom) return row;
      y -= bottom;
      row++;
    }
    return lanes;
  }

  void _startMove(Offset global) {
    final selection = ref.read(timelineSelectionProvider(widget.projectId));
    if (selection.isEmpty || _resize != null) return;
    final clips = idsOfKind(selection, TimelineItemKind.clip);
    // Clips reorder one at a time; a group with one in it stays put.
    if (clips.isNotEmpty && selection.length > 1) return;
    HapticFeedback.selectionClick();
    setState(() {
      _move = _Move(
        moving: selection,
        origin: global,
        scrollAt: _scroll.hasClients ? _scroll.offset : 0,
        startRow: _rowAt(global.dy) ?? 0,
        clipId: clips.firstOrNull,
      );
    });
  }

  void _updateMove(Offset global) {
    final move = _move;
    if (move == null) return;
    move.pointer = global;
    _replanMove();
    _edgeScroll(global);
  }

  /// How far the finger has carried things along the axis, counting what
  /// the timeline scrolled under it.
  double _travel(Offset origin, Offset pointer, double scrollAt) =>
      pointer.dx -
      origin.dx +
      ((_scroll.hasClients ? _scroll.offset : scrollAt) - scrollAt);

  void _replanMove() {
    final move = _move;
    if (move == null) return;
    final dx = _travel(move.origin, move.pointer, move.scrollAt);
    if (move.clipId != null) {
      setState(() => move.clipDx = dx);
      return;
    }
    final row = _rowAt(move.pointer.dy) ?? move.startRow;
    setState(() {
      move.plan = planMove(
        blocks: _contents.blocks,
        moving: move.moving,
        deltaMs: (dx / _pps * 1000).round(),
        deltaRows: row - move.startRow,
        tracks: _slots,
      );
    });
  }

  Future<void> _endMove() async {
    _stopEdgeScroll();
    final move = _move;
    if (move == null) return;
    setState(() => _move = null);

    final repository = ref.read(transcriptRepositoryProvider);
    final contents = _contents;

    final clipId = move.clipId;
    if (clipId != null) {
      // Dropped where its middle now is, among the other clips' middles.
      final block = contents.blocks
          .where((b) => b.item == (kind: TimelineItemKind.clip, id: clipId))
          .firstOrNull;
      if (block == null) return;
      final middle = (block.startMs + block.endMs) / 2 +
          move.clipDx / _pps * 1000;
      final others = [
        for (final b in contents.blocks)
          if (b.item.kind == TimelineItemKind.clip && b.item.id != clipId) b,
      ]..sort((a, b) => a.startMs - b.startMs);
      final slot =
          others.where((b) => (b.startMs + b.endMs) / 2 < middle).length;
      final order = [for (final b in others) b.item.id]..insert(slot, clipId);
      await repository.placeItems(
        projectId: widget.projectId,
        placements: const [],
        clipOrder: order,
      );
      return;
    }

    final plan = move.plan;
    if (plan == null || (plan.deltaMs == 0 && plan.deltaRows == 0)) return;
    if (!plan.valid) {
      // Nothing moves; the items go back where they were.
      HapticFeedback.heavyImpact();
      return;
    }
    final from = {for (final b in contents.blocks) b.item: b};
    await repository.placeItems(
      projectId: widget.projectId,
      newTracks: plan.newTracks,
      placements: [
        for (final planned in plan.blocks)
          if (from[planned.item] case final block?)
            (
              item: planned.item,
              fromStartMs: block.startMs,
              fromEndMs: block.endMs,
              toStartMs: planned.startMs,
              toEndMs: planned.endMs,
              trackId:
                  planned.trackId == block.trackId ? null : planned.trackId,
              newTrack: planned.newTrack,
            ),
      ],
    );
  }

  void _startResize(TimelineItem item, LayerGrip grip, Offset global) {
    if (_move != null) return;
    setState(() {
      _resize = _Resize(
        item: item,
        grip: grip,
        origin: global,
        scrollAt: _scroll.hasClients ? _scroll.offset : 0,
      );
    });
  }

  void _updateResize(Offset global) {
    final resize = _resize;
    if (resize == null) return;
    resize.pointer = global;
    _replanResize();
    _edgeScroll(global);
  }

  void _replanResize() {
    final resize = _resize;
    if (resize == null) return;
    final contents = _contents;
    final block =
        contents.blocks.where((b) => b.item == resize.item).firstOrNull;
    if (block == null) return;
    final dx = _travel(resize.origin, resize.pointer, resize.scrollAt);
    setState(() {
      resize.bounds = planResize(
        block: block,
        blocks: contents.blocks,
        grip: resize.grip,
        deltaMs: (dx / _pps * 1000).round(),
        pixelsPerSecond: _pps,
        snapTargets: layerSnapTargets(
          timeline: ref.read(projectTimelineProvider(widget.projectId)),
          playheadMs: ref.read(timelinePlayheadProvider(widget.projectId)),
        ),
      );
    });
  }

  Future<void> _endResize() async {
    _stopEdgeScroll();
    final resize = _resize;
    if (resize == null) return;
    setState(() => _resize = null);
    final bounds = resize.bounds;
    final block =
        _contents.blocks.where((b) => b.item == resize.item).firstOrNull;
    if (bounds == null || block == null) return;
    if (bounds.startMs == block.startMs && bounds.endMs == block.endMs) return;
    await ref.read(transcriptRepositoryProvider).placeItems(
      projectId: widget.projectId,
      placements: [
        (
          item: block.item,
          fromStartMs: block.startMs,
          fromEndMs: block.endMs,
          toStartMs: bounds.startMs,
          toEndMs: bounds.endMs,
          trackId: null,
          newTrack: null,
        ),
      ],
    );
  }

  /// Scrolls -- and so seeks -- while a drag holds a finger near either edge
  /// of the timeline, faster the nearer it is, so an item can be carried
  /// past what is on screen.
  void _edgeScroll(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = left + box.size.width;
    const zone = 48.0;
    const fastest = 12.0;
    var speed = 0.0;
    if (global.dx < left + zone) {
      speed = -fastest * ((left + zone - global.dx) / zone).clamp(0.0, 1.0);
    } else if (global.dx > right - zone) {
      speed = fastest * ((global.dx - right + zone) / zone).clamp(0.0, 1.0);
    }
    _edgeSpeed = speed;
    if (speed == 0) {
      _stopEdgeScroll();
      return;
    }
    _edgeTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _edgeTick(),
    );
  }

  void _edgeTick() {
    if ((_move == null && _resize == null) || !_scroll.hasClients) {
      _stopEdgeScroll();
      return;
    }
    final next = (_scroll.offset + _edgeSpeed)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (next == _scroll.offset) return;
    // A seek the user is asking for, so the player follows.
    _scrubbing = true;
    _scroll.jumpTo(next);
    _scrubbing = false;
    if (_move != null) {
      _replanMove();
    } else {
      _replanResize();
    }
  }

  void _stopEdgeScroll() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeSpeed = 0;
  }

  /// Where [block] is drawn now: where a drag or resize under way would put
  /// it, else where it is.
  ({int startMs, int endMs, String? trackId, int? newTrack, bool live})
      _shownAt(TimelineBlock block, Map<TimelineItem, PlannedBlock> planned) {
    final resize = _resize;
    final bounds = resize?.item == block.item ? resize?.bounds : null;
    if (bounds != null) {
      return (
        startMs: bounds.startMs,
        endMs: bounds.endMs,
        trackId: block.trackId,
        newTrack: null,
        live: true,
      );
    }
    if (planned[block.item] case final p?) {
      return (
        startMs: p.startMs,
        endMs: p.endMs,
        trackId: p.trackId,
        newTrack: p.newTrack,
        live: true,
      );
    }
    return (
      startMs: block.startMs,
      endMs: block.endMs,
      trackId: block.trackId,
      newTrack: null,
      live: false,
    );
  }

  /// One media track -- or, with [newTrack], the dotted lane a drop would make.
  /// transcriptions with their sentences, texts, images and translation lines,
  /// each answering taps, holds, drags and its grips the same way.
  Widget _mediaLane({
    required String? trackId,
    int? newTrack,
    required double width,
    required double height,
  }) {
    final theme = Theme.of(context);
    final contents = ref.watch(timelineContentsProvider(widget.projectId));
    final selection = ref.watch(timelineSelectionProvider(widget.projectId));
    final planned = {
      for (final p in _move?.plan?.blocks ?? const <PlannedBlock>[]) p.item: p,
    };
    final invalid = _move?.plan?.valid == false;
    double x(int ms) => ms / 1000 * _pps;

    // Each item stays where it is while it is carried.
    final here = [
      if (newTrack == null)
        for (final block in contents.blocks)
          if (block.item.kind != TimelineItemKind.clip &&
              block.item.kind != TimelineItemKind.audio &&
              block.trackId == trackId)
            (block: block, shown: _shownAt(block, const {})),
    ];
    final ghosts = [
      for (final block in contents.blocks)
        if (planned.containsKey(block.item))
          if (_shownAt(block, planned) case final shown)
            if (newTrack != null
                ? shown.newTrack == newTrack
                : shown.newTrack == null && shown.trackId == trackId)
              (block: block, shown: shown),
    ];
    // Bands underneath, so the sentences on them stay reachable.
    here.sort((a, b) {
      final aBand = a.block.item.kind == TimelineItemKind.layer ? 0 : 1;
      final bBand = b.block.item.kind == TimelineItemKind.layer ? 0 : 1;
      if (aBand != bBand) return aBand - bBand;
      return a.shown.startMs - b.shown.startMs;
    });

    final selectionNotifier =
        ref.read(timelineSelectionProvider(widget.projectId).notifier);

    Widget item(TimelineBlock block, Widget child) {
      final draggable = _draggable(block, selection);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => selectionNotifier.tap(block.item),
        onLongPress: () => _longPress(block.item),
        onPanStart: draggable ? (d) => _startMove(d.globalPosition) : null,
        onPanUpdate: draggable ? (d) => _updateMove(d.globalPosition) : null,
        onPanEnd: draggable ? (_) => _endMove() : null,
        onPanCancel: draggable ? _endMove : null,
        child: child,
      );
    }

    Widget visual(TimelineBlock block, bool dividedLeft, bool joinedRight) {
      final id = block.item.id;
      final selected = selection.contains(block.item);
      switch (block.item.kind) {
        case TimelineItemKind.layer:
          return _LayerBand(selected: selected);
        case TimelineItemKind.sentence:
          final sentence = contents.sentences[block.item];
          final fill = SpeakerPalette.colorFor(
            sentence?.speaker,
            fallback: theme.colorScheme.onSurface,
            custom: sentence == null
                ? null
                : ref
                    .watch(speakerNamesProvider(sentence.transcriptId))
                    .colorOf(sentence.speaker),
          );
          return DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : dividedLeft
                      ? Border(
                          left: BorderSide(
                            color: theme.colorScheme.surface
                                .withValues(alpha: 0.75),
                          ),
                        )
                      : null,
            ),
          );
        case TimelineItemKind.text:
          return _ItemTile(
            icon: Icons.title,
            selected: selected,
            label: contents.texts[id]?.content,
          );
        case TimelineItemKind.translation:
          final content = contents.translations[id]?.line.content ?? '';
          return _ItemTile(
            icon: Icons.translate,
            selected: selected,
            label: content,
            direction: translationDirectionOf(content),
            joinedLeft: dividedLeft,
            joinedRight: joinedRight,
          );
        case TimelineItemKind.image:
          return _ItemTile(
            icon: Icons.image_outlined,
            selected: selected,
            image: contents.images[id]?.path,
          );
        case TimelineItemKind.clip:
        case TimelineItemKind.audio:
          return const SizedBox.shrink();
      }
    }

    final children = <Widget>[];
    for (final (i, entry) in here.indexed) {
      final block = entry.block;
      final shown = entry.shown;
      final left = x(shown.startMs);
      final w = math.max(x(shown.endMs - shown.startMs), 2.0);
      bool touching(
        ({TimelineBlock block, ({int startMs, int endMs, String? trackId, int? newTrack, bool live}) shown})? a,
        ({TimelineBlock block, ({int startMs, int endMs, String? trackId, int? newTrack, bool live}) shown})? b,
      ) =>
          a != null &&
          b != null &&
          a.block.item.kind == b.block.item.kind &&
          !selection.contains(a.block.item) &&
          !selection.contains(b.block.item) &&
          x(b.shown.startMs) - x(a.shown.endMs) < _sentenceJoinGap;
      final dividedLeft = touching(i > 0 ? here[i - 1] : null, entry);
      final joinedRight =
          touching(entry, i + 1 < here.length ? here[i + 1] : null);
      final band = block.item.kind == TimelineItemKind.layer;
      children.add(Positioned(
        key: ValueKey(('item', block.item)),
        left: left,
        width: w,
        top: band ? 0 : AppSpacing.xxs,
        bottom: band ? 0 : AppSpacing.xxs,
        child: item(
          block,
          Opacity(
            // Faded where it was while it is carried elsewhere.
            opacity: planned.containsKey(block.item) ? 0.3 : 1,
            child: visual(block, dividedLeft, joinedRight),
          ),
        ),
      ));
    }

    // What is being carried here: where it would land, tinted when it
    // cannot. Never answers a finger -- the item it stands for does.
    for (final entry in ghosts) {
      final block = entry.block;
      final band = block.item.kind == TimelineItemKind.layer;
      final ghost = Opacity(
        opacity: 0.85,
        child: visual(block, false, false),
      );
      children.add(Positioned(
        key: ValueKey(('ghost', block.item)),
        left: x(entry.shown.startMs),
        width: math.max(x(entry.shown.endMs - entry.shown.startMs), 2.0),
        top: band ? 0 : AppSpacing.xxs,
        bottom: band ? 0 : AppSpacing.xxs,
        child: IgnorePointer(
          child: invalid
              ? ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    theme.colorScheme.error.withValues(alpha: 0.55),
                    BlendMode.srcATop,
                  ),
                  child: ghost,
                )
              : ghost,
        ),
      ));
    }

    // Grips on the one item picked on its own, over everything else here.
    if (newTrack == null) {
      for (final entry in here) {
        final block = entry.block;
        if (!_resizable(ref, widget.projectId, block.item)) continue;
        final left = x(entry.shown.startMs);
        final w = math.max(x(entry.shown.endMs - entry.shown.startMs), 2.0);
        // Never more than a third each, so the middle always moves it.
        final grab = math.max(8.0, math.min(_layerHandleWidth * 0.7, w / 3));
        for (final (grip, at) in [
          (LayerGrip.start, left),
          (LayerGrip.end, left + w - grab),
        ]) {
          children.add(Positioned(
            key: ValueKey(('grip', block.item, grip)),
            left: at,
            width: grab,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => selectionNotifier.tap(block.item),
              onHorizontalDragStart: (d) =>
                  _startResize(block.item, grip, d.globalPosition),
              onHorizontalDragUpdate: (d) => _updateResize(d.globalPosition),
              onHorizontalDragEnd: (_) => _endResize(),
              onHorizontalDragCancel: _endResize,
              child: _EndGrip(atStart: grip == LayerGrip.start),
            ),
          ));
        }
      }
    }

    final lane = SizedBox(
      width: width <= 0 ? 1 : width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
    return newTrack == null ? lane : _DashedLane(child: lane);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contents = ref.watch(timelineContentsProvider(widget.projectId));
    final selection = ref.watch(timelineSelectionProvider(widget.projectId));

    // Follow playback: the player reports a position inside the selected clip,
    // which the timeline turns into a position on the shared axis.
    final selected = widget.selectedId;
    final selectedClip = selected == null
        ? null
        : widget.clips.where((clip) => clip.id == selected).firstOrNull;
    _follow(
      selected == null ? null : ref.watch(mediaPlayerProvider(selected)).value,
      selectedClip?.mediaPath,
    );

    // As long as the project runs, which past a removed tail is longer than
    // its clips: the words there stay reachable.
    final runMs = ref.watch(projectRunMsProvider(widget.projectId));
    final trackWidth = runMs / 1000 * _pps;
    final tracks = _visibleTracks(contents, trackWidth);
    _specs = tracks;

    // **Selecting locks the seek.** With something picked, a drag on the
    // timeline moves it rather than scrolling; the edges scroll for it.
    final locked = selection.isNotEmpty;

    // Ruler, then one lane per track with a gap between each.
    final stackHeight = _rulerHeight +
        AppSpacing.xs +
        tracks.fold<double>(0, (sum, track) => sum + track.height) +
        math.max(0, tracks.length - 1) * AppSpacing.xs;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Half the viewport at each end, which is what lets the very first and
        // very last frame reach a playhead pinned to the centre.
        final lead = (constraints.maxWidth - _gutterWidth) / 2;

        return Listener(
          // Wraps the whole track section, not just the scrolling strip.
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerFinished,
          onPointerCancel: _onPointerFinished,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The gutter sits inside this widget rather than beside it,
                    // which is what lets each control line up with the lane it
                    // belongs to.
                    _TrackGutter(
                      tracks: tracks,
                      topInset: _rulerHeight + AppSpacing.xs,
                      onToggleVisible: (id) => ref
                          .read(hiddenTracksProvider(widget.projectId).notifier)
                          .toggle(id),
                      onMove: _moveTrack,
                      onSelectAll: _selectTrack,
                    ),
                    Expanded(
                      child: Stack(
                        key: _viewportKey,
                        alignment: Alignment.topCenter,
                        children: [
                          NotificationListener<ScrollNotification>(
                            // Only a drag counts as scrubbing.
                            onNotification: (notification) {
                              if (notification is ScrollStartNotification &&
                                  notification.dragDetails != null) {
                                _scrubbing = true;
                              } else if (notification
                                  is ScrollEndNotification) {
                                _scrubbing = false;
                              }
                              return false;
                            },
                            child: SingleChildScrollView(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              physics: _pinch.isPinching || locked
                                  ? const NeverScrollableScrollPhysics()
                                  : null,
                              padding: EdgeInsets.symmetric(horizontal: lead),
                              child: Column(
                                key: _lanesKey,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // The ruler always seeks, even while a
                                  // selection locks the timeline for dragging.
                                  // it holds no items.
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragStart: (_) =>
                                        _scrubbing = true,
                                    onHorizontalDragUpdate: (d) =>
                                        _scrubBy(-d.delta.dx),
                                    onHorizontalDragEnd: (_) =>
                                        _scrubbing = false,
                                    onHorizontalDragCancel: () =>
                                        _scrubbing = false,
                                    onTapUp: (d) => _seekToX(
                                      d.localPosition.dx,
                                    ),
                                    child: _TimeRuler(
                                      totalMs: runMs,
                                      width: trackWidth,
                                      pixelsPerSecond: _pps,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  for (final (index, track) in tracks.indexed)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: index == 0 ? 0 : AppSpacing.xs,
                                      ),
                                      child: SizedBox(
                                        height: track.height,
                                        // A hidden track keeps its lane rather
                                        // than collapsing it.
                                        child: track.visible
                                            ? GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onTap: track.newTrack == null
                                                    ? () => ref
                                                        .read(
                                                          timelineSelectionProvider(
                                                            widget.projectId,
                                                          ).notifier,
                                                        )
                                                        .clear()
                                                    : null,
                                                onLongPress:
                                                    track.newTrack == null
                                                        ? () => _selectTrack(
                                                              track.trackId,
                                                            )
                                                        : null,
                                                child: track.build(),
                                              )
                                            : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // Drawn over the tracks rather than scrolling with
                          // them: it marks a place on the screen, not a place
                          // in the media.
                          IgnorePointer(
                            child: Container(
                              width: _playheadWidth,
                              height: stackHeight,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _AddTrackRow(
                    onAdd: widget.onAddTrack,
                    onAddText: widget.onAddText,
                    onAddImage: widget.onAddImage,
                    onUnavailable: widget.onTrackUnavailable,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [row] with whatever a drag is carrying over it drawn on top -- tinted,
  /// since nothing but clips and sound may land on these tracks.
  Widget _withGhosts(String trackId, double width, Widget row) => Stack(
        children: [
          row,
          if (_move?.plan != null)
            Positioned.fill(
              child: IgnorePointer(
                child: _mediaLane(
                  trackId: trackId,
                  width: width,
                  height: _trackHeight,
                ),
              ),
            ),
        ],
      );

  /// Moves a track one place up or down among those drawn, as one undoable
  /// step.
  void _moveTrack(String trackId, int delta) {
    final drawn = [
      for (final spec in _specs)
        if (spec.newTrack == null) spec.trackId,
    ];
    final at = drawn.indexOf(trackId);
    final to = at + delta;
    if (at < 0 || to < 0 || to >= drawn.length) return;
    final order = [for (final track in _contents.tracks) track.id];
    final a = order.indexOf(trackId);
    final b = order.indexOf(drawn[to]);
    if (a < 0 || b < 0) return;
    order[a] = drawn[to];
    order[b] = trackId;
    ref
        .read(transcriptRepositoryProvider)
        .reorderTracks(projectId: widget.projectId, order: order);
  }

  /// Selects everything on a track: every clip on the video track, every sound
  /// on the audio track, and on any other every item drawn there -- a
  /// transcription and each of its sentences, each shown selected, so a drag.
  void _selectTrack(String trackId) {
    final items = {
      for (final block in _contents.blocks)
        if (block.trackId == trackId) block.item,
    };
    if (items.isEmpty) return;
    HapticFeedback.selectionClick();
    ref
        .read(timelineSelectionProvider(widget.projectId).notifier)
        .selectAll(items);
  }

  /// The lanes to draw, top to bottom as the project's tracks are ordered.
  List<_TrackSpec> _visibleTracks(TimelineContents contents, double width) {
    final hidden = ref.watch(hiddenTracksProvider(widget.projectId));
    final occupied = {for (final block in contents.blocks) block.trackId};
    final specs = <_TrackSpec>[];

    for (final track in contents.tracks) {
      final kind = TrackKind.fromCode(track.kind);
      final visible = !hidden.contains(track.id);
      switch (kind) {
        case TrackKind.video:
          specs.add(_TrackSpec(
            trackId: track.id,
            kind: kind,
            height: _trackHeight,
            visible: visible,
            build: () => _withGhosts(track.id, width, _clipRow()),
          ));
        case TrackKind.audio:
          if (widget.clips.isEmpty) continue;
          specs.add(_TrackSpec(
            trackId: track.id,
            kind: kind,
            height: _trackHeight,
            visible: visible,
            build: () => _withGhosts(track.id, width, _audioRow(width)),
          ));
        case TrackKind.media:
          if (!occupied.contains(track.id)) continue;
          final banded = contents.blocks.any((b) =>
              b.trackId == track.id && b.item.kind == TimelineItemKind.layer);
          final height = banded ? _trackHeight : _textTrackHeight;
          specs.add(_TrackSpec(
            trackId: track.id,
            kind: kind,
            height: height,
            visible: visible,
            build: () => _mediaLane(
              trackId: track.id,
              width: width,
              height: height,
            ),
          ));
      }
    }

    for (var i = 0; i < (_move?.plan?.newTracks ?? 0); i++) {
      specs.add(_TrackSpec(
        trackId: '',
        kind: TrackKind.media,
        height: _textTrackHeight,
        visible: true,
        newTrack: i,
        build: () => _mediaLane(
          trackId: null,
          newTrack: i,
          width: width,
          height: _textTrackHeight,
        ),
      ));
    }
    return specs;
  }
}


/// Width of the controls column beside the tracks.
const double _gutterWidth = 32;

/// Roughly how wide one filmstrip frame is drawn.
const double _filmstripFrameWidth = 48;

/// How many frames a clip [width] points wide has room for.
int _filmstripSlots(double width) =>
    width <= 0 ? 1 : math.max(1, (width / _filmstripFrameWidth).round());

/// How long a freshly drawn layer covers, before the user resizes it.
const int _defaultLayerMs = 10000;

/// Draws a transcribe layer over [clipId] -- or, with no clip, over the first
/// free stretch -- and returns its id, or null if there was no room.
Future<String?> _addLayer(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String? clipId,
}) async {
  final l10n = AppLocalizations.of(context);
  final repository = ref.read(transcriptRepositoryProvider);
  final timeline = ref.read(projectTimelineProvider(projectId));
  final layers = ref.read(projectLayersProvider(projectId)).value ?? const [];

  final placement = clipId == null ? null : timeline.placementOf(clipId);
  final wanted = placement == null
      ? _defaultLayerMs
      : placement.durationMs.clamp(_defaultLayerMs, 1 << 31);

  // Dropped into the first gap that fits rather than always at zero, so
  // adding a second layer does not silently fail against the overlap rule.
  var start = placement?.startMs ?? 0;
  for (final layer in [...layers]..sort((a, b) => a.startMs - b.startMs)) {
    if (layer.startMs - start >= wanted) break;
    if (layer.endMs > start) start = layer.endMs;
  }

  // Never past the end of the project: a layer hanging off the end covers
  // audio that does not exist and would only be trimmed on the first run.
  if (timeline.totalMs > 0 && start >= timeline.totalMs) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.layerNoRoom)));
    }
    return null;
  }
  final end = timeline.totalMs > 0
      ? math.min(start + wanted, timeline.totalMs)
      : start + wanted;

  return repository.addLayer(projectId: projectId, startMs: start, endMs: end);
}

/// Runs [layerId], confirming first if it would replace an earlier run.
Future<void> _transcribeLayer(
  BuildContext context,
  WidgetRef ref,
  String layerId,
) async {
  final l10n = AppLocalizations.of(context);

  final existing =
      await ref.read(transcriptRepositoryProvider).transcriptsForLayer(layerId);
  if (!context.mounted) return;

  // The options come first, every time -- this is the moment they apply to.
  final confirmed = await showTranscriptionOptions(
    context,
    warning: existing.isEmpty ? null : l10n.layerRerunBody,
  );
  if (!confirmed) return;

  // Read now, not before the dialog.
  final controller =
      ref.read(layerTranscriptionControllerProvider(layerId).notifier);
  if (existing.isEmpty) {
    await controller.transcribe();
  } else {
    await controller.rerun();
  }
}

/// What can be done with the selection, one line under the tracks.
class _SelectionStrip extends ConsumerWidget {
  const _SelectionStrip({required this.projectId});

  final String projectId;

  TimelineSelection _selection(WidgetRef ref) =>
      ref.read(timelineSelectionProvider(projectId).notifier);

  /// What a selection's Translate covers: the whole transcription of each
  /// selected layer, and just the words of each selected sentence --
  /// neighbouring sentences joined into one run.
  Future<_TranslationScope> _scopeOf(
    WidgetRef ref,
    Set<TimelineItem> selection,
  ) async {
    final repository = ref.read(transcriptRepositoryProvider);
    final whole = <String>{};
    final pieces = <String, List<({int from, int to})>>{};
    for (final item in selection) {
      if (item.kind == TimelineItemKind.layer) {
        for (final t in await repository.transcriptsForLayer(item.id)) {
          whole.add(t.id);
        }
      } else if (sentenceOf(item) case final sentence?) {
        (pieces[sentence.transcriptId] ??= []).add(
          (from: sentence.fromPosition, to: sentence.toPosition),
        );
      }
    }
    final ranges = <String, List<({int from, int to})>>{};
    for (final MapEntry(key: id, value: list) in pieces.entries) {
      if (whole.contains(id)) continue;
      list.sort((a, b) => a.from.compareTo(b.from));
      final merged = <({int from, int to})>[];
      for (final range in list) {
        if (merged.isNotEmpty && range.from <= merged.last.to + 1) {
          final last = merged.removeLast();
          merged.add((
            from: last.from,
            to: range.to > last.to ? range.to : last.to,
          ));
        } else {
          merged.add(range);
        }
      }
      ranges[id] = merged;
    }
    return (ids: [...whole, ...ranges.keys], ranges: ranges);
  }

  /// Translates what [scope] covers, kept beside the transcriptions on the
  /// Translation track. "Remove translation" is offered when any of it is
  /// translated already.
  Future<void> _translate(
    BuildContext context,
    WidgetRef ref,
    _TranslationScope scope,
  ) async {
    var translated = false;
    for (final id in scope.ids) {
      final lines = await ref
          .read(transcriptRepositoryProvider)
          .watchTranslation(id)
          .first;
      final only = scope.ranges[id];
      if (lines.any((line) =>
          only == null ||
          only.any((r) => line.firstWord <= r.to && line.lastWord >= r.from))) {
        translated = true;
      }
    }
    if (!context.mounted) return;
    await translateTranscripts(
      context,
      ref,
      transcriptIds: scope.ids,
      ranges: scope.ranges,
      hasTranslation: translated,
    );
  }

  /// Deletes everything selected, as undoable steps. A clip comes off the
  /// timeline; its media stays with the project (`removeClip`), so there is
  /// nothing to confirm.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Set<TimelineItem> selection,
  ) async {
    final clipIds = idsOfKind(selection, TimelineItemKind.clip);

    final repository = ref.read(transcriptRepositoryProvider);
    // A transcription selected with its sentences -- a whole track -- is
    // removed whole: its words go with it, not one sentence at a time.
    final layerIds = idsOfKind(selection, TimelineItemKind.layer);
    final wholeLayers = {
      for (final sentence in ref.read(projectSentencesProvider(projectId)))
        if (layerIds.contains(sentence.layerId)) sentence.transcriptId,
    };
    // A sound is removed from the timeline, not deleted: its picture stays,
    // and Restore -- or undo -- puts it back.
    final sounds = idsOfKind(selection, TimelineItemKind.audio)
        .where((id) => !clipIds.contains(id))
        .toList();
    if (sounds.isNotEmpty) {
      await repository.setAudioMuted(
        projectId: projectId,
        clipIds: sounds,
        muted: true,
      );
    }
    for (final id in idsOfKind(selection, TimelineItemKind.layer)) {
      await repository.removeLayer(id);
    }
    for (final id in idsOfKind(selection, TimelineItemKind.text)) {
      await repository.removeTextLayer(id);
    }
    await repository.removeTranslationLines(
      projectId: projectId,
      ids: idsOfKind(selection, TimelineItemKind.translation).toList(),
    );
    await repository.removeImages(
      projectId,
      idsOfKind(selection, TimelineItemKind.image).toList(),
    );
    // Sentences last, and the latest words first within a transcript:
    // removing words renumbers every word after them.
    final sentences = [
      for (final item in selection)
        if (sentenceOf(item) case final sentence?
            when !wholeLayers.contains(sentence.transcriptId))
          sentence,
    ]..sort((a, b) => b.fromPosition.compareTo(a.fromPosition));
    for (final sentence in sentences) {
      await repository.removeSentence(
        transcriptId: sentence.transcriptId,
        fromPosition: sentence.fromPosition,
        toPosition: sentence.toPosition,
      );
    }
    for (final id in clipIds) {
      await ref.read(clipEditorProvider).remove(id);
      // The removed clip may have been the one on show; clearing lets both
      // modes fall back to one that still exists.
      if (ref.read(selectedClipProvider(projectId)) == id) {
        ref.read(selectedClipProvider(projectId).notifier).clear();
      }
    }
    _selection(ref).clear();
  }

  /// Whether [clipId]'s sound has been removed from the timeline.
  bool _mutedClip(WidgetRef ref, String clipId) =>
      (ref.watch(projectClipsProvider(projectId)).value ?? const [])
          .where((clip) => clip.id == clipId)
          .firstOrNull
          ?.audioMuted ??
      false;

  /// Opens [item]'s words for typing on the stage, where they stand.
  void _type(WidgetRef ref, TimelineItem item) =>
      ref.read(stageEditingProvider(projectId).notifier).start(item);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selection = ref.watch(timelineSelectionProvider(projectId));
    final multi = ref.watch(timelineMultiSelectProvider(projectId));
    final only = selection.length == 1 ? selection.first : null;
    final layerId =
        only?.kind == TimelineItemKind.layer ? only!.id : null;

    // The engine's state for a selected layer. Watched rather than read so
    // the strip follows a run that is already under way -- returning to the
    // screen mid-transcription must not look idle.
    final status = layerId == null
        ? const LayerTranscriptionIdle()
        : ref.watch(layerTranscriptionControllerProvider(layerId));

    final hint = theme.textTheme.bodySmall;

    final Widget content = switch (status) {
      LayerTranscriptionRunning(:final stage, :final percent) => Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(stageLabel(l10n, stage, percent), style: hint),
            ),
          ],
        ),
      LayerTranscriptionFailed() => Row(
          children: [
            Expanded(child: Text(l10n.clipTranscribeFailed, style: hint)),
            AppPressDown(
              child: TextButton(
                onPressed: () => ref
                    .read(layerTranscriptionControllerProvider(layerId!)
                        .notifier)
                    .transcribe(),
                child: Text(l10n.retryAction),
              ),
            ),
          ],
        ),
      _ when multi || selection.length > 1 => Row(
          children: [
            Expanded(
              child: Text(
                l10n.selectionCount(selection.length),
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (selection.isNotEmpty) ...[
              _StripAction(
                label: l10n.selectionRemove,
                danger: true,
                onPressed: () => _delete(context, ref, selection),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            // Whenever captions are among what is selected: translates the
            // transcriptions they belong to.
            if (selection.any((item) =>
                item.kind == TimelineItemKind.layer ||
                item.kind == TimelineItemKind.sentence)) ...[
              _StripAction(
                label: l10n.translateAction,
                onPressed: () async {
                  final scope = await _scopeOf(ref, selection);
                  if (!context.mounted) return;
                  await _translate(context, ref, scope);
                },
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            AppRaised(
              child: FilledButton(
                onPressed: () => _selection(ref).clear(),
                child: Text(l10n.selectionDone),
              ),
            ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.audio => Row(
          children: [
            Expanded(child: Text(l10n.audioSelected, style: hint)),
            if (_mutedClip(ref, only!.id))
              _StripAction(
                label: l10n.audioRestore,
                onPressed: () => ref
                    .read(transcriptRepositoryProvider)
                    .setAudioMuted(
                      projectId: projectId,
                      clipIds: [only.id],
                      muted: false,
                    ),
              )
            else
              _StripAction(
                label: l10n.selectionRemove,
                danger: true,
                onPressed: () => _delete(context, ref, selection),
              ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.clip => Row(
          children: [
            Expanded(child: Text(l10n.clipSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.text => Row(
          children: [
            Expanded(child: Text(l10n.textSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppRaised(
              child: FilledButton(
                onPressed: () => _type(ref, only!),
                child: Text(l10n.textEdit),
              ),
            ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.translation => Row(
          children: [
            Expanded(child: Text(l10n.translationSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppRaised(
              child: FilledButton(
                onPressed: () => _type(ref, only!),
                child: Text(l10n.textEdit),
              ),
            ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.image => Row(
          children: [
            Expanded(child: Text(l10n.imageSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
          ],
        ),
      _ when only?.kind == TimelineItemKind.sentence => Row(
          children: [
            Expanded(child: Text(l10n.sentenceSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StripAction(
              label: l10n.translateAction,
              onPressed: () async {
                final scope = await _scopeOf(ref, {only!});
                if (!context.mounted) return;
                await _translate(context, ref, scope);
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            AppRaised(
              child: FilledButton(
                onPressed: () => _type(ref, only!),
                child: Text(l10n.textEdit),
              ),
            ),
          ],
        ),
      _ when layerId != null => Row(
          children: [
            Expanded(child: Text(l10n.layerSelected, style: hint)),
            _StripAction(
              label: l10n.selectionRemove,
              danger: true,
              onPressed: () => _delete(context, ref, selection),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StripAction(
              label: l10n.translateAction,
              onPressed: () async {
                final scope = await _scopeOf(ref, selection);
                if (!context.mounted) return;
                await _translate(context, ref, scope);
              },
            ),
          ],
        ),
      _ => Row(
          children: [
            Expanded(child: Text(l10n.selectionHint, style: hint)),
          ],
        ),
    };

    return Padding(
      // Clear of the toolbar below by more than the buttons' shadows, so a
      // pressed button never looks like it is sitting on the toolbar.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      // One height whatever it holds, so the tracks above do not jump as the
      // selection changes what the strip says.
      child: SizedBox(height: 48, child: content),
    );
  }
}

/// What a Translate covers: transcriptions, and for some of them only these
/// word ranges (see `_SelectionStrip._scopeOf`).
typedef _TranslationScope = ({
  List<String> ids,
  Map<String, List<({int from, int to})>> ranges,
});

/// A selection's action, as a raised rectangle that presses down onto its
/// shadow: Remove in the danger red, anything else on the page's own ground
/// with the outline.
class _StripAction extends StatelessWidget {
  const _StripAction({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = context.surface;
    final fill = danger ? scheme.error : scheme.surface;

    return AppRaised(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: danger ? scheme.onError : scheme.onSurface,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(side: surface.side),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// One clip's sound on the audio lane: its stretch of the waveform, where it
/// plays. Picked, it shows the same end handles as a clip; removed, it fades
/// and is struck through, still there to be restored.
class _AudioBlock extends ConsumerWidget {
  const _AudioBlock({
    required this.clip,
    required this.mediaStartMs,
    required this.lengthMs,
    required this.divided,
    required this.selected,
    required this.handles,
    required this.onTap,
    required this.onLongPress,
    required this.onTrimStart,
    required this.onTrimUpdate,
    required this.onTrimEnd,
  });

  final MediaClip clip;

  /// Where in the media the drawn stretch begins, and how long it runs.
  final int mediaStartMs;
  final int lengthMs;

  /// A divider on its left, where it meets the sound before it.
  final bool divided;
  final bool selected;
  final bool handles;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<ClipEdge> onTrimStart;
  final ValueChanged<double> onTrimUpdate;
  final VoidCallback onTrimEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final all = ref.watch(clipWaveformProvider(clip.id)).value ?? Uint8List(0);

    // The readings for just this stretch of the file.
    final from = (mediaStartMs * waveformPeaksPerSecond / 1000)
        .floor()
        .clamp(0, all.length);
    final to = ((mediaStartMs + lengthMs) * waveformPeaksPerSecond / 1000)
        .ceil()
        .clamp(from, all.length);
    final peaks = Uint8List.sublistView(all, from, to);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: clip.audioMuted ? 0.35 : 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: _tileRadius,
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: selected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            )
                          : divided
                              ? Border(left: _clipDivider(theme, surface))
                              : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CustomPaint(
                      painter: _WavePainter(
                        peaks: peaks,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
              // Removed: struck through, so it reads as there but silent.
              if (clip.audioMuted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        height: 2,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              if (handles)
                for (final (edge, atStart) in const [
                  (ClipEdge.start, true),
                  (ClipEdge.end, false),
                ])
                  Positioned(
                    left: atStart ? 0 : null,
                    right: atStart ? null : 0,
                    top: 0,
                    bottom: 0,
                    width: math.max(8, math.min(_layerHandleWidth, width / 2)),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      onHorizontalDragStart: (_) => onTrimStart(edge),
                      onHorizontalDragUpdate: (details) =>
                          onTrimUpdate(details.delta.dx),
                      onHorizontalDragEnd: (_) => onTrimEnd(),
                      child: Align(
                        alignment: atStart
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          width: _layerGripWidth,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: _gripRadius(atStart: atStart),
                          ),
                          child: Icon(
                            atStart ? Icons.chevron_left : Icons.chevron_right,
                            size: _gripArrowSize,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Draws amplitude readings as bars mirrored about the lane's centre line.
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.peaks, required this.color});

  final Uint8List peaks;
  final Color color;

  /// Width of one bar and the gap after it. Wider than a hairline so the lane
  /// reads as bars rather than as a filled shape at a glance.
  static const double _barWidth = 2;
  static const double _barGap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0) return;

    final slot = _barWidth + _barGap;
    final count = (size.width / slot).floor();
    if (count <= 0) return;

    // Resampled to the number of bars that actually fit rather than drawn one
    // bar per stored reading. Every reading still contributes, so the pattern
    // stays put instead of shimmering as the clip's width changes.
    final bars = resamplePeaks(peaks, count);
    final centre = size.height / 2;
    final paint = Paint()..color = color;

    for (var i = 0; i < bars.length; i++) {
      // Always at least a hairline: a bar of zero height would punch a hole in
      // the lane at every quiet moment, which reads as missing data rather
      // than as silence.
      final half = (bars[i] / waveformPeakMax * centre).clamp(0.5, centre);
      canvas.drawRect(
        Rect.fromLTRB(i * slot, centre - half, i * slot + _barWidth, centre + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.peaks != peaks || old.color != color;
}

/// The transcribe track: one rectangle per layer, laid out on the same axis as
/// the clips above it.
const double _layerHandleWidth = 40;

/// The visible grip inside that grab area.
const double _layerGripWidth = 18;

/// The outward arrow on a grip.
const double _gripArrowSize = 14;

/// The grip's corner rounding, applied to its inner edge only.
BorderRadius _gripRadius({required bool atStart}) => BorderRadius.zero;

/// The controls column beside the tracks: one row per lane.
class _TrackGutter extends StatelessWidget {
  const _TrackGutter({
    required this.tracks,
    required this.topInset,
    required this.onToggleVisible,
    required this.onMove,
    required this.onSelectAll,
  });

  final List<_TrackSpec> tracks;

  /// Selects everything on a track: a long press anywhere on its controls.
  final ValueChanged<String> onSelectAll;

  /// Height of the ruler above the first lane, so the first row lines up.
  final double topInset;

  final ValueChanged<String> onToggleVisible;

  /// Moves a track by [delta] places in the stack.
  final void Function(String trackId, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final real = tracks.where((t) => t.newTrack == null).length;
    return SizedBox(
      width: _gutterWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: topInset),
          for (final (index, track) in tracks.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xs),
              child: SizedBox(
                height: track.height,
                // The lane a drop would make has no controls yet.
                child: track.newTrack != null
                    ? null
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () {
                          HapticFeedback.selectionClick();
                          onSelectAll(track.trackId);
                        },
                        child: _TrackControls(
                          track: track,
                          canMoveUp: index > 0,
                          canMoveDown: index < real - 1,
                          onToggleVisible: () => onToggleVisible(track.trackId),
                          onMove: (delta) => onMove(track.trackId, delta),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One lane's controls: show/hide, and a handle that is dragged to reorder.
class _TrackControls extends StatefulWidget {
  const _TrackControls({
    required this.track,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onToggleVisible,
    required this.onMove,
  });

  final _TrackSpec track;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onToggleVisible;
  final ValueChanged<int> onMove;

  @override
  State<_TrackControls> createState() => _TrackControlsState();
}

class _TrackControlsState extends State<_TrackControls> {
  /// How far the handle has been dragged since the last swap.
  double _dragged = 0;

  /// How far the handle travels before the track moves a place.
  static const double _swapDistance = 28;

  void _onDrag(DragUpdateDetails details) {
    _dragged += details.delta.dy;

    while (_dragged.abs() >= _swapDistance) {
      final down = _dragged > 0;
      if (down && !widget.canMoveDown) break;
      if (!down && !widget.canMoveUp) break;

      widget.onMove(down ? 1 : -1);
      _dragged -= down ? _swapDistance : -_swapDistance;
    }

    // A drag that has run out of room should not bank credit it will spend
    // the instant a track appears beneath it.
    if ((_dragged > 0 && !widget.canMoveDown) ||
        (_dragged < 0 && !widget.canMoveUp)) {
      _dragged = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visible = widget.track.visible;
    final canReorder = widget.canMoveUp || widget.canMoveDown;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkResponse(
          radius: 16,
          onTap: widget.onToggleVisible,
          // A label, not a Tooltip: a tooltip opens on long press, which
          // would take the gesture that selects the whole track.
          child: Semantics(
            label: visible ? l10n.trackHide : l10n.trackShow,
            button: true,
            child: Icon(
              visible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: theme.colorScheme.onSurface
                  .withValues(alpha: visible ? 0.9 : 0.4),
            ),
          ),
        ),
        // Only when there is somewhere to go. A handle beside the only track
        // in the stack is a control that cannot do anything.
        if (canReorder) ...[
          const SizedBox(height: AppSpacing.xxs),
          GestureDetector(
            // A drag, not a tap. Tapping it used to rearrange the stack on its
            // own, which told the user nothing about what it would do next.
            onVerticalDragUpdate: _onDrag,
            onVerticalDragEnd: (_) => _dragged = 0,
            onVerticalDragCancel: () => _dragged = 0,
            child: Semantics(
              label: l10n.trackReorder,
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Whether [item] is the one thing selected, outside multi-select: the only
/// time it shows the handles that resize it.
bool _resizable(WidgetRef ref, String projectId, TimelineItem item) {
  final selection = ref.watch(timelineSelectionProvider(projectId));
  return selection.length == 1 &&
      selection.contains(item) &&
      !ref.watch(timelineMultiSelectProvider(projectId));
}

/// How close two sentences must be drawn before they read as one run.
const double _sentenceJoinGap = 3;

/// Where one clip meets the next: a line in the outline's ink when the theme
/// draws outlines, else a cut in the page's own colour.
BorderSide _clipDivider(ThemeData theme, AppSurface surface) =>
    surface.outlined
        ? BorderSide(color: surface.outline)
        : BorderSide(color: theme.colorScheme.surface, width: 2);

/// Height the ruler occupies: ticks plus the labels beneath them.
const double _rulerHeight = 28;

/// A measuring rule: a long tick for each labelled value, short ticks between.
class _TimeRuler extends StatelessWidget {
  const _TimeRuler({
    required this.totalMs,
    required this.width,
    required this.pixelsPerSecond,
  });

  final int totalMs;
  final double width;
  final double pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _rulerHeight,
      width: width <= 0 ? 1 : width,
      child: CustomPaint(
        painter: _RulerPainter(
          totalMs: totalMs,
          pixelsPerSecond: pixelsPerSecond,
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
    required this.pixelsPerSecond,
    required this.ink,
    required this.textStyle,
  });

  final int totalMs;
  final double pixelsPerSecond;
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
    final step = stepFor(pixelsPerSecond);
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
      final x = second * pixelsPerSecond;
      if (x > size.width) break;
      final isMajor = (second / step - (second / step).round()).abs() < 0.001;
      if (isMajor) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, _minorTick), minor);
    }

    for (var second = 0; second <= totalSeconds; second += step) {
      final x = second * pixelsPerSecond;
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
      pixelsPerSecond != oldDelegate.pixelsPerSecond ||
      ink != oldDelegate.ink ||
      textStyle != oldDelegate.textStyle;
}

/// One clip on the track, filled with frames sampled from its own media.
class _ClipTile extends ConsumerWidget {
  const _ClipTile({
    required this.clip,
    required this.width,
    required this.window,
    required this.first,
    required this.selected,
    this.handles = false,
    required this.onTap,
    required this.onLongPress,
    required this.onTrimStart,
    required this.onTrimUpdate,
    required this.onTrimEnd,
  });

  final MediaClip clip;
  final double width;

  /// What the clip currently plays, which during a drag is the preview rather
  /// than what is stored.
  final ClipWindow window;

  final ValueChanged<ClipEdge> onTrimStart;
  final ValueChanged<double> onTrimUpdate;
  final VoidCallback onTrimEnd;

  /// Whether this is the leftmost clip, which has nothing to divide it from.
  final bool first;

  final bool selected;

  /// Shows the trim handles: selected, and on its own.
  final bool handles;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final duration = Duration(milliseconds: window.endMs - window.startMs);

    // Frames are counted from the drawn width, not from the duration.
    final slots = _filmstripSlots(width);
    final count = ThumbnailService.frameCountForSlots(slots, duration);
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
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Container(
                  // The border is drawn *inside* the tile's width rather than
                  // as a gap beside it.
                  decoration: BoxDecoration(
                    borderRadius: _tileRadius,
                    color: theme.colorScheme.surfaceContainerHighest,
                    // The selected clip takes the theme's own call to action,
                    // the same signal `_Segment` uses for a chosen option.
                    border: selected
                        ? Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          )
                        : first
                            ? null
                            : Border(
                                left: _clipDivider(theme, context.surface),
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
                            for (var slot = 0; slot < slots; slot++)
                              Expanded(
                                child: Image.file(
                                  // The frame nearest this slot's moment.
                                  File(frames[slot * frames.length ~/ slots]),
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
            ),
            // Handles sit inside the tile, never straddling its edge.
            if (handles)
              for (final (edge, atStart) in const [
                (ClipEdge.start, true),
                (ClipEdge.end, false),
              ])
                Positioned(
                  left: atStart ? 0 : null,
                  right: atStart ? null : 0,
                  top: 0,
                  bottom: 0,
                  width: math.max(8, math.min(_layerHandleWidth, width / 2)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // Opaque, so it must answer taps as well as drags.
                    onTap: onTap,
                    onHorizontalDragStart: (_) => onTrimStart(edge),
                    onHorizontalDragUpdate: (details) =>
                        onTrimUpdate(details.delta.dx),
                    onHorizontalDragEnd: (_) => onTrimEnd(),
                    // Drawn on the edge, grabbed from inside it.
                    child: Align(
                      alignment:
                          atStart ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        width: _layerGripWidth,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: _gripRadius(atStart: atStart),
                        ),
                        child: Icon(
                          atStart ? Icons.chevron_left : Icons.chevron_right,
                          size: _gripArrowSize,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
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

    return Semantics(
      button: true,
      label: l10n.clipAdd,
      child: InkWell(
        borderRadius: _tileRadius,
        onTap: busy ? null : onTap,
        child: Container(
          width: 56,
          // Deliberately not `surface.decoration`: the theme's 14pt radius is
          // for cards, and this tile stands in a row of clips at 6. Inheriting
          // it made the "+" read as a pill wedged against square neighbours.
          decoration: BoxDecoration(
            borderRadius: _tileRadius,
            color: busy
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
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

/// The kinds of track that can be stacked on the timeline.
enum _TrackKind { transcribe, audio, text, image, video }

/// Adds a track to the stack.
class _AddTrackRow extends StatelessWidget {
  const _AddTrackRow({
    required this.onAdd,
    required this.onAddText,
    required this.onAddImage,
    required this.onUnavailable,
  });

  final VoidCallback onAdd;
  final VoidCallback onAddText;
  final VoidCallback onAddImage;
  final ValueChanged<String> onUnavailable;

  Future<void> _choose(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final entries = <(_TrackKind, IconData, String, String)>[
      (
        _TrackKind.transcribe,
        Icons.graphic_eq,
        l10n.trackKindTranscribe,
        l10n.trackKindTranscribeDetail,
      ),
      (_TrackKind.audio, Icons.music_note, l10n.trackKindAudio, ''),
      (
        _TrackKind.text,
        Icons.title,
        l10n.trackKindText,
        l10n.trackKindTextDetail,
      ),
      (
        _TrackKind.image,
        Icons.image_outlined,
        l10n.trackKindImage,
        l10n.trackKindImageDetail,
      ),
      (_TrackKind.video, Icons.movie_outlined, l10n.trackKindVideo, ''),
    ];

    final chosen = await showModalBottomSheet<_TrackKind>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                l10n.trackAddTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final (kind, icon, label, detail) in entries)
              ListTile(
                enabled: detail.isNotEmpty,
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(
                  detail.isNotEmpty ? detail : l10n.trackKindUnavailable,
                ),
                onTap: () => Navigator.of(context).pop(kind),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    if (chosen == _TrackKind.transcribe) {
      onAdd();
      return;
    }
    if (chosen == _TrackKind.text) {
      onAddText();
      return;
    }
    if (chosen == _TrackKind.image) {
      onAddImage();
      return;
    }
    onUnavailable(chosen.name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;

    return InkWell(
      borderRadius: surface.borderRadius,
      onTap: () => _choose(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        // Outlined where the theme draws outlines; on dark, which does not,
        // the card's fill takes the outline's place.
        decoration: BoxDecoration(
          borderRadius: surface.borderRadius,
          border: surface.border,
          color: surface.outlined
              ? null
              : theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: theme.colorScheme.onSurface),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.trackAdd, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// How long a text added with the Text tool stays on screen.
const int _defaultTextMs = 3000;

/// The text track's lane: shorter than a clip's, since it holds a word or two
/// rather than a filmstrip.
const double _textTrackHeight = 52;

/// The zoom slider, docked above the toolbar while Zoom is on.
class _ZoomBar extends ConsumerStatefulWidget {
  const _ZoomBar({required this.projectId, required this.items});

  final String projectId;

  /// What the slider scales: what is selected, else the clip on the stage.
  final List<TimelineItem> items;

  @override
  ConsumerState<_ZoomBar> createState() => _ZoomBarState();
}

class _ZoomBarState extends ConsumerState<_ZoomBar> {
  Map<TimelineItem, ({ItemTransform from, ItemTransform? own})>? _start;

  /// Where each item sits, from the first one's scale -- the one the slider
  /// shows.
  Map<TimelineItem, ({ItemTransform from, ItemTransform? own})> _stored() =>
      selectedPlacements(ref, widget.projectId, widget.items);

  /// [from] scaled by the same factor that takes the first item to [scale],
  /// so a selection of different sizes keeps its proportions.
  ItemTransform _scaled(
    ItemTransform from,
    double scale,
    Map<TimelineItem, ({ItemTransform from, ItemTransform? own})> start,
  ) {
    final lead = start.values.firstOrNull?.from.scale ?? 1;
    final factor = lead <= 0 ? 1.0 : scale / lead;
    return from.copyWith(
      scale: (from.scale * factor).clamp(0.2, ItemTransform.maxScale).toDouble(),
    );
  }

  void _slide(double scale) {
    final start = _start ??= _stored();
    ref.read(stageLiveProvider(widget.projectId).notifier).show({
      for (final MapEntry(key: item, value: at) in start.entries)
        item: _scaled(at.from, scale, start),
    });
  }

  Future<void> _release(double scale) async {
    final start = _start ?? _stored();
    _start = null;
    await ref.read(transcriptRepositoryProvider).applyPlacements(
      projectId: widget.projectId,
      changes: [
        for (final MapEntry(key: item, value: at) in start.entries)
          (
            kind: item.kind,
            id: item.id,
            before: at.own,
            after: _scaled(at.from, scale, start),
          ),
      ],
    );
    if (mounted) {
      ref.read(stageLiveProvider(widget.projectId).notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;
    final live = ref.watch(stageLiveProvider(widget.projectId));
    // Rebuilt as the rows change, so the value follows an undo.
    ref.watch(projectClipsProvider(widget.projectId));
    ref.watch(projectLayersProvider(widget.projectId));
    ref.watch(projectTextLayersProvider(widget.projectId));
    ref.watch(projectImageLayersProvider(widget.projectId));

    // The first item the slider moves speaks for the rest.
    final lead = _stored().entries.firstOrNull;
    final scale =
        (lead == null ? null : live[lead.key]?.scale ?? lead.value.from.scale) ??
            1;
    const lowest = 0.5;
    const highest = ItemTransform.maxScale;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: DecoratedBox(
        // Flat, like the other docked panels: a control, not an action.
        decoration: surface.decoration(
          fill: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.zoom_out, size: 20),
              Expanded(
                child: Slider(
                  value: scale.clamp(lowest, highest).toDouble(),
                  min: lowest,
                  max: highest,
                  onChanged: lead == null ? null : _slide,
                  onChangeEnd: lead == null ? null : _release,
                ),
              ),
              const Icon(Icons.zoom_in, size: 20),
              SizedBox(
                width: 52,
                child: Text(
                  l10n.zoomPercent((scale * 100).round()),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tools at the foot of the screen, each one working.
class _BottomToolbar extends StatelessWidget {
  /// How many tools the strip holds, and where Style sits among them -- what
  /// the Style panel's link down to its button is measured from. Keep in step
  /// with the list in [build].
  static const toolCount = 6;
  static const styleIndex = 4;

  const _BottomToolbar({
    required this.onSplit,
    required this.onZoom,
    required this.onRotate,
    required this.onText,
    required this.onStyle,
    required this.onTranscribe,
    this.zoomOpen = false,
    this.styleOpen = false,
  });

  final VoidCallback onSplit;
  final VoidCallback onZoom;
  final VoidCallback onRotate;
  final VoidCallback onText;
  final VoidCallback onStyle;
  final VoidCallback onTranscribe;

  /// Whether the style panel is showing, which the Style button reflects.
  final bool styleOpen;

  /// Whether the zoom slider is showing, which the Zoom button reflects.
  final bool zoomOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          // No space above: a panel linked to a tool draws its lines right
          // down to the strip's top line.
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          // One strip with a rule between tools, not a box round each, running
          // to the screen's edges with no line at either end.
          child: AppStrip(
            edgeToEdge: true,
            children: [
              for (final (icon, label, onTap, active) in [
                (Icons.content_cut, l10n.timelineToolSplit, onSplit, false),
                (Icons.zoom_in, l10n.timelineToolZoom, onZoom, zoomOpen),
                (
                  Icons.rotate_90_degrees_cw_outlined,
                  l10n.timelineToolRotate,
                  onRotate,
                  false,
                ),
                (Icons.text_fields, l10n.timelineToolText, onText, false),
                (
                  Icons.palette_outlined,
                  l10n.timelineToolStyle,
                  onStyle,
                  styleOpen,
                ),
                (
                  Icons.subtitles_outlined,
                  l10n.clipTranscribe,
                  onTranscribe,
                  false,
                ),
              ])
                _ToolbarButton(
                  icon: icon,
                  label: label,
                  active: active,
                  onTap: onTap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The tool that is open is a chosen state, so it takes the selection ink,
    // not the action colour.
    final fill = active
        ? theme.colorScheme.secondary
        : theme.colorScheme.surfaceContainerHighest;
    final ink =
        active ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface;

    // The open tool's block reaches over the strip's lines, like every chosen
    // cell. Pressed, the cell sinks straight down into the strip, less than a
    // raised button's drop: it is set in the strip, not standing off it.
    return AppSelectedBleed(
      selected: active,
      color: fill,
      child: AppPushIn(
        face: fill,
        travel: Offset(0, context.surface.offset.dy * 0.75),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // `AppPushIn` supplies the feedback.
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: ink, size: 22),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    label,
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

/// One pipeline stage as a sentence, with its percentage where there is one.
String stageLabel(AppLocalizations l10n, ImportStage stage, int? percent) =>
    switch (stage) {
      ImportStage.preparingModel => l10n.stagePreparingModel,
      ImportStage.copyingMedia => l10n.stageCopyingMedia,
      ImportStage.extractingAudio => l10n.stageExtractingAudio,
      ImportStage.transcribing => percent == null
          ? l10n.stageTranscribing
          : l10n.transcribingPercent(percent),
      ImportStage.identifyingSpeakers => percent == null
          ? l10n.stageIdentifyingSpeakers
          : l10n.identifyingSpeakersPercent(percent),
      ImportStage.saving => l10n.stageSaving,
      ImportStage.translating => l10n.translateWorking,
    };
