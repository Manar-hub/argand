import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/video/export_options.dart';
import '../../l10n/app_localizations.dart';
import 'editor_mode_controller.dart';
import 'video_canvas.dart';
import 'video_settings.dart';

part 'video_settings_panel.g.dart';

/// The settings the panel can show. The mode switch is not one of them: it
/// acts rather than shows, so it never becomes the selected item.
enum VideoSettingsItem { aspect, resolution, watermark }

typedef VideoSettingsPanelState = ({bool open, VideoSettingsItem item});

/// Whether a project's video settings are open, and on which item.
///
/// A provider rather than widget state because two separate parts of the
/// screen answer to it: the transport row, which hides its buttons, and the
/// body, which shows the panel. It also remembers the last item for as long
/// as the project is open, so reopening the panel lands where it was left.
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
///
/// One figure for all of them, so the buttons fading, the panel arriving and
/// the content changing read as one motion rather than several.
const Duration _motion = Duration(milliseconds: 220);

/// Zero when the user has asked for no animation (docs/design-direction.md
/// §6): with motion off, everything is simply there.
Duration _motionFor(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : _motion;

/// The gear that opens the panel, in both modes' transport rows.
///
/// **Turns a quarter and takes the accent while open**, so the same button
/// reads as the way out: there is no separate close control to find.
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
        child: Icon(
          Icons.settings_outlined,
          color: open ? theme.colorScheme.secondary : null,
        ),
      ),
    );
  }
}

/// Fades a control out while the panel is open, and back in after.
///
/// **Fades rather than removes.** Taking the button out of the row would
/// shift what is left of it, and the play button would drift off centre just
/// as the user's eye goes to it. An invisible button that cannot be pressed
/// holds its place.
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
///
/// **Inline, not a window.** It covers the timeline (or the transcript) and
/// leaves the stage above in view, so a new shape or corner shows on the
/// real preview as it is chosen -- which is what made a preview inside the
/// panel unnecessary, and most of the old panel's clutter with it.
///
/// What is behind is dimmed and blurred, the one soft effect in an otherwise
/// flat style: it says "set aside for a moment" without hiding where the user
/// is. The panel's own surfaces keep the flat fill and hard outline.
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
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PanelItem(
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
                ),
                // Sets the mode switch apart from the three settings: it
                // acts, the others show.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  child: SizedBox(
                    width: appHairlineWidth,
                    child: ColoredBox(color: appHairline(theme)),
                  ),
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
                    Icons.branding_watermark_outlined,
                    l10n.videoSettingsWatermarkItem,
                  ),
                ])
                  Expanded(
                    child: _PanelItem(
                      icon: icon,
                      label: label,
                      selected: panel.item == item,
                      onTap: () => controller.show(item),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DecoratedBox(
            decoration: surface.decoration(
              fill: theme.colorScheme.surfaceContainerHighest,
              raised: false,
            ),
            child: ClipRRect(
              borderRadius: surface.borderRadius,
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
                      padding: const EdgeInsets.all(AppSpacing.md),
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

/// One of the panel's items, in the bottom toolbar's own style: icon over
/// label on a bordered surface, the accent when selected.
class _PanelItem extends StatelessWidget {
  const _PanelItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink =
        selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Semantics(
        selected: selected,
        button: true,
        child: PressableSurface(
          selected: selected,
          fill: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          border: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: ink, size: 22),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(color: ink),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice inside an item's options: a small bordered cell, the accent when
/// chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;

  /// Null when the choice is not available, which greys it out.
  final VoidCallback? onTap;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.38,
        duration: _motionFor(context),
        child: PressableSurface(
          selected: selected,
          fill:
              selected ? theme.colorScheme.primary : theme.colorScheme.surface,
          border: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.sm,
                ),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
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

    return Row(
      children: [
        for (final (index, (aspect, label)) in <(ExportAspect, String)>[
          (ExportAspect.source, l10n.exportAspectSource),
          (ExportAspect.portrait9x16, l10n.exportAspectPortrait),
          (ExportAspect.square1x1, l10n.exportAspectSquare),
          (ExportAspect.portrait4x5, l10n.exportAspectFeed),
          (ExportAspect.landscape16x9, l10n.exportAspectWide),
        ].indexed) ...[
          if (index > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _Choice(
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
          ),
        ],
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
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// The sizes, with those the footage cannot fill greyed out.
///
/// **No pixel count.** The name of the size is what people choose by; the
/// exact frame is the render's business.
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

    return Row(
      children: [
        for (final (index, (quality, label)) in <(ExportQuality, String)>[
          (ExportQuality.p720, l10n.exportQuality720),
          (ExportQuality.p1080, l10n.exportQuality1080),
          (ExportQuality.p1440, l10n.exportQuality1440),
          (ExportQuality.p2160, l10n.exportQuality2160),
          (ExportQuality.source, l10n.exportQualitySource),
        ].indexed) ...[
          if (index > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _Choice(
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
          ),
        ],
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

    return Row(
      children: [
        Text(
          l10n.videoSettingsWatermarkPreview,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppSegmentRow<bool>(
            selected: settings.previewWatermark,
            items: {
              true: l10n.videoSettingsVisible,
              false: l10n.videoSettingsHidden,
            },
            onSelected: (visible) =>
                onChanged(settings.copyWith(previewWatermark: visible)),
          ),
        ),
      ],
    );
  }
}

/// The stage's picture in the project's frame, as both modes draw it.
///
/// **One widget for both stages**, so Script and Timeline cannot drift apart:
/// the project's shape, the picture fitted inside it with black bars as the
/// render fits it, the watermark where it will be -- and, while the
/// Watermark item is open, every corner of the frame as a target.
class ProjectStageCanvas extends ConsumerWidget {
  const ProjectStageCanvas({
    super.key,
    required this.projectId,
    required this.sourceSize,
    required this.picture,
    this.overlay,
  });

  final String projectId;

  /// The picture's own size, which is its shape when no shape is chosen.
  final Size sourceSize;

  final Widget picture;

  /// The captions, drawn inside the frame.
  final Widget? overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(projectVideoSettingsProvider(projectId)).value ??
        VideoSettings.defaults;
    final panel = ref.watch(videoSettingsPanelControllerProvider(projectId));
    final picking = panel.open && panel.item == VideoSettingsItem.watermark;

    return VideoCanvas(
      ratio: settings.aspect.ratio ?? sourceSize.width / sourceSize.height,
      picture: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(size: sourceSize, child: picture),
      ),
      overlay: overlay,
      watermark: settings.previewWatermark ? settings.corner : null,
      pickCorner: picking
          ? (corner) => ref
              .read(projectVideoSettingsProvider(projectId).notifier)
              .change(settings.copyWith(corner: corner))
          : null,
      pickedCorner: settings.corner,
    );
  }
}
