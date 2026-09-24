import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio/waveform.dart';
import '../../core/captions/caption_controller.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/media/media_converter.dart';
import '../../core/media/thumbnail_service.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/timeline/clip_trim.dart';
import '../../core/timeline/layer_drag.dart';
import '../../core/timeline/pinch_tracker.dart';
import '../../core/timeline/project_timeline.dart';
import '../../core/timeline/timeline_selection.dart';
import '../../core/timeline/timeline_sentences.dart';
import '../../core/timeline/timeline_zoom.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'editor_mode_controller.dart';
import 'layer_transcription_controller.dart';
import 'import_controller.dart' show ImportStage;
import 'media_player_controller.dart';
import 'project_screen.dart' show CaptionOverlay, HistoryControls;
import 'transcript_repository.dart';
import 'transcription_options.dart';
import 'video_settings_panel.dart';

/// Height of every track row.
///
/// **One height for all of them, deliberately.** Lanes sized to their own
/// content -- a tall filmstrip, a short waveform, a shorter layer bar -- made
/// the stack read as a ragged pile rather than as tracks, and gave the gutter
/// three different rhythms to line its controls up with. A single value also
/// puts a floor under the lane: the controls beside a track stack an eye above
/// a drag handle, and a lane shorter than those two icons plus their gap
/// overflows its own gutter.
const double _trackHeight = 56;

/// Height of the preview stage, in every state it can be in.
///
/// Loading, failed, video and audio all reserve this, so nothing below the
/// preview moves as a clip loads or as the selection changes.
const double _stageHeight = 300;

/// Width of the fixed playhead line.
const double _playheadWidth = 2;

/// Corner radius shared by everything that sits *on* a track -- clip tiles, the
/// "+" tile, layer rectangles. Deliberately tighter than the theme's card
/// radius and deliberately one constant: when these were specified separately
/// they drifted to 14, 6 and 4, and the row read as three unrelated shapes.
final BorderRadius _tileRadius = BorderRadius.circular(6);

