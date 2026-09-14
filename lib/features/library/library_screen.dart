import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/media/shared_media.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/theme/theme_reveal.dart';
import '../../core/diarization/diarization_controller.dart';
import '../../core/whisper/transcription_language_controller.dart';
import '../../core/whisper/vad_controller.dart';
import '../../core/whisper/whisper_model_catalog.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../l10n/app_localizations.dart';
import '../transcription/import_controller.dart';
import '../transcription/project_screen.dart';
import '../transcription/transcript_repository.dart';

/// Landing screen: every imported project, plus the entry point for a new
/// import.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  StreamSubscription<SharedMedia>? _shares;

  @override
  void initState() {
    super.initState();

    // Media sent here from the system Sharesheet, arriving two ways.
    //
    // A cold start already has the intent waiting by the time the engine is up,
    // so it is *taken* on the first frame -- pulled rather than pushed, which
    // removes the race between the engine starting and a listener attaching.
    // A share into an already-running app comes through the stream instead.
    //
    // Started here rather than in `main.dart` because this screen is what shows
    // the import's progress and its result; a listener somewhere with no UI
    // would kick off an import nothing was rendering.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final channel = ref.read(sharedMediaChannelProvider);
      _shares = channel.shares().listen(_importShared);

      final initial = await channel.initialShare();
      if (initial != null) _importShared(initial);
    });
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  void _importShared(SharedMedia media) {
    if (!mounted) return;
    // A second share arriving mid-import is dropped rather than queued. The
    // pipeline runs one file at a time, and silently starting a second would
    // interleave two sets of progress into one status.
    if (ref.read(importControllerProvider) is ImportRunning) return;

    ref.read(importControllerProvider.notifier).importShared(media);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projects = ref.watch(projectListProvider);
    final import = ref.watch(importControllerProvider);

    ref.listen(importControllerProvider, (previous, next) {
      switch (next) {
        case ImportSucceeded(:final projectId):
          ref.read(importControllerProvider.notifier).reset();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectScreen(projectId: projectId),
            ),
          );
        case ImportCancelled():
          ref.read(importControllerProvider.notifier).reset();
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(l10n.importCancelled)));
        case _:
          break;
      }
    });

    final busy = import is ImportRunning;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        // Disabled mid-import: every setting behind this button changes what a
        // later stage of the running pipeline would do -- which weights load,
        // which language is declared, whether silence is skipped, whether
        // speakers are labelled.
        actions: [_SettingsButton(enabled: import is! ImportRunning)],
      ),
      // One scroll, so the import panel travels with the list rather than
      // pinning a slab to the top of a screen that is mostly list.
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ImportPanel(busy: busy),
                  if (import is ImportRunning) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ImportProgress(status: import),
                  ],
                  if (import is ImportFailed) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ImportError(error: import.error),
                  ],
                ],
              ),
            ),
          ),
          projects.when(
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                SliverToBoxAdapter(child: _ImportError(error: error)),
            data: (items) => items.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyLibrary(),
                  )
                : _ProjectSliver(projects: items),
          ),
        ],
      ),
    );
  }
}

