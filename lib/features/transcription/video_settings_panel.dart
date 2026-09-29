import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/monetization/monetization.dart';
import '../../core/theme/app_controls.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/video/export_options.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'editor_mode_controller.dart';
import 'media_player_controller.dart';
import 'overlap_audio.dart';
import 'transcript_repository.dart';
import '../../core/timeline/audio_window.dart';
import '../../core/timeline/clip_trim.dart';
import 'stage_editor.dart';
import 'video_canvas.dart';
import 'video_settings.dart';

part 'video_settings_panel.g.dart';

/// The settings the panel can show. The mode switch is not one of them: it
/// acts rather than shows, so it never becomes the selected item.
enum VideoSettingsItem { aspect, resolution, watermark }

typedef VideoSettingsPanelState = ({bool open, VideoSettingsItem item});

/// Whether a project's video settings are open, and on which item.
@riverpod
class VideoSettingsPanelController extends _$VideoSettingsPanelController {
  @override
  VideoSettingsPanelState build(String projectId) =>
      (open: false, item: VideoSettingsItem.aspect);

  void toggle() => state = (open: !state.open, item: state.item);

  void close() {
    if (state.open) state = (open: false, item: state.item);
  }

  void show(VideoSettingsItem item) => state = (open: true, item: item);
}

/// How long every movement in the panel takes.
const Duration _motion = Duration(milliseconds: 220);