/// Timeline mode: the clip/track view of the editing screen.
///
/// **The track is a true time axis.** A clip's width is exactly its duration
/// times the current scale — no minimum width, no gaps between tiles. An
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

  /// The stack, top to bottom, and which lanes are drawn.
  ///
  /// Neither is a property of the data -- hiding a track removes nothing and
  /// reordering moves no media -- so both live here rather than in the
  /// database.
  ///
  /// **Text starts above the video**, because that is where it ends up: tracks
  /// composite in stacking order and captions burn over the picture, so a
  /// transcribe lane drawn underneath would contradict what it does at export.
  List<_TrackId> _trackOrder = [
    _TrackId.layers,
    _TrackId.clips,
    _TrackId.audio,
  ];
  final Set<_TrackId> _hiddenTracks = {};

  void _moveTrack(_TrackId id, int delta) {
    final from = _trackOrder.indexOf(id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _trackOrder.length) return;

    setState(() {
      final next = [..._trackOrder];
      next.removeAt(from);
      next.insert(to, id);
      _trackOrder = next;
    });
  }


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

  /// Cuts everything selected, at the playhead.
  ///
  /// **Whatever is selected, not whatever is playing.** Clips are cut through
  /// `splitClip`; a transcribe layer is shortened to the playhead and a second
  /// one takes the rest of its range. Selecting a clip and the layer over it
  /// and splitting once cuts both at the same moment, which is the only way
  /// the two stay lined up through an edit.
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

    // **The preview follows the playhead, not the selection.** Selection now
    // means "what the tools act on" and can hold several things at once, so it
    // cannot also mean "what is on screen". Falls back to the first clip
    // before the playhead has moved at all.
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
                              // Adding the transcribe track while it is hidden has to
                              // reveal it, or the button would appear to do nothing.
                              onAddTrack: () =>
                                  setState(() => _hiddenTracks.remove(_TrackId.layers)),
                              onTrackUnavailable: _placeholder,
                              trackOrder: _trackOrder,
                              hiddenTracks: _hiddenTracks,
                              onToggleTrack: (id) => setState(() {
                                if (!_hiddenTracks.remove(id)) _hiddenTracks.add(id);
                              }),
                              onMoveTrack: _moveTrack,
                              selectedLayerIds:
                                  idsOfKind(selection, TimelineItemKind.layer),
                            ),
                          ),
                          _LayerStrip(
                            projectId: projectId,
                            selectedClipId: selectedId,
                            // The panel acts on one layer; the selection can hold
                            // several. The first is the one it speaks for.
                            selectedLayerId:
                                idsOfKind(selection, TimelineItemKind.layer).firstOrNull,
                            onCreated: (id) => ref
                                .read(timelineSelectionProvider(projectId).notifier)
                                .selectOnly((kind: TimelineItemKind.layer, id: id)),
                            onRemoved: () => ref
                                .read(timelineSelectionProvider(projectId).notifier)
                                .clear(),
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
                    onSplit: () => _splitSelection(playheadMs),
                    onPlaceholder: _placeholder,
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
        // Just the gear. The settings panel is also where the mode switches,
        // so an empty project without it would have no way into Script mode.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Align(
            alignment: Alignment.centerRight,
            child: VideoSettingsGear(projectId: projectId),
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

  /// **What the stage is keyed by, rather than [clipId].**
  ///
  /// Watching the per-clip player meant crossing a split changed the family
  /// key, and a fresh key starts in `loading` -- so the spinner flashed and
  /// the picture jumped at every cut, even though the decoder underneath was
  /// already warm and shared. Both halves of a split name the same file, so
  /// keying by the file means nothing changes at the boundary at all.
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
              // **One height, whatever is on it.** An audio clip used to get a
              // shorter stage, which read well in isolation and badly in
              // motion: `value.size` is zero until the first frame arrives, so
              // every video clip was briefly mistaken for audio and the whole
              // timeline below jumped as it loaded. A fixed stage costs some
              // empty ground under an audio clip and buys a screen that does
              // not move while you are looking at it.
              height: _stageHeight,
              width: double.infinity,
              child: hasVideo
                  // **The output's frame, not the clip's.** The stage used to
                  // letterbox whatever the clip was, which showed a landscape
                  // clip whole even when the project was 9:16 and the export
                  // would crop half of it away. It now draws the frame the
                  // render produces, in the project's shape, with the picture
                  // cropped the same way and the watermark where it will be.
                  ? ColoredBox(
                      // Ground around the frame in a different tone from the
                      // frame's own black, so its edges -- the edges of the
                      // exported video -- are visible.
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: ProjectStageCanvas(
                          projectId: widget.projectId,
                          sourceSize: value.size,
                          picture: VideoPlayer(widget.controller),
                          // The same overlay Script mode draws, from the same
                          // cues, inside the frame where it will be burned in
                          // -- but live widgets here, never rasterized
                          // (docs/engine-architecture.md).
                          overlay: transcriptId == null
                              ? null
                              : CaptionOverlay(
                                  transcriptId: transcriptId,
                                  positionMs: value.position.inMilliseconds,
                                ),
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
            // A `Stack` rather than spacers because centring by flex would
            // drift as the right-hand group changes width with undo/redo.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      // Fullscreen and history step aside while the video
                      // settings are open: the panel below is about the
                      // frame, and a stray undo there would take back an
                      // edit the user cannot see.
                      HiddenWhileSettingsOpen(
                        projectId: widget.projectId,
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen),
                          tooltip: l10n.timelineFullscreen,
                          onPressed: _openFullscreen,
                        ),
                      ),
                      const Spacer(),
                      VideoSettingsGear(projectId: widget.projectId),
                      // **Not gated on the selected clip having a
                      // transcript.** The history is the project's, so a
                      // project whose only action was a split had no way to
                      // undo it -- and undoing a transcription took the
                      // buttons away with the transcript it removed, stranding
                      // every earlier step behind a control that had vanished.
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
/// clips; one scroll offset and one scale means the tick above a
/// clip boundary is genuinely the time that boundary falls at.
class _TimelineTrack extends ConsumerStatefulWidget {
  const _TimelineTrack({
    required this.projectId,
    required this.clips,
    required this.selectedId,
    required this.onAddClip,
    required this.onAddTrack,
    required this.onTrackUnavailable,
    required this.trackOrder,
    required this.hiddenTracks,
    required this.onToggleTrack,
    required this.onMoveTrack,
    required this.selectedLayerIds,
  });

  final String projectId;
  final List<MediaClip> clips;
  final String? selectedId;
  final VoidCallback onAddClip;
  final VoidCallback onAddTrack;
  final ValueChanged<String> onTrackUnavailable;

  /// The stack, top to bottom. Every track the project can have appears here
  /// whether or not it currently has anything on it; what is actually drawn
  /// is decided per track.
  final List<_TrackId> trackOrder;

  /// Tracks whose content is not drawn. Their lane stays, because the eye
  /// that unhides them lives beside it.
  final Set<_TrackId> hiddenTracks;

  final ValueChanged<_TrackId> onToggleTrack;

  /// Moves a track by a number of places in the stack.
  final void Function(_TrackId id, int delta) onMoveTrack;

  final Set<String> selectedLayerIds;

  @override
  ConsumerState<_TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<_TimelineTrack> {
  final _scroll = ScrollController();

  /// How wide one second is drawn, now that it is the user's to change.
  ///
  /// **Still the one scale everything measures with.** The ruler's ticks, each
  /// clip's width, the waveform, the layers and the playhead's position all
  /// derive from this single value, so they cannot drift apart at any zoom.
  double _pps = defaultPixelsPerSecond;

  /// The scale when the current pinch began, and the project time that was
  /// under the playhead at that moment.
  ///
  /// Zoom is anchored to the playhead rather than to the pinch's midpoint:
  /// the playhead is where the user is working and where playback is, and an
  /// anchor that wandered with the fingers would move the thing being examined
  /// out from under the line examining it.
  double _pinchStartPps = defaultPixelsPerSecond;
  int _pinchAnchorMs = 0;

  /// The fingers on the track, and what scale they are asking for.
  ///
  /// **Fed from raw pointer events rather than a scale recogniser.** A
  /// `GestureDetector` here loses: the scroll view's own drag recogniser
  /// claims the gesture as soon as it passes touch slop, the scale recogniser
  /// is rejected by the arena, and its callbacks then never fire at all — the
  /// track just scrolls sideways under a pinch. `Listener` takes no part in
  /// the arena, so it sees every pointer whatever else has claimed them.
  ///
  /// The scroll is still switched off while two fingers are down, so a pinch
  /// does not also scrub.
  final _pinch = PinchTracker();

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

  /// Project time currently under the playhead.
  ///
  /// The offset *is* the playhead — content is padded by half the viewport —
  /// so this is the one conversion between pixels and time, used by both the
  /// scrub and the zoom anchor.
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

  /// Moves the playhead to where a sentence is spoken.
  ///
  /// Goes through the scroll rather than seeking the player directly: the
  /// offset *is* the playhead, so scrolling there drives the seek, the clip
  /// selection and the ruler together. Seeking the player on its own would
  /// leave the track showing somewhere else.
  void _seekToSentence(TimelineSentence sentence) {
    if (!_scroll.hasClients) return;

    final target = offsetForAnchor(
      anchorMs: sentence.projectStartMs,
      pixelsPerSecond: _pps,
      maxScrollExtent: _scroll.position.maxScrollExtent,
    );
    // A tap is the user choosing a moment, which is exactly what scrubbing
    // means -- so the seek this triggers is wanted, not an echo to suppress.
    _scrubbing = true;
    _scroll.jumpTo(target);
    _scrubbing = false;
  }

  /// Captures what the pinch now measures from.
  ///
  /// Called whenever the tracker changes which fingers it is measuring, not
  /// only when a pinch first begins: a pair that changed mid-gesture starts
  /// from a new distance, and leaving the old scale in place would make the
  /// zoom jump the moment the next finger moved.
  void _restartPinch() {
    _pinchStartPps = _pps;
    _pinchAnchorMs = _playheadMs;
    setState(() {});
  }

  void _applyZoom(double scale) {
    final next = scalePixelsPerSecond(_pinchStartPps, scale);
    if (next == _pps) return;

    setState(() => _pps = next);

    // Re-anchor after the layout that the new scale forces, or the offset
    // would be applied against the old content width and the playhead would
    // slide off the moment it was holding.
    //
    // This also cleans up after the scroll: the drag that was already under
    // way when the second finger landed may have moved the offset, and
    // re-asserting the anchor overrides it.
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

    // **The clip that is playing, not the one the playhead is over.** Both
    // halves of a split share one decoder, and its position is in media time.
    // Mapping that through the playhead's clip subtracts the wrong in-point,
    // so the timeline scrolled to a moment neither half is at -- which is the
    // timeline yanking itself away from under the user.
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

    final projectMs = _playheadMs;

    // Published whether this was a drag or playback following itself: the
    // preview and the toolbar both ask where the playhead is, and it is just
    // as true when the timeline moved on its own.
    ref
        .read(timelinePlayheadProvider(widget.projectId).notifier)
        .moveTo(projectMs);

    final at = timeline.clipAt(projectMs);
    if (at == null) return;

    // **Script mode reads this, so it has to keep moving.** Decoupling the
    // preview from the selection left nothing writing it, which pinned
    // `resolvedSelectedClipProvider` to the first clip -- so after a split the
    // second half's words were unreachable in Script mode entirely.
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
  ///
  /// Held here rather than written on every frame, for the same reason a layer
  /// drag is: sixty writes a second, none of them a decision the user has made
  /// yet. The database learns the result once, when the finger lifts.
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

  /// A clip's width *is* its duration -- the **trimmed** one. See the class doc
  /// on [TimelineBody] for why there is no minimum and no gap.
  ///
  /// Measuring `durationMs` here while the ruler measured the trim is exactly
  /// the drift `ProjectTimeline` exists to prevent: the tiles and the times
  /// above them would disagree for every trimmed clip.
  double _widthOf(MediaClip clip) {
    final window = _windowOf(clip);
    return (window.endMs - window.startMs) / 1000 * _pps;
  }

  /// The clip on the other side of this edge, when the two are one cut.
  ///
  /// Only ever the immediate neighbour, and only when it plays the same file
  /// and meets this one exactly -- which is what a split leaves behind.
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
      // **Rolling, not resizing.** Extending one half of a split back over the
      // other made the project longer than the file it came from and played
      // the overlap twice. Moving the cut gives one side exactly what the
      // other gives up, so the pair always covers the same span.
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
          _ClipTile(
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
            onTap: () => ref
                .read(timelineSelectionProvider(widget.projectId).notifier)
                .toggle((kind: TimelineItemKind.clip, id: clip.id)),
            onLongPress: () => _showActions(clip, index),
            onTrimStart: (edge) => _startTrim(clip, edge),
            onTrimUpdate: (delta) => _updateTrim(clip, delta),
            onTrimEnd: () => _endTrim(clip),
          ),
        _AddClipTile(
          busy: ref.watch(addClipControllerProvider(widget.projectId))
              is AddClipCopying,
          onTap: widget.onAddClip,
        ),
      ],
    );
  }

  /// The audio track: each clip's own audio, drawn as amplitude bars.
  ///
  /// **A track in its own right, not a strip glued under the video.** It hides
  /// and reorders on its own, which is what lets the picture be moved or put
  /// away without taking the sound with it.
  ///
  /// It is still *derived* from the clips rather than independent content --
  /// there is no way yet to put a separate audio file on it -- so it stays
  /// aligned with the video above by construction: same clips, same widths,
  /// same axis.
  Widget _audioRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, clip) in widget.clips.indexed)
          _WaveLane(
            clipId: clip.id,
            width: _widthOf(clip),
            first: index == 0,
          ),
      ],
    );
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
      builder: (context) => AppDialog(
        title: l10n.clipRemoveTitle,
        content: Text(l10n.clipRemoveMessage),
        actions: [
          AppDialogAction(
            label: l10n.clipRemove,
            emphasis: AppDialogEmphasis.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          AppDialogAction(
            label: l10n.editCancel,
            onPressed: () => Navigator.of(context).pop(false),
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
    final theme = Theme.of(context);
    final timeline = ref.watch(projectTimelineProvider(widget.projectId));
    final layers =
        ref.watch(projectLayersProvider(widget.projectId)).value ?? const [];

    // Follow playback: the player reports a position inside the selected clip,
    // which the timeline turns into a position on the shared axis. Watched
    // here only to learn *which* controller to listen to -- the position
    // itself arrives through the listener, not through a rebuild.
    final selected = widget.selectedId;
    final selectedClip = selected == null
        ? null
        : widget.clips.where((clip) => clip.id == selected).firstOrNull;
    _follow(
      selected == null ? null : ref.watch(mediaPlayerProvider(selected)).value,
      selectedClip?.mediaPath,
    );

    final trackWidth = timeline.totalMs / 1000 * _pps;
    final tracks = _visibleTracks(layers, trackWidth, timeline);

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
          // **Wraps the whole track section, not just the scrolling strip.**
          // A pinch is only a pinch if both fingers are seen, and a listener
          // sized to the strip alone misses any gesture where one finger falls
          // above or below it.
          //
          // Translucent so it does not depend on a child hit-testing at the
          // point a finger lands: the gaps between tracks are not filled by
          // anything, and a finger in one of them still counts.
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
                    // The gutter sits inside this widget rather than beside
                    // it, which is what lets each control line up with the
                    // lane it belongs to: both are laid out from the same list
                    // of track heights, so they cannot drift apart.
                    _TrackGutter(
                      tracks: tracks,
                      topInset: _rulerHeight + AppSpacing.xs,
                      onToggleVisible: widget.onToggleTrack,
                      onMove: widget.onMoveTrack,
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          NotificationListener<ScrollNotification>(
                            // Only a drag counts as scrubbing. `jumpTo` while
                            // following playback emits no start/end
                            // notification, so the flag stays false and the
                            // seek loop never closes.
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
                              physics: _pinch.isPinching
                                  ? const NeverScrollableScrollPhysics()
                                  : null,
                              padding: EdgeInsets.symmetric(horizontal: lead),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TimeRuler(
                                    totalMs: timeline.totalMs,
                                    width: trackWidth,
                                    pixelsPerSecond: _pps,
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
                                        // than collapsing it. Collapsing would
                                        // take the eye that unhides it away
                                        // along with the content.
                                        child: track.visible
                                            ? track.build()
                                            : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // Drawn over the tracks rather than scrolling with
                          // them: it marks a place on the screen, not a place
                          // in the media. Runs the full height of the stack so
                          // a layer and the clip beneath it are cut by the same
                          // line -- which is the whole claim that they share
                          // one axis.
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

  /// The lanes to draw, in the order the user has put them.
  ///
  /// **A track with nothing on it is not a track.** The transcribe lane
  /// appears once a layer exists and not before: an empty lane is a rectangle
  /// that explains nothing, and "Add layer" below already says where layers
  /// come from.
  List<_TrackSpec> _visibleTracks(
    List<TranscribeLayer> layers,
    double trackWidth,
    ProjectTimeline timeline,
  ) {
    final specs = <_TrackSpec>[];

    for (final id in widget.trackOrder) {
      switch (id) {
        case _TrackId.clips:
          specs.add(_TrackSpec(
            id: id,
            height: _trackHeight,
            visible: !widget.hiddenTracks.contains(id),
            build: _clipRow,
          ));
        case _TrackId.audio:
          // No clips, no audio. An empty lane is a rectangle that explains
          // nothing -- the same reason the transcribe lane waits for a layer.
          if (widget.clips.isEmpty) continue;
          specs.add(_TrackSpec(
            id: id,
            height: _trackHeight,
            visible: !widget.hiddenTracks.contains(id),
            build: _audioRow,
          ));
        case _TrackId.layers:
          if (layers.isEmpty) continue;
          specs.add(_TrackSpec(
            id: id,
            height: _trackHeight,
            visible: !widget.hiddenTracks.contains(id),
            build: () => _LayerTrack(
              projectId: widget.projectId,
              width: trackWidth,
              totalMs: timeline.totalMs,
              pixelsPerSecond: _pps,
              selectedLayerIds: widget.selectedLayerIds,
              playheadMs: _playheadMs,
              onSeek: _seekToSentence,
            ),
          ));
      }
    }

    return specs;
  }
}

enum _ClipAction { earlier, later, remove }

/// The tracks a project can stack.
///
/// An enum rather than free-form ids because the set is closed and the order
/// is persisted view state: a typo'd string would silently drop a track from
/// the timeline rather than failing to compile.
enum _TrackId { layers, clips, audio }

/// One lane, as both the gutter and the track column need to see it.
///
/// Height is declared here rather than measured, because the gutter has to lay
/// its controls out to the same rhythm without being able to see the lanes.
/// One list, read twice, is what keeps a control beside the track it operates.
class _TrackSpec {
  const _TrackSpec({
    required this.id,
    required this.height,
    required this.visible,
    required this.build,
  });

  final _TrackId id;
  final double height;
  final bool visible;
  final Widget Function() build;
}

/// Width of the controls column beside the tracks.
///
/// Every point this takes is a point the time axis does not get, and on a
/// phone the axis is the scarce thing.
const double _gutterWidth = 32;

/// Roughly how wide one filmstrip frame is drawn.
///
/// The strip divides its width by this to decide how many frames it has room
/// for, then lays them out with `Expanded`, so each lands near this width
/// without the row ever overflowing by a partial frame.
const double _filmstripFrameWidth = 48;

/// How many frames a clip [width] points wide has room for.
int _filmstripSlots(double width) =>
    width <= 0 ? 1 : math.max(1, (width / _filmstripFrameWidth).round());

/// How long a freshly drawn layer covers, before the user resizes it.
///
/// Never zero: a zero-width layer would be invisible and untappable, so there
/// would be no way to fix it.
const int _defaultLayerMs = 10000;

/// Adding a layer, and acting on the selected one.
///
/// **Transcribing what a layer spans is Stage C** — the audio slicing it needs
/// does not exist yet — so the action here is deliberately absent rather than
/// present and inert. A button that looked ready and did nothing would be
/// worse than no button.
class _LayerStrip extends ConsumerWidget {
  const _LayerStrip({
    required this.projectId,
    required this.selectedClipId,
    required this.selectedLayerId,
    required this.onCreated,
    required this.onRemoved,
  });

  final String projectId;
  final String? selectedClipId;

  /// The layer the panel speaks for: the first of whatever is selected.
  final String? selectedLayerId;

  final ValueChanged<String> onCreated;
  final VoidCallback onRemoved;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(transcriptRepositoryProvider);
    final timeline = ref.read(projectTimelineProvider(projectId));
    final layers = ref.read(projectLayersProvider(projectId)).value ?? const [];

    // **Spans the selected clip when it can.** Transcribing a whole clip is
    // the common case by a wide margin, and a layer that had to be resized to
    // reach the end of one would make the ordinary thing the fiddly thing.
    final placement =
        selectedClipId == null ? null : timeline.placementOf(selectedClipId!);
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
    final end = timeline.totalMs > 0
        ? math.min(start + wanted, timeline.totalMs)
        : start + wanted;
    if (timeline.totalMs > 0 && start >= timeline.totalMs) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.layerNoRoom)));
      return;
    }

    final id = await repository.addLayer(
      projectId: projectId,
      startMs: start,
      endMs: end,
    );
    if (id != null) onCreated(id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = selectedLayerId;

    // The engine's state for the selected layer. Watched rather than read so
    // the strip follows a run that is already under way -- returning to the
    // screen mid-transcription must not look idle.
    final status = selected == null
        ? const LayerTranscriptionIdle()
        : ref.watch(layerTranscriptionControllerProvider(selected));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: switch (status) {
        LayerTranscriptionRunning(:final stage, :final percent) => Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  stageLabel(l10n, stage, percent),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        LayerTranscriptionFailed() => Row(
            children: [
              Expanded(
                child: Text(
                  l10n.clipTranscribeFailed,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(layerTranscriptionControllerProvider(selected!)
                        .notifier)
                    .transcribe(),
                child: Text(l10n.retryAction),
              ),
            ],
          ),
        _ => Row(
            children: [
              Expanded(
                child: Text(
                  selected == null ? l10n.layerHint : l10n.layerSelected,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (selected != null) ...[
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(transcriptRepositoryProvider)
                        .removeLayer(selected);
                    onRemoved();
                  },
                  child: Text(l10n.layerRemove),
                ),
                FilledButton(
                  onPressed: () => _transcribe(context, ref, selected),
                  child: Text(l10n.clipTranscribe),
                ),
              ] else
                TextButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.layerAdd),
                ),
            ],
          ),
      },
    );
  }

  /// Runs the layer, confirming first if it would replace an earlier run.
  Future<void> _transcribe(
    BuildContext context,
    WidgetRef ref,
    String layerId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller =
        ref.read(layerTranscriptionControllerProvider(layerId).notifier);

    final existing =
        await ref.read(transcriptRepositoryProvider).transcriptsForLayer(layerId);
    if (!context.mounted) return;

    // The options come first, every time -- this is the moment they apply to.
    //
    // **Re-running is offered rather than refused**, but never silently: it
    // discards word corrections and speaker names, which are the parts the
    // user typed rather than the parts the engine produced. That warning rides
    // inside this dialog instead of being a second one, because two modals in
    // a row for a single decision is one too many.
    final confirmed = await showTranscriptionOptions(
      context,
      warning: existing.isEmpty ? null : l10n.layerRerunBody,
    );
    if (!confirmed) return;

    if (existing.isEmpty) {
      await controller.transcribe();
    } else {
      await controller.rerun();
    }
  }
}