/// The import action, as the largest thing on the page.
///
/// A tall panel rather than a floating button. Importing is what an empty
/// library is *for*, and a corner FAB makes the one action people opened the
/// app to perform the smallest thing on screen. Filled with the accent and
/// carrying the outline and offset shadow, so it is unmistakable before there
/// is anything else to look at.
class _ImportPanel extends ConsumerWidget {
  const _ImportPanel({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;

    // Dimmed rather than hidden while an import runs: the panel anchors the
    // page, and removing it would make the whole layout jump.
    final ink = busy ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary;

    return Semantics(
      button: true,
      enabled: !busy,
      label: l10n.importHeadline,
      child: InkWell(
        borderRadius: surface.borderRadius,
        onTap: busy
            ? null
            : () =>
                ref.read(importControllerProvider.notifier).importFromPicker(),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          decoration: surface.decoration(
            fill: busy
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
          ),
          child: Row(
            children: [
              Icon(Icons.add, size: 34, color: ink),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.importHeadline,
                      style: theme.textTheme.titleLarge?.copyWith(color: ink),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      l10n.importSubhead,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: ink.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The project list, with its own heading.
class _ProjectSliver extends StatelessWidget {
  const _ProjectSliver({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      sliver: SliverList.separated(
        itemCount: projects.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                l10n.projectsHeading,
                style: theme.textTheme.labelLarge,
              ),
            );
          }
          return _ProjectTile(project: projects[index - 1]);
        },
      ),
    );
  }
}

/// One project, as a card.
///
/// Everything needed to choose between two similar recordings is on the face of
/// it — when it was imported, how long it runs, what it costs on disk — because
/// the alternative is opening each one to find out.
class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;
    // Null while the directory is still being measured, so the meta line shows
    // what it knows rather than flashing a placeholder size.
    final bytes = ref.watch(projectMediaBytesProvider(project.id)).value;

    return InkWell(
      borderRadius: surface.borderRadius,
      onTap: () => _open(context),
      // Long-press still reaches the same menu, so the gesture people learned
      // before the button existed keeps working.
      onLongPress: () => _showActions(context, ref, l10n, bytes),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: surface.decoration(
          fill: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: surface.decoration(
                fill: theme.colorScheme.surface,
                // Inside an already-raised card. Nesting one offset shadow in
                // another is what turns this style into noise.
                raised: false,
              ),
              child: const Icon(Icons.movie_outlined, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // One line, ellipsised: three facts of wildly different
                  // lengths, and a wrap would make neighbouring rows different
                  // heights for no gain.
                  Text(
                    _meta(l10n, bytes),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.projectsHeading,
              onPressed: () => _showActions(context, ref, l10n, bytes),
            ),
          ],
        ),
      ),
    );
  }

  /// Created date, running time and size on disk, in that order — oldest fact
  /// first, because it is what distinguishes two imports of the same clip.
  String _meta(AppLocalizations l10n, int? bytes) {
    return [
      l10n.projectCreated(project.createdAt),
      if (project.durationMs case final int ms)
        _formatDuration(Duration(milliseconds: ms)),
      if (bytes != null) _formatBytes(l10n, bytes),
    ].join('  \u00b7  ');
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(projectId: project.id),
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    int? bytes,
  ) async {
    final action = await showModalBottomSheet<_ProjectAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  project.title,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined),
              title: Text(l10n.openAction),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ProjectAction.open),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.duplicateAction),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ProjectAction.duplicate),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(l10n.deleteAction),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ProjectAction.delete),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _ProjectAction.open:
        _open(context);
      case _ProjectAction.duplicate:
        await _duplicate(context, ref, l10n);
      case _ProjectAction.delete:
        await _confirmDelete(context, ref, l10n, bytes);
    }
  }

  /// Copies the project, explaining once what a copy actually costs.
  ///
  /// The notice is shown a single time and remembered in `Settings`, because
  /// "duplicating is free" is surprising and worth saying — and saying every
  /// time would be nagging.
  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final repository = ref.read(transcriptRepositoryProvider);
    final seen = await ref.read(appDatabaseProvider).readSetting(_sharedMediaHintKey);

    if (seen == null && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.duplicateSharesMediaTitle),
          content: Text(l10n.duplicateSharesMediaBody),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.gotItAction),
            ),
          ],
        ),
      );
      await ref.read(appDatabaseProvider).writeSetting(_sharedMediaHintKey, 'seen');
    }

    await repository.duplicateProject(
      projectId: project.id,
      title: l10n.duplicateTitle(project.title),
    );
  }

  /// Confirms, then deletes the project and its media for good.
  ///
  /// A dialog rather than a snackbar with an undo. Material reserves undo for
  /// frequent, reversible actions; this one destroys the imported video, so the
  /// user is told before it happens rather than given seconds to catch it. The
  /// message names the space recovered, which is the reason most people reach
  /// for delete in the first place.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    int? bytes,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteProjectTitle),
        content: Text(
          l10n.deleteProjectMessage(_formatBytes(l10n, bytes ?? 0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.editCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(transcriptRepositoryProvider).deleteProject(project.id);
    }
  }
}

enum _ProjectAction { open, duplicate, delete }