/// Zero when the user has asked for no animation (docs/design-direction.md
/// §6): with motion off, everything is simply there.
Duration _motionFor(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : _motion;

/// The gear that opens the panel, in both modes' transport rows.
class VideoSettingsGear extends ConsumerWidget {
  const VideoSettingsGear({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final open =
        ref.watch(videoSettingsPanelControllerProvider(projectId)).open;

    return IconButton(
      tooltip: open ? l10n.videoSettingsClose : l10n.videoSettingsOpen,
      onPressed: () => ref
          .read(videoSettingsPanelControllerProvider(projectId).notifier)
          .toggle(),
      icon: AnimatedRotation(
        turns: open ? 0.25 : 0,
        duration: _motionFor(context),
        curve: Curves.easeOutCubic,
        child: AppIcon(
          AppGlyph.gear,
          color: open ? theme.colorScheme.secondary : null,
        ),
      ),
    );
  }
}

/// Fades a control out while the panel is open, and back in after.
class HiddenWhileSettingsOpen extends ConsumerWidget {
  const HiddenWhileSettingsOpen({
    super.key,
    required this.projectId,
    required this.child,
  });

  final String projectId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open =
        ref.watch(videoSettingsPanelControllerProvider(projectId)).open;

    return IgnorePointer(
      ignoring: open,
      child: AnimatedOpacity(
        opacity: open ? 0 : 1,
        duration: _motionFor(context),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// The project's video settings, laid over whatever sits below the stage.
class VideoSettingsPanel extends ConsumerStatefulWidget {
  const VideoSettingsPanel({
    super.key,
    required this.projectId,
    required this.mode,
  });

  final String projectId;

  /// The mode on screen. The panel's first item switches to the other one.
  final EditorMode mode;

  @override
  ConsumerState<VideoSettingsPanel> createState() => _VideoSettingsPanelState();
}

class _VideoSettingsPanelState extends ConsumerState<VideoSettingsPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _presence;

  @override
  void initState() {
    super.initState();
    _presence = AnimationController(
      vsync: this,
      duration: _motion,
      value: ref.read(videoSettingsPanelControllerProvider(widget.projectId)).open
          ? 1
          : 0,
    );
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  void _close() => ref
      .read(videoSettingsPanelControllerProvider(widget.projectId).notifier)
      .close();

  @override
  Widget build(BuildContext context) {
    ref.listen(videoSettingsPanelControllerProvider(widget.projectId),
        (previous, next) {
      if (previous?.open == next.open) return;
      _presence.duration = _motionFor(context);
      next.open ? _presence.forward() : _presence.reverse();
    });

    return AnimatedBuilder(
      animation: _presence,
      builder: (context, _) {
        // Nothing at all while closed, so the timeline underneath takes every
        // touch exactly as it did before the panel existed.
        if (_presence.isDismissed) return const SizedBox.shrink();

        final t = Curves.easeOutCubic.transform(_presence.value);
        final theme = Theme.of(context);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Tapping what is behind puts the panel away, the way tapping
            // outside any sheet does.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 5 * t, sigmaY: 5 * t),
                  // A light veil, not a curtain. At 55% the timeline behind
                  // all but disappeared on the device, which reads as having
                  // left the screen rather than as setting it aside.
                  child: ColoredBox(
                    color: theme.colorScheme.surface.withValues(alpha: 0.3 * t),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -12 * (1 - t)),
                  child: _PanelBody(
                    projectId: widget.projectId,
                    mode: widget.mode,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({required this.projectId, required this.mode});

  final String projectId;
  final EditorMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final panel = ref.watch(videoSettingsPanelControllerProvider(projectId));
    final controller =
        ref.read(videoSettingsPanelControllerProvider(projectId).notifier);
    final settings = ref.watch(projectVideoSettingsProvider(projectId)).value ??
        VideoSettings.defaults;

    void change(VideoSettings next) =>
        ref.read(projectVideoSettingsProvider(projectId).notifier).change(next);

    final other =
        mode == EditorMode.timeline ? EditorMode.script : EditorMode.timeline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The chosen item's options in a rectangle below, linked to it
          // like a folder tab: two lines drop from the item's edges, and
          // the rectangle's top is open between them.
          AppLinkedPanel(
            // The mode switch comes first, so the settings start at 1.
            selected: 1 + panel.item.index,
            items: [
              AppPanelItem(
                icon: other == EditorMode.script
                    ? Icons.notes
                    : Icons.view_timeline_outlined,
                label: other == EditorMode.script
                    ? l10n.editorModeScript
                    : l10n.editorModeTimeline,
                selected: false,
                onTap: () {
                  controller.close();
                  ref
                      .read(sessionEditorModeProvider(projectId).notifier)
                      .select(other);
                },
              ),
              for (final (item, icon, label) in [
                (
                  VideoSettingsItem.aspect,
                  Icons.aspect_ratio,
                  l10n.exportOptionsAspect,
                ),
                (
                  VideoSettingsItem.resolution,
                  Icons.high_quality_outlined,
                  l10n.exportOptionsQuality,
                ),
                (
                  VideoSettingsItem.watermark,
                  Icons.visibility_outlined,
                  l10n.videoSettingsPreviewItem,
                ),
              ])
                AppPanelItem(
                  icon: icon,
                  label: label,
                  selected: panel.item == item,
                  onTap: () => controller.show(item),
                ),
            ],
            // Clipped at the sides only: the rows' rules end in a T on the
            // rectangle's edge line, just outside this box, and a plain clip
            // cut the Ts off.
            child: ClipRect(
              clipper: const AppSideClipper(bleed: 4),
              child: AnimatedSize(
                duration: _motionFor(context),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: _motionFor(context),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // Only the arriving content takes space, so the card's
                  // height follows the new item rather than the taller of
                  // the two while they cross.
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (final child in previous)
                        Positioned(left: 0, right: 0, top: 0, child: child),
                      ?current,
                    ],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(panel.item),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: switch (panel.item) {
                        VideoSettingsItem.aspect => _AspectOptions(
                            settings: settings,
                            onChanged: change,
                          ),
                        VideoSettingsItem.resolution => _ResolutionOptions(
                            projectId: projectId,
                            settings: settings,
                            onChanged: change,
                          ),
                        VideoSettingsItem.watermark => _WatermarkOptions(
                            settings: settings,
                            onChanged: change,
                          ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five shapes, each drawn rather than only named.
class _AspectOptions extends StatelessWidget {
  const _AspectOptions({required this.settings, required this.onChanged});

  final VideoSettings settings;
  final ValueChanged<VideoSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppStrip(
      bare: true,
      children: [
        for (final (aspect, label) in <(ExportAspect, String)>[
          (ExportAspect.source, l10n.exportAspectSource),
          (ExportAspect.portrait9x16, l10n.exportAspectPortrait),
          (ExportAspect.square1x1, l10n.exportAspectSquare),
          (ExportAspect.portrait4x5, l10n.exportAspectFeed),
          (ExportAspect.landscape16x9, l10n.exportAspectWide),
        ])
          AppChoice(
            selected: settings.aspect == aspect,
            onTap: () => onChanged(settings.copyWith(aspect: aspect)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 30,
                  child: Center(child: _ShapeGlyph(ratio: aspect.ratio)),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small outline in the shape of a frame, or the "as shot" mark for Source.
class _ShapeGlyph extends StatelessWidget {
  const _ShapeGlyph({required this.ratio});

  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    final ratio = this.ratio;

    // Source has no shape of its own -- it is whatever was shot.
    if (ratio == null) return Icon(Icons.crop_free, size: 24, color: color);

    const box = 24.0;
    final width = ratio >= 1 ? box : box * ratio;
    final height = ratio >= 1 ? box / ratio : box;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.6),
      ),
    );
  }
}

/// The sizes, with those the footage cannot fill greyed out.
class _ResolutionOptions extends ConsumerWidget {
  const _ResolutionOptions({
    required this.projectId,
    required this.settings,
    required this.onChanged,
  });

  final String projectId;
  final VideoSettings settings;
  final ValueChanged<VideoSettings> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shortEdge =
        shortEdgeOf(ref.watch(projectSourceSizeProvider(projectId)).value);
    // What will actually render: a stored 4K on a 1080p clip shows as 1080p,
    // because 1080p is what the file will be.
    final effective = settings.quality.fitTo(shortEdge);

    return AppStrip(
      bare: true,
      children: [
        for (final (quality, label) in <(ExportQuality, String)>[
          (ExportQuality.p720, l10n.exportQuality720),
          (ExportQuality.p1080, l10n.exportQuality1080),
          (ExportQuality.p1440, l10n.exportQuality1440),
          (ExportQuality.p2160, l10n.exportQuality2160),
          (ExportQuality.source, l10n.exportQualitySource),
        ])
          AppChoice(
            selected: effective == quality,
            onTap: quality.availableFor(shortEdge)
                ? () => onChanged(settings.copyWith(quality: quality))
                : null,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// Whether the preview shows the mark. Its corner is chosen on the stage
/// above, where every corner becomes a target while this item is open.
class _WatermarkOptions extends StatelessWidget {
  const _WatermarkOptions({required this.settings, required this.onChanged});

  final VideoSettings settings;
  final ValueChanged<VideoSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // What the stage shows on top of the picture, each on or off. Neither is
    // ever part of the export by itself.
    Widget row(String label, bool value, VideoSettings Function(bool) next) =>
        MergeSemantics(
          child: InkWell(
            onTap: () => onChanged(next(!value)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                  AppToggle(
                    value: value,
                    onChanged: (v) => onChanged(next(v)),
                  ),
                ],
              ),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          l10n.videoSettingsWatermarkPreview,
          settings.previewWatermark,
          (v) => settings.copyWith(previewWatermark: v),
        ),
        row(
          l10n.videoSettingsSafeZonePreview,
          settings.previewSafeZone,
          (v) => settings.copyWith(previewSafeZone: v),
        ),
      ],
    );
  }
}

/// Height of the preview stage in both modes, Script and Timeline, so the
/// picture is the same size whichever one is showing.
const double stageHeight = 300;

/// The stage's picture in the project's frame, as both modes draw it.
class ProjectStageCanvas extends ConsumerWidget {
  const ProjectStageCanvas({
    super.key,
    required this.projectId,
    required this.clipId,
    required this.sourceSize,
    required this.picture,
    required this.mediaPositionMs,
    this.editable = false,
  });

  final String projectId;

  /// The clip on the stage.
  final String? clipId;

  /// The picture's own size, which is its shape when no shape is chosen.
  final Size sourceSize;

  final Widget picture;

  /// Where the player is inside the clip's media, for which caption and text
  /// are showing.
  final int mediaPositionMs;

  /// Whether items can be picked and moved here. Timeline only: Script mode
  /// is for the words, and shows the framing without offering to change it.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(projectVideoSettingsProvider(projectId)).value ??
        VideoSettings.defaults;
    final panel = ref.watch(videoSettingsPanelControllerProvider(projectId));
    final picking = panel.open && panel.item == VideoSettingsItem.watermark;
    final pro = ref.watch(proUnlockedProvider).value ?? false;

    // The gutter's eyes reach the preview: hidden video leaves the frame
    // black, hidden audio plays silent -- as the export will.
    final hidden = ref.watch(hiddenPlaybackProvider(projectId));
    final player = clipId == null
        ? null
        : ref.watch(mediaPlayerProvider(clipId!)).value;
    // This clip's own sound: silent where the audio track is hidden, where
    // its sound was removed, and outside its sound's window -- a sound
    // trimmed shorter than its picture stops where the trim says.
    final clip = (ref.watch(projectClipsProvider(projectId)).value ?? const [])
        .where((c) => c.id == clipId)
        .firstOrNull;
    final window = clip == null ? null : audioWindow(clip);
    final muted = hidden.audio ||
        (clip?.audioMuted ?? false) ||
        (window != null &&
            (mediaPositionMs < window.startMs ||
                mediaPositionMs >= window.endMs));
    if (player != null && player.value.volume != (muted ? 0.0 : 1.0)) {
      player.setVolume(muted ? 0 : 1);
    }
    // Black outside the clip.
    final shown = clip == null ? null : clipWindow(clip);
    final offClip = shown != null &&
        (mediaPositionMs < shown.startMs || mediaPositionMs >= shown.endMs);

    return VideoCanvas(
      ratio: settings.aspect.ratio ?? sourceSize.width / sourceSize.height,
      picture: StagePicture(
        projectId: projectId,
        clipId: clipId,
        sourceSize: sourceSize,
        picture: Opacity(
          opacity: hidden.video || offClip ? 0 : 1,
          child: picture,
        ),
      ),
      foreground: Stack(
        // The stage lays out against the frame as it did on its own.
        fit: StackFit.expand,
        children: [
          StageEditor(
            projectId: projectId,
            clipId: clipId,
            sourceSize: sourceSize,
            mediaPositionMs: mediaPositionMs,
            // Choosing the watermark's corner takes the frame's taps for
            // itself.
            editable: editable && !picking,
          ),
          // Other clips' sound reaching under this picture (J/L cuts).
          if (clipId != null)
            OverlapAudio(
              projectId: projectId,
              clipId: clipId!,
              mediaPositionMs: mediaPositionMs,
            ),
        ],
      ),
      // Pro exports have no watermark, so the preview has none either --
      // except while its corner is being picked, which needs something to
      // point at.
      watermark: settings.previewWatermark && (!pro || picking)
          ? settings.corner
          : null,
      safeZone: settings.previewSafeZone,
      pickCorner: picking
          ? (corner) => ref
              .read(projectVideoSettingsProvider(projectId).notifier)
              .change(settings.copyWith(corner: corner))
          : null,
      pickedCorner: settings.corner,
    );
  }
}