/// One clip's audio, drawn as vertical bars on the same axis as the clip.
///
/// The readings are computed on first sight and stored, so this is flat for a
/// moment after a clip is added and then permanently drawn. A clip with no
/// decodable audio stays flat, which is the truth about it.
class _WaveLane extends ConsumerWidget {
  const _WaveLane({
    required this.clipId,
    required this.width,
    required this.first,
  });

  final String clipId;
  final double width;

  /// Whether this is the leftmost lane, which has nothing to divide it from.
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final peaks = ref.watch(clipWaveformProvider(clipId)).value ?? Uint8List(0);

    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: _tileRadius,
        color: theme.colorScheme.surfaceContainerHighest,
        // No outline. A box drawn round every lane turned the stack into a
        // grid of frames, and the frames read louder than the content inside
        // them. Where one clip meets the next, a single divider does the whole
        // job the outline was there for.
        border: first
            ? null
            : Border(left: BorderSide(color: surface.outline)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _WavePainter(
          peaks: peaks,
          // Not the accent. A waveform is a dense texture across the whole
          // lane, and spending the theme's one call-to-action colour on it
          // both drowns out the things that are actions and, in the light
          // theme, puts yellow on cream where it barely reads. Chrome stays
          // quieter than the content -- the same rule that keeps the app's
          // speaker colours legible.
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
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

/// The transcribe track: one rectangle per layer, laid out on the same axis
/// as the clips above it.
///
/// A layer is a *request* — it exists before anything has run, and running it
/// is what produces words. Its rectangle is positioned from project-timeline
/// milliseconds, which is only meaningful because the clip row is a true time
/// axis; if clips were still clamped and spaced, a layer could not sit over
/// the media it describes.
/// Width of the grab area at each end of a selected layer.
///
/// **Fixed, and straddling the edge rather than carved out of the bar.** A
/// handle sized as a fraction of the layer would be untouchable on a short one
/// and absurd on a long one; taking it out of the bar's own width would leave
/// a short layer with no middle to drag. Half in and half out costs the bar
/// [_layerHandleWidth] / 2 of its middle and keeps the target the same size at
/// every zoom and every duration.
const double _layerHandleWidth = 40;

/// The visible grip inside that grab area.
///
/// Wide enough to hold its arrow. The first version was 10pt with a 12pt icon
/// inside it, so the glyph fought its own container and looked like a mistake.
const double _layerGripWidth = 18;

/// The outward arrow on a grip.
///
/// Sized to sit inside [_layerGripWidth] rather than fill it, so the grip
/// reads as a surface with a mark on it instead of a box around an icon.
const double _gripArrowSize = 14;

/// The grip's corner rounding, applied to its **inner** edge only.
///
/// Square where it meets the end of the clip and rounded where it meets the
/// picture, so it reads as the edge of the tile thickening into something to
/// hold -- rather than as a separate chip sitting on top of it.
BorderRadius _gripRadius({required bool atStart}) => BorderRadius.horizontal(
      left: Radius.circular(atStart ? 0 : 4),
      right: Radius.circular(atStart ? 4 : 0),
    );

/// The transcribe track: one band per layer, with the sentences it produced
/// drawn inside it.
///
/// A selected layer grows handles at both ends: drag an end to resize, the
/// middle to move. Both are clamped against the neighbouring layers every
/// frame rather than on release, and both snap to clip seams and to the
/// playhead -- see `layer_drag.dart`, where those rules live so they can be
/// tested without a gesture.
class _LayerTrack extends ConsumerStatefulWidget {
  const _LayerTrack({
    required this.projectId,
    required this.width,
    required this.totalMs,
    required this.pixelsPerSecond,
    required this.selectedLayerIds,
    required this.playheadMs,
    required this.onSeek,
  });

  final String projectId;
  final double width;
  final int totalMs;
  final double pixelsPerSecond;

  /// Every selected layer, because the tools act on all of them at once.
  final Set<String> selectedLayerIds;

  /// Where the playhead is, so an edge can snap to it.
  final int playheadMs;

  /// Moves the playhead to a sentence, the way tapping a word does in Script
  /// mode -- the timeline is a second way into the same transcript, so it
  /// should answer a tap the same way.
  final ValueChanged<TimelineSentence> onSeek;

  @override
  ConsumerState<_LayerTrack> createState() => _LayerTrackState();
}

class _LayerTrackState extends ConsumerState<_LayerTrack> {
  /// Where the layer being dragged currently sits.
  ///
  /// Held here rather than written to the database on every frame: a drag is
  /// sixty writes a second, each one running the overlap check, and none of
  /// them is a decision the user has made yet. The database learns the result
  /// once, when the finger lifts.
  LayerBounds? _dragged;
  String? _draggingId;
  LayerGrip _grip = LayerGrip.whole;
  double _dragPixels = 0;

  /// Adds or removes a layer from the selection the tools act on.
  void _toggle(String layerId) => ref
      .read(timelineSelectionProvider(widget.projectId).notifier)
      .toggle((kind: TimelineItemKind.layer, id: layerId));

  void _startDrag(TranscribeLayer layer, LayerGrip grip) {
    setState(() {
      _draggingId = layer.id;
      _grip = grip;
      _dragPixels = 0;
      _dragged = (startMs: layer.startMs, endMs: layer.endMs);
    });
  }

  void _updateDrag(
    TranscribeLayer layer,
    List<TranscribeLayer> layers,
    double deltaPixels,
  ) {
    if (_draggingId != layer.id) return;

    _dragPixels += deltaPixels;
    final deltaMs =
        (_dragPixels / widget.pixelsPerSecond * 1000).round();

    final bounds = layerBoundsWithin(
      others: [
        for (final other in layers)
          if (other.id != layer.id)
            (startMs: other.startMs, endMs: other.endMs),
      ],
      layer: (startMs: layer.startMs, endMs: layer.endMs),
      totalMs: widget.totalMs,
    );

    setState(() {
      _dragged = applyLayerDrag(
        layer: (startMs: layer.startMs, endMs: layer.endMs),
        grip: _grip,
        deltaMs: deltaMs,
        lowerBoundMs: bounds.lowerMs,
        upperBoundMs: bounds.upperMs,
        pixelsPerSecond: widget.pixelsPerSecond,
        snapTargets: layerSnapTargets(
          timeline: ref.read(projectTimelineProvider(widget.projectId)),
          playheadMs: widget.playheadMs,
        ),
      );
    });
  }

  Future<void> _endDrag(TranscribeLayer layer) async {
    final result = _dragged;
    setState(() {
      _dragged = null;
      _draggingId = null;
      _dragPixels = 0;
    });

    if (result == null) return;
    if (result.startMs == layer.startMs && result.endMs == layer.endMs) return;

    await ref.read(transcriptRepositoryProvider).moveLayer(
          layerId: layer.id,
          startMs: result.startMs,
          endMs: result.endMs,
        );
  }

  /// Grab width for a bar [barWidth] points wide.
  double _handleWidth(double barWidth) =>
      math.max(8, math.min(_layerHandleWidth, barWidth / 2));

  /// The layer covering [projectMs], if any.
  String? _layerAt(List<TranscribeLayer> layers, int projectMs) {
    for (final layer in layers) {
      if (projectMs >= layer.startMs && projectMs < layer.endMs) {
        return layer.id;
      }
    }
    return null;
  }

  /// Where a layer is drawn, which is its dragged position while one is under
  /// way and its stored position otherwise.
  LayerBounds _boundsOf(TranscribeLayer layer) =>
      _draggingId == layer.id && _dragged != null
          ? _dragged!
          : (startMs: layer.startMs, endMs: layer.endMs);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final layers =
        ref.watch(projectLayersProvider(widget.projectId)).value ?? const [];
    final sentences = ref.watch(projectSentencesProvider(widget.projectId));

    double x(int ms) => ms / 1000 * widget.pixelsPerSecond;

    return SizedBox(
      height: _trackHeight,
      width: widget.width <= 0 ? 1 : widget.width,
      // Handles reach outside the bar they belong to, so they must not be
      // clipped away by the lane's own bounds.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The empty lane, so its extent reads even with no layers on it.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: _tileRadius,
              ),
            ),
          ),
          // **The layer is the band, the sentences are what is on it.** The
          // band says which stretch was asked for; the sentences say what came
          // back. Drawing only the sentences would lose the difference between
          // a stretch nobody has transcribed and one that was transcribed and
          // is silent -- and the obvious response to that gap is to transcribe
          // the same audio a second time.
          for (final layer in layers)
            if (_boundsOf(layer) case final bounds)
              Positioned(
                left: x(bounds.startMs),
                width: x(bounds.endMs - bounds.startMs),
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () => _toggle(layer.id),
                  onHorizontalDragStart: widget.selectedLayerIds.contains(layer.id)
                      ? (_) => _startDrag(layer, LayerGrip.whole)
                      : null,
                  onHorizontalDragUpdate: widget.selectedLayerIds.contains(layer.id)
                      ? (details) =>
                          _updateDrag(layer, layers, details.delta.dx)
                      : null,
                  onHorizontalDragEnd: widget.selectedLayerIds.contains(layer.id)
                      ? (_) => _endDrag(layer)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.selectedLayerIds.contains(layer.id)
                          ? theme.colorScheme.primary.withValues(alpha: 0.30)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: _tileRadius,
                      // Outlined only when selected, where the border is
                      // carrying a state rather than drawing a frame.
                      border: widget.selectedLayerIds.contains(layer.id)
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: surface.borderWidth,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          for (final (index, sentence) in sentences.indexed)
            Positioned(
              left: x(sentence.projectStartMs),
              // Never narrower than a hairline: a very short sentence at a
              // wide zoom-out would otherwise vanish entirely, and an absent
              // box reads as untranscribed rather than as brief.
              width: math.max(
                2,
                x(sentence.projectEndMs - sentence.projectStartMs),
              ),
              top: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
              child: _SentenceBox(
                sentence: sentence,
                // Adjacency is measured in pixels rather than milliseconds so
                // it answers to the zoom: sentences a breath apart read as one
                // run when the axis is compressed and separate once it is
                // stretched far enough to show the pause between them.
                joinedLeft: index > 0 &&
                    x(sentence.projectStartMs) -
                            x(sentences[index - 1].projectEndMs) <
                        _sentenceJoinGap,
                joinedRight: index < sentences.length - 1 &&
                    x(sentences[index + 1].projectStartMs) -
                            x(sentence.projectEndMs) <
                        _sentenceJoinGap,
                // **Resolved from where the finger landed, not from where
                // the sentence begins.** Sentences are derived from word rows
                // and pay no attention to layer edges, so one straddling a cut
                // starts in the layer before the one being tapped -- which
                // selected the neighbour instead, and read as the two layers
                // overlapping.
                onTapAtOffset: (dx) {
                  final tappedMs = sentence.projectStartMs +
                      (dx / widget.pixelsPerSecond * 1000).round();
                  final layerId = _layerAt(layers, tappedMs);
                  if (layerId != null) _toggle(layerId);
                  widget.onSeek(sentence);
                },
              ),
            ),
          // Drawn last so they sit over the sentences: a handle buried under a
          // sentence box would be unreachable on a fully transcribed layer.
          for (final layer in layers)
            if (widget.selectedLayerIds.contains(layer.id))
              if (_boundsOf(layer) case final bounds) ...[
                // **Inside the bar, not straddling its edge.** A handle drawn
                // half outside looks roomier and is not: Flutter does not
                // hit-test the part of a child that falls outside its parent,
                // so the outer half was decoration and every grab landed on
                // the band behind it instead.
                //
                // Narrow bars split evenly rather than letting the two handles
                // overlap, so both ends stay reachable; a bar with no middle
                // left cannot be dragged as a whole, which on something that
                // small is the less useful of the two gestures anyway.
                if (_handleWidth(x(bounds.endMs) - x(bounds.startMs))
                    case final handleWidth) ...[
                  for (final (grip, left) in [
                    (LayerGrip.start, x(bounds.startMs)),
                    (LayerGrip.end, x(bounds.endMs) - handleWidth),
                  ])
                    Positioned(
                      left: left,
                      width: handleWidth,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        // Opaque so the whole grab area answers, not only the
                        // few points the grip itself is drawn on.
                        behavior: HitTestBehavior.opaque,
                        // Answers taps too: on a short layer the two handles
                        // cover the whole band, and a handle that only
                        // listened for drags made it impossible to deselect.
                        onTap: () => _toggle(layer.id),
                        onHorizontalDragStart: (_) => _startDrag(layer, grip),
                        onHorizontalDragUpdate: (details) =>
                            _updateDrag(layer, layers, details.delta.dx),
                        onHorizontalDragEnd: (_) => _endDrag(layer),
                        child: Align(
                          // The grip sits on the edge it moves, while the area
                          // that answers a thumb reaches inward from it.
                          alignment: grip == LayerGrip.start
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            width: _layerGripWidth,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: _gripRadius(
                                atStart: grip == LayerGrip.start,
                              ),
                            ),
                            child: Icon(
                              grip == LayerGrip.start
                                  ? Icons.chevron_left
                                  : Icons.chevron_right,
                              size: _gripArrowSize,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
        ],
      ),
    );
  }
}

/// The controls column beside the tracks: one row per lane.
///
/// **Laid out from the same track list the lanes are**, with the same heights
/// and the same gaps, so each control sits beside the track it operates. An
/// earlier version had a single eye and a single reorder button for the whole
/// stack, which meant neither said which track it meant.
class _TrackGutter extends StatelessWidget {
  const _TrackGutter({
    required this.tracks,
    required this.topInset,
    required this.onToggleVisible,
    required this.onMove,
  });

  final List<_TrackSpec> tracks;

  /// Height of the ruler above the first lane, so the first row lines up.
  final double topInset;

  final ValueChanged<_TrackId> onToggleVisible;

  /// Moves a track by [delta] places in the stack.
  final void Function(_TrackId id, int delta) onMove;

  @override
  Widget build(BuildContext context) {
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
                child: _TrackControls(
                  track: track,
                  canMoveUp: index > 0,
                  canMoveDown: index < tracks.length - 1,
                  onToggleVisible: () => onToggleVisible(track.id),
                  onMove: (delta) => onMove(track.id, delta),
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
  ///
  /// Reset on every swap rather than compared against the original position,
  /// so a long drag steps through several tracks instead of jumping the whole
  /// distance at once.
  double _dragged = 0;

  /// How far the handle travels before the track moves a place.
  ///
  /// Deliberately not the track's own height: a 34pt lane would swap almost
  /// immediately, and a 92pt one would feel stuck. A fixed distance makes
  /// every track answer the drag at the same rate.
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
          child: Tooltip(
            message: visible ? l10n.trackHide : l10n.trackShow,
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
            child: Tooltip(
              message: l10n.trackReorder,
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

/// How close two sentences must be drawn before they read as one run.
const double _sentenceJoinGap = 3;

/// One sentence, drawn where it is spoken.
///
/// **Colour, not text.** The text was tried here and taken out: at any zoom
/// that fits a useful stretch of the timeline on screen, a sentence is a few
/// dozen points wide, and a few clipped characters is noise rather than
/// information. The full sentence is a tap away in the preview and in Script
/// mode, both of which have room for it.
///
/// What the box does carry is **who was speaking and when**, which is legible
/// at any width and is the app's signature signal — the reason the rest of the
/// timeline stays grey.
///
/// Neighbours merge: a box is rounded only on a side with nothing against it,
/// and takes a divider on a side where it meets another. A run of speech then
/// reads as one bar cut into sentences rather than as a row of separate pills
/// with gaps that mean nothing.
class _SentenceBox extends StatelessWidget {
  const _SentenceBox({
    required this.sentence,
    required this.joinedLeft,
    required this.joinedRight,
    required this.onTapAtOffset,
  });

  final TimelineSentence sentence;
  final bool joinedLeft;
  final bool joinedRight;

  /// Reports **where** along the box the tap landed, not merely that it did.
  ///
  /// A sentence can span more than one layer, so the caller needs the position
  /// to know which one was actually pressed.
  final ValueChanged<double> onTapAtOffset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = SpeakerPalette.colorFor(
      sentence.speaker,
      fallback: theme.colorScheme.secondary,
    );

    const corner = Radius.circular(6);

    return GestureDetector(
      onTapUp: (details) => onTapAtOffset(details.localPosition.dx),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.horizontal(
            left: joinedLeft ? Radius.zero : corner,
            right: joinedRight ? Radius.zero : corner,
          ),
          // Drawn on the left edge only, so two neighbours share one line
          // rather than each drawing its own and doubling its weight.
          border: joinedLeft
              ? Border(
                  left: BorderSide(
                    color: theme.colorScheme.surface.withValues(alpha: 0.75),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
/// Height the ruler occupies: ticks plus the labels beneath them.
const double _rulerHeight = 28;

/// A measuring rule: a long tick for each labelled value, short ticks between.
///
/// **The label is centred on its tick**, which an earlier pass got wrong by
/// positioning text from its left edge — the glyphs then sat beside the moment
/// they named rather than on it, and at a glance the whole ruler read as
/// shifted.
///
/// The labelled interval widens until labels cannot collide, so the ruler
/// needs no special handling at any zoom — it relabels itself as the scale
/// changes. Minor ticks subdivide that interval into five.
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
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surface = context.surface;

    final duration = Duration(milliseconds: window.endMs - window.startMs);

    // **Frames are counted from the drawn width, not from the duration.**
    // Counting by duration meant a fixed number of frames stretched across
    // whatever width the clip happened to occupy, so zooming in magnified
    // three pictures instead of revealing more of the clip — the strip got
    // bigger and said no more than before.
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
                  // The border is drawn *inside* the tile's width rather than as a gap
                  // beside it. A gap would add pixels the timeline does not have time
                  // for, and every clip boundary after the first would sit later than
                  // the moment it represents.
                  decoration: BoxDecoration(
                    borderRadius: _tileRadius,
                    color: theme.colorScheme.surfaceContainerHighest,
                    // The selected clip takes the theme's own call to action, the same
                    // signal `_Segment` uses for a chosen option. An unselected clip
                    // gets no frame -- only a divider where it meets the clip before
                    // it, which is the one thing the outline was needed for. Drawn
                    // inside the tile's width rather than as a gap beside it: a gap
                    // would add pixels the timeline does not have, and every clip
                    // boundary after the first would sit later than the moment it
                    // represents.
                    border: selected
                        ? Border.all(
                            color: theme.colorScheme.primary,
                            width: surface.borderWidth,
                          )
                        : first
                            ? null
                            : Border(left: BorderSide(color: surface.outline)),
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
                                  // The frame nearest this slot's moment. Once the
                                  // strip has more slots than there are extracted
                                  // frames, neighbouring slots repeat a picture rather
                                  // than stretching one across the gap.
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
            // **Handles sit inside the tile, never straddling its edge.**
            // Flutter does not hit-test the part of a child that falls outside
            // its parent, so an overhanging grab area is decoration and every
            // drag lands on whatever is behind it.
            if (selected)
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
                    // **Opaque, so it must answer taps as well as drags.** On
                    // a tile narrower than twice a handle the two cover it
                    // completely, and without this the item could be selected
                    // and then never deselected -- every tap landed on a
                    // handle that only listened for drags.
                    onTap: onTap,
                    onHorizontalDragStart: (_) => onTrimStart(edge),
                    onHorizontalDragUpdate: (details) =>
                        onTrimUpdate(details.delta.dx),
                    onHorizontalDragEnd: (_) => onTrimEnd(),
                    // **Drawn on the edge, grabbed from inside it.** The grip
                    // sits flush to the end it moves so it reads as the edge
                    // itself, while the area that answers a thumb reaches
                    // inward from there -- the two do not have to be the same
                    // rectangle, and only one of them can leave the tile.
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
///
/// **Only [transcribe] can be added today.** The others each need their
/// content composited into the exported video, and nothing in the app does
/// that yet — captions are still structured data right up to export, and there
/// is no compositor to burn a second layer in. They are listed rather than
/// hidden because the stack is the thing being chosen from, and a menu that
/// showed one entry would misdescribe what a track is; each says what it is
/// waiting on rather than simply refusing.
enum _TrackKind { transcribe, audio, text, image, video }

/// Adds a track to the stack.
///
/// Sits outside the horizontal scroll: this adds a track, it is not one, so it
/// stays put while the timeline moves beneath the playhead.
class _AddTrackRow extends StatelessWidget {
  const _AddTrackRow({required this.onAdd, required this.onUnavailable});

  final VoidCallback onAdd;
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
      (_TrackKind.text, Icons.title, l10n.trackKindText, ''),
      (_TrackKind.image, Icons.image_outlined, l10n.trackKindImage, ''),
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
                enabled: kind == _TrackKind.transcribe,
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(
                  kind == _TrackKind.transcribe
                      ? detail
                      : l10n.trackKindUnavailable,
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
        decoration: BoxDecoration(
          borderRadius: surface.borderRadius,
          border:
              Border.all(color: surface.outline, width: surface.borderWidth),
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
    required this.onSplit,
    required this.onPlaceholder,
  });

  final bool showCaptions;
  final VoidCallback onToggleCaptions;

  final VoidCallback onSplit;
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
                  label: l10n.timelineToolSplit,
                  onTap: onSplit,
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

/// One pipeline stage as a sentence, with its percentage where there is one.
///
/// The stage vocabulary is shared with import rather than duplicated per
/// caller, so a run started from the library and a run started from a layer
/// describe themselves in the same words.
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
    };