/// Remembers that the shared-media explanation has been shown.
const _sharedMediaHintKey = 'hint.duplicateSharesMedia';

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Scrollable so the copy still reaches the user on a short screen or at a
    // large accessibility text scale instead of overflowing.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.libraryEmptyTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.libraryEmptyBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.status});

  final ImportRunning status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = status.percent;

    final label = switch (status.stage) {
      ImportStage.preparingModel => l10n.stagePreparingModel,
      ImportStage.copyingMedia => l10n.stageCopyingMedia,
      ImportStage.extractingAudio => l10n.stageExtractingAudio,
      ImportStage.transcribing =>
        percent == null ? l10n.stageTranscribing : l10n.transcribingPercent(percent),
      ImportStage.identifyingSpeakers => percent == null
          ? l10n.stageIdentifyingSpeakers
          : l10n.identifyingSpeakersPercent(percent),
      ImportStage.saving => l10n.stageSaving,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(
            // Transcription and diarization both report real progress; the
            // remaining stages animate indeterminately rather than faking a
            // number. Driven off `percent` being present rather than off the
            // stage, so a future stage that learns to report needs no change
            // here.
            value: percent == null ? null : percent / 100,
          ),
        ],
      ),
    );
  }
}

class _ImportError extends ConsumerWidget {
  const _ImportError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.errorTitle,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$error',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref.read(importControllerProvider.notifier).reset(),
              child: Text(l10n.retryAction),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// A byte count at the largest unit that leaves a readable number.
///
/// Binary units (1024), because that is what Android's own storage screens
/// report -- showing 260 MB beside the system's 248 MB for the same file would
/// read as a bug. Whole numbers below a gigabyte and one decimal above it: at
/// that scale the tenth is the part people compare.
String _formatBytes(AppLocalizations l10n, int bytes) {
  const k = 1024;
  if (bytes < k) return l10n.sizeBytes(bytes);
  if (bytes < k * k) return l10n.sizeKilobytes((bytes / k).round());
  if (bytes < k * k * k) return l10n.sizeMegabytes((bytes / (k * k)).round());
  return l10n.sizeGigabytes((bytes / (k * k * k)).toStringAsFixed(1));
}

/// App-bar entry point for the transcription settings sheet.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return IconButton(
      icon: const Icon(Icons.tune),
      tooltip: l10n.settingsMenuTooltip,
      onPressed: enabled
          ? () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                // The sheet sizes to its content but is allowed to scroll, so
                // a large accessibility text scale grows it instead of
                // clipping the last row off the bottom.
                isScrollControlled: true,
                builder: (_) => const _SettingsSheet(),
              )
          : null,
    );
  }
}

/// Everything that changes what the *next* import does: which model runs,
/// which language the engine is told to expect, whether non-speech audio is
/// skipped, and whether speakers are labelled.
///
/// A bottom sheet rather than the popup menu this replaces. A popup dismisses
/// itself on every selection, which is wrong for a surface holding several
/// independent settings, and it cannot host a switch at all. The sheet also
/// makes the confirmation snackbars redundant — each row shows its own state,
/// so the change is visible where it was made.
/// Light, dark, or whatever the device is doing.
///
/// Lives in settings rather than in the app bar: it is a standing preference,
/// not something toggled while working. It exists at all because without it
/// there is no way to look at the theme the device is not currently in.
class _ThemeModeControl extends ConsumerStatefulWidget {
  const _ThemeModeControl();

  @override
  ConsumerState<_ThemeModeControl> createState() => _ThemeModeControlState();
}

