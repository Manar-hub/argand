import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/media/shared_media.dart';
import '../../core/monetization/monetization.dart';
import '../../core/monetization/purchases.dart';
import '../../core/theme/accent_color_controller.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_color_picker.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/argand_logo.dart';
import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../core/theme/theme_reveal.dart';
import '../../core/text/library_search.dart';
import '../../l10n/app_localizations.dart';
import '../monetization/pro_offer.dart';
import '../monetization/pro_screen.dart';
import '../settings/pack_screens.dart';
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

  /// What the search field asks for, settled: it follows the typing after a
  /// short pause, so a search runs per thought rather than per keystroke.
  String _query = '';
  Timer? _queryDebounce;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// The last results shown, kept while the next query's first answer is on
  /// its way so the list does not blink empty between keystrokes.
  List<LibraryHit>? _lastHits;

  void _onSearchChanged(String text) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = text);
    });
  }

  void _clearSearch() {
    _queryDebounce?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  /// Which mode the entry button just tapped wants the resulting project to
  /// open in, consumed the moment the pipeline reports [ImportSucceeded].
  EditorMode? _pendingImportMode;

  @override
  void initState() {
    super.initState();

    // Media sent here from the system Sharesheet, arriving two ways.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final channel = ref.read(sharedMediaChannelProvider);
      _shares = channel.shares().listen(_importShared);

      final initial = await channel.initialShare();
      if (initial != null) _importShared(initial);
    });
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
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
        // The logo in place of the name, its hand in the action colour.
        // Long-pressed in a Test Store build, it resets Pro for another take.
        title: GestureDetector(
          onLongPress: proResettable ? () => _resetPro(l10n) : null,
          child: ArgandLogo(semanticLabel: l10n.appTitle),
        ),
        // Disabled mid-import: every setting behind this button changes what a
        // later stage of the running pipeline would do -- which weights load,
        // which language is declared, whether silence is skipped.
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
                  const SizedBox(height: AppSpacing.md),
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
                : SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _ProjectsHeading(
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          onClear: _clearSearch,
                        ),
                      ),
                      _results(items, l10n),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Every project, or -- while the search field holds something -- the ones
