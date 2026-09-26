import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/media/shared_media.dart';
import '../../core/monetization/monetization.dart';
import '../../core/theme/accent_color_controller.dart';
import '../../core/theme/app_color_picker.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/theme/theme_reveal.dart';
import '../../l10n/app_localizations.dart';
import '../monetization/pro_offer.dart';
import '../transcription/transcription_options.dart';
import '../transcription/editor_mode_controller.dart';
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

  /// Which mode the entry button just tapped wants the resulting project to
  /// open in, consumed the moment the pipeline reports [ImportSucceeded].
  /// Cleared on every path that is not "a button was just tapped" -- a
  /// share-sheet arrival, or the previous attempt being cancelled -- so it
  /// never leaks into an import it was not meant for.
  EditorMode? _pendingImportMode;

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

  Future<void> _importShared(SharedMedia media) async {
    if (!mounted) return;
    // A second share arriving mid-import is dropped rather than queued. The
    // pipeline runs one file at a time, and silently starting a second would
    // interleave two sets of progress into one status.
    if (ref.read(importControllerProvider) is ImportRunning) return;

    // **An import transcribes**, so it gets the same options any other run
    // does. Asking on a share is not an interruption of something already
    // underway: this is the first thing that happens after the file arrives.
    if (!await showTranscriptionOptions(context)) return;
    if (!mounted) return;

    // A share never came through a button, so it never has a mode opinion --
    // clear a mode a cancelled button-triggered import might have left behind.
    _pendingImportMode = null;
    ref.read(importControllerProvider.notifier).importShared(media);
  }

  Future<void> _startImport(EditorMode mode) async {
    if (!await showTranscriptionOptions(context)) return;
    if (!mounted) return;

    _pendingImportMode = mode;
    ref.read(importControllerProvider.notifier).importFromPicker();
  }

  /// Names an empty project and opens it on the timeline.
  ///
  /// **No picker, and nothing transcribed.** This is the entry point for
  /// building something out of several clips: the project is created first and
  /// media is added to it afterwards, which is the opposite order from
  /// "Transcribe", where the file *is* the project.
  Future<void> _createProject() async {
    final l10n = AppLocalizations.of(context);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const _NameProjectDialog(),
    );
    if (title == null || !mounted) return;

    final projectId = await ref
        .read(transcriptRepositoryProvider)
        .createEmptyProject(
          title: title.trim().isEmpty ? l10n.createProjectDefaultName : title.trim(),
        );
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(
          projectId: projectId,
          initialMode: EditorMode.timeline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projects = ref.watch(projectListProvider);
    final import = ref.watch(importControllerProvider);

    ref.listen(importControllerProvider, (previous, next) {
      switch (next) {
        case ImportSucceeded(:final projectId):
          final mode = _pendingImportMode;
          _pendingImportMode = null;
          ref.read(importControllerProvider.notifier).reset();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectScreen(projectId: projectId, initialMode: mode),
            ),
          );
        case ImportCancelled():
          _pendingImportMode = null;
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
                  _ImportPanel(
                    busy: busy,
                    icon: Icons.movie_creation_outlined,
                    headline: l10n.createProjectHeadline,
                    subhead: l10n.createProjectSubhead,
                    onTap: _createProject,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ImportPanel(
                    busy: busy,
                    icon: Icons.text_snippet_outlined,
                    headline: l10n.importHeadline,
                    subhead: l10n.importSubhead,
                    onTap: () => _startImport(EditorMode.script),
                  ),
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

/// Asks for a new project's name before it is created.
///
/// Prefilled and pre-selected so confirming immediately is a valid answer: the
/// point of naming here is that a project holding several clips has no filename
/// to borrow one from, not that the user must invent something before starting.
class _NameProjectDialog extends StatefulWidget {
  const _NameProjectDialog();

  @override
  State<_NameProjectDialog> createState() => _NameProjectDialogState();
}

class _NameProjectDialogState extends State<_NameProjectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppDialog(
      title: l10n.createProjectTitle,
      // **No transcription options here.** This creates an empty project and
      // transcribes nothing -- media is added afterwards and run separately --
      // so there is no run for those choices to apply to. They belong where a
      // transcription actually starts, which is the Transcribe action.
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: l10n.createProjectDefaultName),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        AppDialogAction(
          label: l10n.createProjectAction,
          emphasis: AppDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
        AppDialogAction(
          label: l10n.editCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// One of the two entry points on the library, as the largest things on the
/// page.
///
/// Tall panels rather than a floating button. Importing is what an empty
/// library is *for*, and a corner FAB makes the one action people opened the
/// app to perform the smallest thing on screen. Filled with the accent and
/// carrying the outline and offset shadow, so each is unmistakable before
/// there is anything else to look at.
///
/// **Two of these, not one**, since the library gained a second entry point:
/// "Import & edit" opens the result in Timeline mode, "Transcribe" (the
/// original single button) opens it in Script mode as it always did. Both
/// run the identical `ImportController` pipeline -- see `_startImport` --
/// they differ only in which mode the resulting `ProjectScreen` defaults to.
class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.busy,
    required this.icon,
    required this.headline,
    required this.subhead,
    required this.onTap,
  });

  final bool busy;
  final IconData icon;
  final String headline;
  final String subhead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;

    // Dimmed rather than hidden while an import runs: the panel anchors the
    // page, and removing it would make the whole layout jump.
    final ink = busy ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary;

    return Semantics(
      button: true,
      enabled: !busy,
      label: headline,
      child: InkWell(
        borderRadius: surface.borderRadius,
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          decoration: surface.decoration(
            fill: busy
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary,
            // One of the two things this screen is for: raised.
            raised: true,
          ),
          child: Row(
            children: [
              Icon(icon, size: 30, color: ink),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.titleMedium?.copyWith(color: ink),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subhead,
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
    final surface = context.surface;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      // One outlined box with a rule between rows, as the reference's lists,
      // rather than a card per project: a library is one list, and a stack of
      // separate boxes read as a pile of unrelated things.
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.projectsHeading,
              style: theme.textTheme.labelLarge,
            ),
          ),
          DecoratedBox(
            decoration: surface.decoration(
              fill: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Padding(
              // Inside the outline, so the rows' own fill never paints over it.
              padding: EdgeInsets.all(surface.borderWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, project) in projects.indexed) ...[
                    if (index > 0) const _RowRule(),
                    _ProjectTile(project: project),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rule between two rows of a grouped list: the outline's ink on paper,
/// a cut in the page's colour on dark, which draws no light lines.
class _RowRule extends StatelessWidget {
  const _RowRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: appRuleWidth(context),
      child: ColoredBox(color: appRuleColor(context)),
    );
  }
}

/// One project, as a row of the library's grouped list.
///
/// Everything needed to choose between two similar recordings is on the face of
/// it — when it was imported, how long it runs, what it costs on disk — because
/// the alternative is opening each one to find out.
class _ProjectTile extends ConsumerStatefulWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  ConsumerState<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends ConsumerState<_ProjectTile> {
  /// Whether the row is currently under a finger.
  ///
  /// Nothing here stays "selected" the way a segment or a speaker chip does —
  /// a tap navigates away immediately — so the pressed look is momentary,
  /// driven by `InkWell.onHighlightChanged` rather than a persisted choice.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;
    // Null while the directory is still being measured, so the meta line shows
    // what it knows rather than flashing a placeholder size.
    final bytes =
        ref.watch(projectMediaBytesProvider(widget.project.id)).value;
    final duration = ref.watch(projectDurationProvider(widget.project.id));

    // A row of the grouped list: no outline or shadow of its own -- the box
    // round the list has those -- but it still sinks under the finger.
    return PressableSurface(
      selected: _pressed,
      fill: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        borderRadius: surface.borderRadius,
        // The press itself is `PressableSurface`'s job -- the row sinking in
        // already says "tapped", so Material's own splash/highlight overlay
        // is switched off rather than layering a second, conflicting kind of
        // feedback on top.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () => _open(context),
        // Long-press still reaches the same menu, so the gesture people
        // learned before the button existed keeps working.
        onLongPress: () => _showActions(context, ref, l10n, bytes),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // A square outlined tile for the icon, as the reference's rows.
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: surface.decoration(
                  fill: theme.colorScheme.surface,
                ),
                child: const Icon(Icons.movie_outlined, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.project.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // One line, ellipsised: three facts of wildly different
                    // lengths, and a wrap would make neighbouring rows
                    // different heights for no gain.
                    Text(
                      _meta(l10n, bytes, duration),
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
      ),
    );
  }

  /// Created date, running time and size on disk, in that order — oldest fact
  /// first, because it is what distinguishes two imports of the same clip.
  String _meta(AppLocalizations l10n, int? bytes, Duration duration) {
    return [
      l10n.projectCreated(widget.project.createdAt),
      // Summed across clips rather than read off the project row, which has
      // held nothing since schema 5. Omitted at zero: a project with no media
      // yet would otherwise advertise a running time of 00:00.
      if (duration > Duration.zero) _formatDuration(duration),
      if (bytes != null) _formatBytes(l10n, bytes),
    ].join('  \u00b7  ');
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(projectId: widget.project.id),
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
                  widget.project.title,
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
        builder: (dialogContext) => AppDialog(
          title: l10n.duplicateSharesMediaTitle,
          content: Text(l10n.duplicateSharesMediaBody),
          actions: [
            AppDialogAction(
              label: l10n.gotItAction,
              emphasis: AppDialogEmphasis.primary,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      await ref.read(appDatabaseProvider).writeSetting(_sharedMediaHintKey, 'seen');
    }

    await repository.duplicateProject(
      projectId: widget.project.id,
      title: l10n.duplicateTitle(widget.project.title),
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
      builder: (dialogContext) => AppDialog(
        title: l10n.deleteProjectTitle,
        content: Text(
          l10n.deleteProjectMessage(_formatBytes(l10n, bytes ?? 0)),
        ),
        actions: [
          // Red, and the only place in the app that is: this hard-deletes the
          // imported media, which is the one action here that cannot be undone.
          AppDialogAction(
            label: l10n.deleteAction,
            emphasis: AppDialogEmphasis.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          AppDialogAction(
            label: l10n.editCancel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(transcriptRepositoryProvider)
          .deleteProject(widget.project.id);
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

/// The action colour: every call to action in the app takes it, and the
/// user picks it here, beside Light and Dark, from presets or the spectrum.
///
/// The picker previews under the finger and applies on release, so the whole
/// app repaints once per choice rather than on every frame of a drag.
class _AccentColorControl extends ConsumerWidget {
  const _AccentColorControl();

  /// Presets for an action colour: the default violet first, then hues that
  /// each carry a label -- no white or near-black, which would read as a
  /// disabled or a selected button rather than one to press.
  static const _presets = [
    0xFF9B6CFF,
    0xFF116DD6,
    0xFF00A3A3,
    0xFFFFD93D,
    0xFFFF8A3D,
    0xFFE8485A,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accent =
        ref.watch(accentColorSettingProvider).value ?? AppTheme.defaultAccent;
    final setting = ref.read(accentColorSettingProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsAccentColor,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          // No separate "Default" cell: the default is the first preset,
          // and two cells meaning the same colour was one too many.
          AppColorPicker(
            current: accent.toARGB32(),
            swatches: _presets,
            onChanged: (argb) =>
                argb == null ? setting.reset() : setting.select(Color(argb)),
          ),
        ],
      ),
    );
  }
}

/// The Pro offer, as the export sheet makes it: gone once Pro is owned.
class _ProSettingsRow extends ConsumerWidget {
  const _ProSettingsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proUnlockedProvider).value ?? false;
    if (pro) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: ProOfferRow(onGetPro: () => showProComingSoon(context)),
    );
  }
}

/// App-level settings.
///
/// **Transcription options are deliberately not here.** Model, language,
/// silence skipping and diarization moved to the three places a run actually
/// starts -- creating a project, importing a file, and running a transcribe
/// layer -- because they are decisions about the next run rather than standing
/// app preferences, and a sheet behind the app bar is somewhere you have to
/// already know to look. See `TranscriptionOptions`.
///
/// The theme stays because it genuinely is app-wide and belongs to no run.
class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ThemeModeControl(),
            _AccentColorControl(),
            _ProSettingsRow(),
          ],
        ),
      ),
    );
  }
}
