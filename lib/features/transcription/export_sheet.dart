import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/captions/subtitle_export.dart';
import '../../core/database/database.dart';
import '../../core/monetization/monetization.dart';
import '../../core/theme/app_controls.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/video/export_options.dart';
import '../../l10n/app_localizations.dart';
import '../monetization/placeholder_ad_screen.dart';
import '../monetization/pro_offer.dart';
import 'transcript_repository.dart';
import 'video_canvas.dart';
import 'video_export_controller.dart';
import 'video_settings.dart';

/// What the export sheet came back with.
sealed class ExportDecision {
  const ExportDecision();
}

/// Render the timeline to video with these options.
///
/// When [ExportOptions.waiver] is set, the ad has already been watched (or Pro
/// is owned) by the time this exists: the sheet does not close on an
/// unbranded export until it has been paid for.
final class VideoExportDecision extends ExportDecision {
  const VideoExportDecision(this.options);

  final ExportOptions options;
}

/// Write the project's captions out as a subtitle file.
final class SubtitleExportDecision extends ExportDecision {
  const SubtitleExportDecision({
    required this.format,
    required this.includeSpeakers,
    required this.lineLength,
  });

  final SubtitleFormat format;
  final bool includeSpeakers;
  final SubtitleLineLength lineLength;
}

enum _ExportTab { video, srt, vtt, pro }