/// it finds, each with the line of its transcript that matched.
extension on _LibraryScreenState {
  /// Hidden, and only in builds on RevenueCat's Test Store: turns Pro off
  /// as a new customer, so a demo or a purchase test can run again.
  Future<void> _resetPro(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.proResetTitle,
        content: Text(l10n.proResetBody),
        actions: [
          AppDialogAction(
            label: l10n.proResetAction,
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
    try {
      await ref.read(proPurchasesProvider).resetForTesting();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.proResetDone)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.proResetFailed)));
    }
  }

  Widget _results(List<Project> items, AppLocalizations l10n) {
    if (searchTokens(_query).isEmpty) {
      _lastHits = null;
      return _ProjectSliver(entries: [for (final p in items) (p, null)]);
    }

    final hits = ref.watch(librarySearchProvider(_query)).value ?? _lastHits;
    if (hits == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    _lastHits = hits;

    if (hits.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: Text(
            l10n.librarySearchEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return _ProjectSliver(
      entries: [for (final hit in hits) (hit.project, hit.word)],
    );
  }
}

/// "Projects", large, with the search field beside it.
class _ProjectsHeading extends StatelessWidget {
  const _ProjectsHeading({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = context.surface;

    // The search button's grey: the page's ink laid thinly over its ground,
    // so it is the palette's own -- warm on paper, lifted on dark.
    final grey = Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.light ? 0.07 : 0.10,
      ),
      theme.colorScheme.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A faint rule between the two things this page does -- start
        // something new, above; find what exists, below -- set in from the
        // screen's edges so it separates without cutting the page in two.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            0,
          ),
          child: SizedBox(
            height: appHairlineWidth,
            child: ColoredBox(color: appHairline(theme)),
          ),
        ),
        Padding(
          // Below the rule, and clear of the list by more than the field's
          // shadow, so the shadow does not crowd the first project.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Row(
            children: [
              // Smaller than the panels above: finding what exists is the
              // page's second job. Heading, field and button shrink together.
              Text(
                l10n.projectsHeading,
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                // The field on the page's own ground, raised with the hard
                // shadow; the search icon in a grey box of its own at the end.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: surface.outlined
                        ? Border.fromBorderSide(surface.side)
                        : null,
                    boxShadow: [surface.hardShadow],
                  ),
                  // Inside the outline, so the grey button never paints over it.
                  child: Padding(
                    padding: EdgeInsets.all(
                      surface.outlined ? surface.borderWidth : 0,
                    ),
                    child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: onChanged,
                            textInputAction: TextInputAction.search,
                            // Tapping anywhere else leaves the field and puts
                            // the keyboard away; what was found stays listed
                            // until cleared.
                            onTapOutside: (_) => focusNode.unfocus(),
                            textAlignVertical: TextAlignVertical.center,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: l10n.librarySearchHint,
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm + AppSpacing.xxs,
                              ),
                            ),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: l10n.librarySearchClear,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: onClear,
                                ),
                        ),
                        // The search button: a grey square flush with the
                        // field's end, set off by the field's own line.
                        AppPushIn(
                          face: grey,
                          clip: false,
                          travel: surface.offset +
                              Offset(surface.borderWidth, surface.borderWidth),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: focusNode.requestFocus,
                            child: Container(
                              width: 40,
                              decoration: BoxDecoration(
                                border: surface.outlined
                                    ? Border(left: surface.side)
                                    : null,
                              ),
                              child: Icon(
                                Icons.search,
                                size: 18,
                                semanticLabel: l10n.librarySearchHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks for a new project's name before it is created.
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
      // No transcription options here. This creates an empty project and
      // transcribes nothing -- media is added afterwards and run separately --
      // so there is no run for those choices to apply to.
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
      // An action, so it stands on the hard shadow and lands on it when
      // pressed, as every action button does (`AppRaised`).
      child: AppRaised(
        child: InkWell(
          borderRadius: surface.borderRadius,
          // The card moving is the feedback; no ripple on top of it.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: busy ? null : onTap,
          child: Container(
            // Tall: with the logo, these are what the page is about, so they
            // outweigh the project list below. Icon and type grow with them.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl + AppSpacing.xs,
            ),
            decoration: surface.decoration(
              fill: busy
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.primary,
            ),
            child: Row(
              children: [
                Icon(icon, size: 36, color: ink),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: ink, fontSize: 20),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subhead,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.withValues(alpha: 0.75),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The project list: each project, with where a search found it in its words
/// when one did.
class _ProjectSliver extends StatelessWidget {
  const _ProjectSliver({required this.entries});

  final List<(Project, LibraryWordHit?)> entries;

  @override
  Widget build(BuildContext context) {
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
                  for (final (index, (project, hit)) in entries.indexed) ...[
                    if (index > 0) const _RowRule(),
                    _ProjectTile(
                      key: ValueKey(project.id),
                      project: project,
                      hit: hit,
                    ),
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
class _ProjectTile extends ConsumerStatefulWidget {
  const _ProjectTile({super.key, required this.project, this.hit});

  final Project project;

  /// Where a search found this project's words, shown under its title and
  /// opened on when tapped.
  final LibraryWordHit? hit;

  @override
  ConsumerState<_ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends ConsumerState<_ProjectTile> {
  /// Whether the row is currently under a finger.
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
        // already says "tapped", so Material's own splash/highlight overlay is
        // switched off rather than layering a second.
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
                    if (widget.hit case final hit?) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _Snippet(hit: hit),
                    ],
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
    final hit = widget.hit;
    final clipId = hit?.clipId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(
          projectId: widget.project.id,
          // A search that found the words opens on them.
          initialSeek: hit == null || clipId == null
              ? null
              : (clipId: clipId, startMs: hit.startMs),
        ),
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
      ImportStage.translating => l10n.translateWorking,
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
            // number.
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
            child: AppPressDown(
              child: TextButton(
                onPressed: () =>
                    ref.read(importControllerProvider.notifier).reset(),
                child: Text(l10n.retryAction),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line of a transcript a search matched: when it is said, then the words
/// around it with the match in bold.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.hit});

  final LibraryWordHit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final end = hit.matchStart + hit.matchLength;
    String join(Iterable<String> words) => words.join(' ');

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: '${_formatDuration(Duration(milliseconds: hit.startMs))}  ',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (hit.matchStart > 0)
            TextSpan(text: '\u2026${join(hit.snippet.take(hit.matchStart))} '),
          TextSpan(
            text: join(hit.snippet.sublist(hit.matchStart, end)),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (end < hit.snippet.length)
            TextSpan(text: ' ${join(hit.snippet.skip(end))}\u2026'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// A byte count at the largest unit that leaves a readable number.
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
      icon: const AppIcon(AppGlyph.settings),
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

/// Everything that changes what the *next* import does: which model runs, which
/// language the engine is told to expect, whether non-speech audio is skipped,
/// and whether speakers are labelled.
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

/// The action colour: every call to action in the app takes it, and the user
/// picks it here, beside Light and Dark, from presets or the spectrum.
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

/// The Pro offer, as one big gold button with the pitch written on it: gone
/// once Pro is owned.
class _ProSettingsRow extends ConsumerWidget {
  const _ProSettingsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proUnlockedProvider).value ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      // Bought: a thank-you in place of the offer.
      child: pro
          ? SupporterBadge(onPressed: () => showProScreen(context))
          : ProBanner(onPressed: () => showProScreen(context)),
    );
  }
}

enum _SettingsPage { models, languages }

/// A settings row that opens a page of its own: the model and language pack
/// managers, which are lists too long for the sheet.
class _SettingsLink extends StatelessWidget {
  const _SettingsLink({required this.kind});

  final _SettingsPage kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, detail, page) = switch (kind) {
      _SettingsPage.models => (
          l10n.settingsModels,
          l10n.settingsModelsDetail,
          const ModelPacksScreen(),
        ),
      _SettingsPage.languages => (
          l10n.settingsLanguages,
          l10n.settingsLanguagesDetail,
          const LanguagePacksScreen(),
        ),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      title: Text(title),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      // A plain swipe in from the side, and back with an edge drag.
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(builder: (_) => page),
      ),
    );
  }
}

/// App-level settings.
class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A modal route keeps the theme it was opened under, so without this the
    // sheet's own selections would stay in the old action colour while the
    // user picks a new one right here.
    final theme = Theme.of(context);
    final accent = ref.watch(accentColorSettingProvider).value;
    return Theme(
      data: accent == null
          ? theme
          : theme.brightness == Brightness.dark
              ? AppTheme.dark(accent: accent)
              : AppTheme.light(accent: accent),
      child: const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThemeModeControl(),
              _AccentColorControl(),
              _SettingsLink(kind: _SettingsPage.models),
              _SettingsLink(kind: _SettingsPage.languages),
              _ProSettingsRow(),
            ],
          ),
        ),
      ),
    );
  }
}