class _ThemeModeControlState extends ConsumerState<_ThemeModeControl> {
  /// Where the finger went down, so the reveal starts under it rather than
  /// from an arbitrary point. `SegmentedButton` does not report a position, so
  /// it is caught on the way past.
  Offset? _tap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(themeModeSettingProvider).value ?? ThemeMode.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.themeModeLabel, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          // Scrolls rather than shrinking: three segments plus labels will not
          // fit a narrow screen at a large accessibility text scale.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Listener(
              onPointerDown: (event) => _tap = event.position,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined, size: 18),
                    label: Text(l10n.themeModeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text(l10n.themeModeDark),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => _switch(selection.first),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _switch(ThemeMode next) {
    void apply() =>
        ref.read(themeModeSettingProvider.notifier).select(next);

    final reveal = ThemeReveal.of(context);
    if (reveal == null) {
      apply();
      return;
    }

    reveal.reveal(
      // Falls back to the middle of the screen if the pointer position was
      // never seen -- a keyboard or accessibility activation, for instance.
      center: _tap ?? (Offset.zero & MediaQuery.sizeOf(context)).center,
      change: apply,
    );
  }
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final models = ref.watch(availableWhisperModelsProvider).value ?? const [];
    final selectedModel = ref.watch(selectedWhisperModelProvider).value;
    final language = ref.watch(selectedTranscriptionLanguageProvider).value;
    final skipSilence = ref.watch(silenceSkippingEnabledProvider).value;
    final diarize = ref.watch(speakerDiarizationEnabledProvider).value;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            // First, because it is the only entry here that changes the app
            // rather than the next import -- and because it is what lets the
            // dark theme be seen at all on a device set to light.
            const _ThemeModeControl(),
            const Divider(),
            // A picker over fewer than two models is just clutter; the rest of
            // the sheet still earns its place.
            if (models.length >= 2) ...[
              _SectionHeader(label: l10n.transcriptionModelTitle),
              for (final model in models)
                _ChoiceTile(
                  selected: model == selectedModel,
                  title: _labelFor(l10n, model),
                  subtitle: _hintFor(l10n, model),
                  onTap: () => ref
                      .read(selectedWhisperModelProvider.notifier)
                      .select(model),
                ),
              const Divider(),
            ],
            _SectionHeader(label: l10n.transcriptionLanguageTitle),
            for (final option in TranscriptionLanguage.values)
              _ChoiceTile(
                selected: option == language,
                title: _languageLabel(l10n, option),
                subtitle: _languageHint(l10n, option),
                onTap: () => ref
                    .read(selectedTranscriptionLanguageProvider.notifier)
                    .select(option),
              ),
            const Divider(),
            SwitchListTile(
              // Falls back to the declared default only for the instant before
              // the stored value has been read; `onChanged` stays null until
              // then so a tap cannot race the load and write the wrong value.
              value: skipSilence ?? SilenceSkippingEnabled.defaultEnabled,
              title: Text(l10n.silenceSkippingTitle),
              subtitle: Text(l10n.silenceSkippingHint),
              onChanged: skipSilence == null
                  ? null
                  : (value) => ref
                      .read(silenceSkippingEnabledProvider.notifier)
                      .setEnabled(value),
            ),
            SwitchListTile(
              value: diarize ?? SpeakerDiarizationEnabled.defaultEnabled,
              title: Text(l10n.diarizationTitle),
              subtitle: Text(l10n.diarizationHint),
              onChanged: diarize == null
                  ? null
                  : (value) => ref
                      .read(speakerDiarizationEnabledProvider.notifier)
                      .setEnabled(value),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        // Plain ink, not the accent. The accent is a *fill* colour: yellow
        // text on a cream page is close to unreadable, which is exactly what
        // this looked like before.
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}

/// One row in a mutually exclusive group.
///
/// Text is deliberately left to wrap rather than capped with `maxLines`:
/// these strings are localized and the sheet already scrolls, so growing is
/// always preferable to hiding half of an option's explanation.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // `ListTile.selected` tints the whole row with the primary colour, which
    // for a fill colour like yellow means unreadable text. Selection is shown
    // by the check mark and the weight instead, with the colour carried by the
    // icon where it sits on the page rather than behind letterforms.
    return ListTile(
      leading: Icon(
        selected ? Icons.check : Icons.radio_button_unchecked,
        color: selected ? theme.colorScheme.secondary : null,
      ),
      title: Text(
        title,
        style: selected
            ? theme.textTheme.titleSmall
            : theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

/// Localized name for a known model, falling back to its raw id.
///
/// The fallback is what keeps this honest once Tier 2 delivers models this
/// build has never heard of: they still render, just under their identifier
/// rather than a translated name.
String _labelFor(AppLocalizations l10n, WhisperModelDescriptor model) {
  return switch (model.id) {
    'base' => l10n.modelNameBase,
    'small-q5_1' => l10n.modelNameSmallQ51,
    _ => model.id,
  };
}

String _hintFor(AppLocalizations l10n, WhisperModelDescriptor model) {
  return switch (model.id) {
    'base' => l10n.modelHintFaster,
    _ => l10n.modelHintAccurate,
  };
}

/// Exhaustive over [TranscriptionLanguage] rather than falling back to the
/// code, unlike the model labels above: this enum is closed and every entry is
/// one this build deliberately offers, so a missing string is a bug the
/// compiler should catch rather than something to paper over at runtime.
String _languageLabel(AppLocalizations l10n, TranscriptionLanguage language) {
  return switch (language) {
    TranscriptionLanguage.auto => l10n.languageAuto,
    TranscriptionLanguage.english => l10n.languageEnglish,
  };
}

String _languageHint(AppLocalizations l10n, TranscriptionLanguage language) {
  return switch (language) {
    TranscriptionLanguage.auto => l10n.languageAutoHint,
    TranscriptionLanguage.english => l10n.languageEnglishHint,
  };
}