/// Everything to decide before an export, in one sheet.
///
/// **One sheet, with the format across the top.** The first version was a
/// format list that opened a second sheet for video, so choosing video cost a
/// tap and a new surface while SRT and VTT exported from the list itself. A
/// segmented row puts the four side by side and lets each keep only the
/// options that apply to it.
///
/// **The ad plays from inside the sheet, before anything renders.** An
/// unbranded export returns from here only after the ad has been watched to
/// the end; if it is closed early or cannot load, the sheet stays open and
/// says why. Nothing is exported until the user has seen what they are going
/// to get.
Future<ExportDecision?> showExportSheet(
  BuildContext context,
  String projectId,
) {
  return showModalBottomSheet<ExportDecision>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExportSheet(projectId: projectId),
  );
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  /// Tall enough that the Video tab, the longest, fits without scrolling on a
  /// typical phone, leaving the page it was opened from visible above it.
  static const double _sheetHeightFraction = 0.85;

  _ExportTab _tab = _ExportTab.video;

  /// What the user asked for, not what they have been granted: only a
  /// finished ad turns this into an unbranded export.
  bool _removeWatermark = false;

  /// Set while the connection is checked or the ad is on screen, so Export
  /// cannot be pressed a second time underneath it.
  bool _busy = false;

  /// Why the watermark is still on, when that was not the user's choice.
  String? _adNote;

  bool _includeSpeakers = true;
  SubtitleLineLength _lineLength = SubtitleLineLength.standard;

  /// The short edge of the footage, for offering only the sizes it can fill.
  /// Watched, so it is called only while building.
  int? get _sourceShortEdge => shortEdgeOf(
        ref.watch(projectSourceSizeProvider(widget.projectId)).value,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pro = ref.watch(proUnlockedProvider).value ?? false;
    final settings =
        ref.watch(projectVideoSettingsProvider(widget.projectId)).value ??
            VideoSettings.defaults;
    final hasCaptions =
        ref.watch(projectScriptProvider(widget.projectId)).words.isNotEmpty;

    return SafeArea(
      child: SizedBox(
        // **One height for every tab.** Sized to its content, the sheet
        // shrank when a shorter tab was chosen and the tab row slid down the
        // screen -- so the next tap on a tab landed above the sheet and closed
        // it. A fixed height keeps the row under the finger, with the body
        // scrolling inside it and the footer always in reach.
        height: MediaQuery.sizeOf(context).height * _sheetHeightFraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.exportSheetTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppSegmentRow<_ExportTab>(
                    items: {
                      _ExportTab.video: l10n.exportTabVideo,
                      _ExportTab.srt: l10n.exportTabSrt,
                      _ExportTab.vtt: l10n.exportTabVtt,
                      _ExportTab.pro: l10n.exportTabPro,
                    },
                    selected: _tab,
                    onSelected: (tab) => setState(() {
                      _tab = tab;
                      _adNote = null;
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: switch (_tab) {
                  _ExportTab.video =>
                    _videoOptions(l10n, settings, pro: pro),
                  _ExportTab.srt ||
                  _ExportTab.vtt =>
                    _subtitleOptions(l10n, theme, hasCaptions: hasCaptions),
                  _ExportTab.pro => _ProFormats(),
                },
              ),
            ),
            _ExportFooter(
              // Hidden only where it would be redundant: on the Pro formats
              // tab the main button is already Get Pro, and someone who owns
              // Pro has nothing left to be offered.
              showProStrip: !pro && _tab != _ExportTab.pro,
              onGetPro: _getPro,
              primary: _primaryAction(
                l10n,
                settings,
                pro: pro,
                hasCaptions: hasCaptions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoOptions(
    AppLocalizations l10n,
    VideoSettings settings, {
    required bool pro,
  }) {
    // The same values the timeline's video settings edit: choosing a shape
    // here changes the project's shape, and the preview behind this sheet
    // follows it.
    final notifier =
        ref.read(projectVideoSettingsProvider(widget.projectId).notifier);
    final shortEdge = _sourceShortEdge;
    final options = settings.exportOptionsFor(shortEdge);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectFramePreview(
          projectId: widget.projectId,
          options: options,
          // What the file will look like: the mark is in the preview unless
          // this export is going to leave it off.
          showWatermark: !pro && !_removeWatermark,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Label(l10n.exportOptionsAspect),
        const SizedBox(height: AppSpacing.sm),
        _ChipRow(
          children: [
            for (final (aspect, label) in <(ExportAspect, String)>[
              (ExportAspect.source, l10n.exportAspectSource),
              (ExportAspect.portrait9x16, l10n.exportAspectPortrait),
              (ExportAspect.square1x1, l10n.exportAspectSquare),
              (ExportAspect.portrait4x5, l10n.exportAspectFeed),
              (ExportAspect.landscape16x9, l10n.exportAspectWide),
            ])
              _OptionChip(
                label: label,
                selected: settings.aspect == aspect,
                onTap: () =>
                    notifier.change(settings.copyWith(aspect: aspect)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Label(l10n.exportOptionsQuality),
        const SizedBox(height: AppSpacing.sm),
        _ChipRow(
          children: [
            for (final (quality, label) in <(ExportQuality, String)>[
              (ExportQuality.p720, l10n.exportQuality720),
              (ExportQuality.p1080, l10n.exportQuality1080),
              (ExportQuality.p1440, l10n.exportQuality1440),
              (ExportQuality.p2160, l10n.exportQuality2160),
              (ExportQuality.source, l10n.exportQualitySource),
            ])
              _OptionChip(
                label: label,
                // The size the file will be, which a stored choice larger
                // than the footage is not.
                selected: options.quality == quality,
                // Sizes the footage cannot fill are shown, greyed, rather
                // than hidden: "why is there no 4K" is a worse question than
                // "why is 4K off".
                onTap: quality.availableFor(shortEdge)
                    ? () =>
                        notifier.change(settings.copyWith(quality: quality))
                    : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (pro)
          _Notice(
            icon: Icons.verified_outlined,
            text: l10n.exportProIncluded,
          )
        else
          _ToggleCard(
            title: l10n.exportRemoveWatermark,
            subtitle: l10n.exportRemoveWatermarkDetail,
            value: _removeWatermark,
            onChanged: _busy ? null : (on) => _setRemoveWatermark(l10n, on),
            note: _adNote,
          ),
      ],
    );
  }

  Widget _subtitleOptions(
    AppLocalizations l10n,
    ThemeData theme, {
    required bool hasCaptions,
  }) {
    final detail =
        _tab == _ExportTab.srt ? l10n.exportSrtDetail : l10n.exportVttDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(detail, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.exportSubtitlesTimed,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!hasCaptions) ...[
          const SizedBox(height: AppSpacing.md),
          _Notice(
            icon: Icons.info_outline,
            text: l10n.exportSubtitlesNeedTranscript,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _ToggleCard(
          title: l10n.exportIncludeSpeakers,
          value: _includeSpeakers,
          onChanged: (value) => setState(() => _includeSpeakers = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Label(l10n.exportLineLength),
        const SizedBox(height: AppSpacing.sm),
        _ChipRow(
          children: [
            for (final (length, label) in <(SubtitleLineLength, String)>[
              (SubtitleLineLength.standard, l10n.exportLineStandard),
              (SubtitleLineLength.short, l10n.exportLineShort),
            ])
              _OptionChip(
                label: label,
                selected: _lineLength == length,
                onTap: () => setState(() => _lineLength = length),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.exportLineHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  AppDialogAction _primaryAction(
    AppLocalizations l10n,
    VideoSettings settings, {
    required bool pro,
    required bool hasCaptions,
  }) {
    // Read here, while building, not inside the button's callback.
    final videoOptions = settings.exportOptionsFor(_sourceShortEdge);

    return switch (_tab) {
      _ExportTab.video => AppDialogAction(
          label: !pro && _removeWatermark
              ? l10n.exportWatchAdThenExport
              : l10n.exportStart,
          emphasis: AppDialogEmphasis.primary,
          onPressed: _busy
              ? null
              : () => _exportVideo(l10n, videoOptions, pro: pro),
        ),
      _ExportTab.srt || _ExportTab.vtt => AppDialogAction(
          label: l10n.exportStart,
          emphasis: AppDialogEmphasis.primary,
          onPressed: hasCaptions
              ? () => Navigator.of(context).pop(
                    SubtitleExportDecision(
                      format: _tab == _ExportTab.srt
                          ? SubtitleFormat.srt
                          : SubtitleFormat.vtt,
                      includeSpeakers: _includeSpeakers,
                      lineLength: _lineLength,
                    ),
                  )
              : null,
        ),
      // The formats are not built, so even an owner of Pro has nothing to
      // export here yet; the button says so rather than doing nothing.
      _ExportTab.pro => AppDialogAction(
          label: pro ? l10n.exportProComing : l10n.exportGetPro,
          emphasis: AppDialogEmphasis.pro,
          onPressed: pro ? null : _getPro,
        ),
    };
  }

  /// Turns watermark removal on only when an ad could actually play.
  ///
  /// Checked here, at the moment of choosing, rather than when the sheet
  /// opens: this is the point the user asks for an ad, and a privacy-first app
  /// should not reach for the network before anyone has.
  Future<void> _setRemoveWatermark(AppLocalizations l10n, bool on) async {
    if (!on) {
      setState(() {
        _removeWatermark = false;
        _adNote = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _adNote = null;
    });
    final available = await ref.read(rewardedAdsProvider).canLoad();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _removeWatermark = available;
      _adNote = available ? null : l10n.exportAdOffline;
    });
  }

  Future<void> _exportVideo(
    AppLocalizations l10n,
    ExportOptions options, {
    required bool pro,
  }) async {
    if (pro) {
      final waiver = await claimProWaiver(ref.read(appDatabaseProvider));
      if (!mounted) return;
      _finish(waiver == null ? options : options.withWaiver(waiver));
      return;
    }

    if (!_removeWatermark) {
      _finish(options);
      return;
    }

    setState(() {
      _busy = true;
      _adNote = null;
    });
    final outcome = await ref.read(rewardedAdsProvider).show(context);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case AdRewarded(:final waiver):
        _finish(options.withWaiver(waiver));

      // **Back to the sheet, not a branded export.** The user asked for no
      // watermark; rendering one they did not want would be a surprise, and
      // rendering without one would be the bypass. They choose again.
      case AdDismissed():
        setState(() => _adNote = l10n.exportAdIncomplete);

      // Offline, or nothing to show. The watermark stays on and the sheet says
      // why, so the next tap on Export is a branded render the user chose.
      case AdUnavailable():
        setState(() {
          _removeWatermark = false;
          _adNote = l10n.exportAdOffline;
        });
    }
  }

  void _finish(ExportOptions options) =>
      Navigator.of(context).pop(VideoExportDecision(options));

  /// The Pro purchase, which does not exist yet.
  ///
  /// A dialog rather than a snackbar: a snackbar raised from inside a modal
  /// sheet appears on the page underneath it, behind the sheet, where nobody
  /// sees it.
  Future<void> _getPro() => showProComingSoon(context);

}

/// The part of the sheet that never scrolls away: the Pro offer and the
/// button that acts.
///
/// **Get Pro sits beside every export**, above the button the user came to
/// press. It is seen each time without standing in the way: a strip, not a
/// dialog, and never between the user and a free export.
class _ExportFooter extends StatelessWidget {
  const _ExportFooter({
    required this.showProStrip,
    required this.onGetPro,
    required this.primary,
  });

  final bool showProStrip;
  final VoidCallback onGetPro;
  final AppDialogAction primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: appHairline(theme),
            width: appHairlineWidth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showProStrip) ...[
              ProOfferRow(onGetPro: onGetPro),
              const SizedBox(height: AppSpacing.md),
            ],
            // Taller than a dialog's buttons: the one thing the sheet is for.
            AppDialogButton(action: primary, height: 60),
          ],
        ),
      ),
    );
  }
}

/// The professional formats Pro will add.
///
/// **Honest about what exists.** None of these are built yet, and each row
/// says "Coming with Pro" rather than offering an export that would fail.
/// They are listed now because they are what the purchase is for beyond the
/// watermark, and new output is the only kind of thing Pro may sell
/// (CLAUDE.md §2) -- SRT and VTT stay free on their own tabs.
class _ProFormats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.exportProFormatsIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        for (final (index, (title, detail)) in <(String, String)>[
          (l10n.exportProFormatAss, l10n.exportProFormatAssDetail),
          (l10n.exportProFormatFcpxml, l10n.exportProFormatFcpxmlDetail),
          (l10n.exportProFormatPremiere, l10n.exportProFormatPremiereDetail),
        ].indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          _LockedFormat(title: title, detail: detail),
        ],
      ],
    );
  }
}

class _LockedFormat extends StatelessWidget {
  const _LockedFormat({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;

    return DecoratedBox(
      decoration: surface.decoration(
        fill: theme.colorScheme.surfaceContainerHighest,
        raised: false,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l10n.exportProComing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A setting that is on or off, drawn on the app's own surface.
///
/// A `SwitchListTile` was the first version and looked like a settings row from
/// another app: no outline, no fill, nothing tying it to the chips beside it.
///
/// [note] explains a state the user did not choose -- the ad could not load,
/// or was closed early -- right where they are looking.
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.note,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the switch, which is how "busy" shows.
  final ValueChanged<bool>? onChanged;

  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = this.note;

    // No box round it: a setting is a line of the sheet, like the labelled
    // rows above it.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              AppToggle(value: value, onChanged: onChanged),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                right: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A line of information on the same bordered surface as the controls.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;

    return DecoratedBox(
      decoration: surface.decoration(
        fill: theme.colorScheme.surfaceContainerHighest,
        raised: false,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // One strip across the sheet, a rule between presets and none round each
    // -- the same row every other set of choices uses. Labels ellipsize
    // rather than wrap, so a large text scale shortens a word instead of
    // pushing a preset off the row.
    return AppStrip(onCard: true, children: children);
  }
}

/// One preset, using the app's own pressed-surface feedback.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Null when the preset is not available, which greys it out.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    // A cell of the strip: no frame of its own, a block of ink when chosen,
    // reaching over the strip's lines.
    final chip = AppSelectedBleed(
      selected: selected,
      color: theme.colorScheme.secondary,
      child: PressableSurface(
      selected: selected,
      fill: selected ? theme.colorScheme.secondary : Colors.transparent,
      borderRadius: BorderRadius.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // The surface already shows the press; Material's splash on top of
          // it is a second, conflicting kind of feedback.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.md,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.onSecondary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    ),
    );

    return Semantics(
      enabled: enabled,
      child: Opacity(opacity: enabled ? 1 : 0.38, child: chip),
    );
  }
}

/// Shows how far the render has got, and offers to stop it.
///
/// **Not dismissible by tapping away.** The only ways out are cancelling and
/// the render finishing, because a progress window that can be lost behind the
/// app leaves a minutes-long job running with nothing to stop it.
///
/// Returns true when the user stopped the render from here.
///
/// **Only that.** Whether a render that ran to the end succeeded is the
/// render's own answer, taken from the future the controller returns -- this
/// window reports the one thing the render cannot know, which is that somebody
/// asked it to stop.
Future<bool> showExportProgress(
  BuildContext context,
  String projectId,
) async {
  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExportProgressDialog(projectId: projectId),
  );
  // Null means the route was popped by something other than this window -- an
  // Android back gesture. Taken as a cancellation, which is what it meant.
  return cancelled ?? true;
}

class _ExportProgressDialog extends ConsumerStatefulWidget {
  const _ExportProgressDialog({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_ExportProgressDialog> createState() =>
      _ExportProgressDialogState();
}

class _ExportProgressDialogState extends ConsumerState<_ExportProgressDialog> {
  /// Set the moment this window has asked to close.
  ///
  /// The controller is reset to idle right after it reports an outcome, and
  /// that reset is a second state change arriving here. Without this the
  /// window would pop twice -- the second time taking the screen underneath it
  /// with it.
  bool _closing = false;

  @override
  void initState() {
    super.initState();

    // A short project can finish rendering before this window is even built,
    // in which case no state change ever arrives and nothing would close it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = ref.read(videoExportControllerProvider(widget.projectId));
      if (status is! VideoExportRunning) _close(cancelled: false);
    });
  }

  void _close({required bool cancelled}) {
    if (_closing || !mounted) return;
    _closing = true;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final status = ref.watch(videoExportControllerProvider(widget.projectId));

    ref.listen(videoExportControllerProvider(widget.projectId), (_, next) {
      if (next is VideoExportRunning) return;
      _close(cancelled: false);
    });

    final percent = status is VideoExportRunning ? status.percent : null;

    return AppDialog(
      title: l10n.exportProgressTitle,
      actions: [
        AppDialogAction(
          label: l10n.exportCancel,
          onPressed: () {
            // **Closed first, then cancelled.** Cancelling puts the controller
            // back to idle, which the listener above sees as the render simply
            // ending -- so awaiting the cancel let that listener close this
            // window as an ordinary finish, and the caller never learned the
            // user had stopped it. Recording the reason before starting the
            // cancel is what makes the answer the user's rather than the
            // race's.
            final notifier = ref
                .read(videoExportControllerProvider(widget.projectId).notifier);
            _close(cancelled: true);
            unawaited(notifier.cancel());
          },
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            percent == null
                ? l10n.exportProgressPreparing
                : l10n.exportProgressPercent(percent),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // A bordered trough with a hard-edged fill, rather than Material's
          // rounded hairline: the bar is the largest thing in this window and
          // has to look like it belongs to the same app as the chips above.
          DecoratedBox(
            decoration: surface.decoration(
              fill: theme.colorScheme.surface,
              raised: false,
            ),
            child: ClipRRect(
              borderRadius: surface.borderRadius,
              child: SizedBox(
                height: 18,
                child: LinearProgressIndicator(
                  // Indeterminate until Transformer reports something. A bar
                  // sitting at zero looks stalled; a moving one says work has
                  // started, which in the first seconds is all that is true.
                  value: percent == null ? null : percent / 100,
                  backgroundColor: Colors.transparent,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.exportProgressNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
