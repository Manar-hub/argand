import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/whisper/whisper_model_catalog.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../l10n/app_localizations.dart';
import '../transcription/import_controller.dart';
import '../transcription/project_screen.dart';
import '../transcription/transcript_repository.dart';

/// Landing screen: every imported project, plus the entry point for a new
/// import.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // Disabled mid-import: switching models underneath a running
        // transcription would change which weights the next stage loads.
        actions: [_ModelMenu(enabled: import is! ImportRunning)],
      ),
      body: Column(
        children: [
          if (import is ImportRunning) _ImportProgress(status: import),
          if (import is ImportFailed) _ImportError(error: import.error),
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ImportError(error: error),
              data: (items) => items.isEmpty
                  ? const _EmptyLibrary()
                  : _ProjectList(projects: items),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy
            ? null
            : () => ref.read(importControllerProvider.notifier).importFromPicker(),
        icon: const Icon(Icons.add),
        label: Text(l10n.importAction),
      ),
    );
  }
}

class _ProjectList extends ConsumerWidget {
  const _ProjectList({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      // Clears the floating action button so the last tile is never covered.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return _ProjectTile(project: project);
      },
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ListTile(
      leading: const Icon(Icons.movie_outlined),
      // Imported filenames are arbitrary and often long, so the title is
      // clipped rather than allowed to push the layout sideways.
      title: Text(project.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: project.durationMs == null
          ? null
          : Text(_formatDuration(Duration(milliseconds: project.durationMs!))),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProjectScreen(projectId: project.id),
        ),
      ),
      // Secondary action behind a long-press rather than a row of icons --
      // see the gesture note in docs/build-roadmap.md, Tier 1.
      onLongPress: () async {
        final confirmed = await showModalBottomSheet<bool>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.deleteAction),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ),
        );
        if (confirmed ?? false) {
          await ref.read(transcriptRepositoryProvider).softDeleteProject(project.id);
        }
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Scrollable so the copy still reaches the user on a short screen or at a
    // large accessibility text scale instead of overflowing.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 24),
          Text(
            l10n.libraryEmptyTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
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
      ImportStage.saving => l10n.stageSaving,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            // Only the transcription stage knows how far along it is; the
            // rest animate indeterminately rather than faking a number.
            value: status.stage == ImportStage.transcribing && percent != null
                ? percent / 100
                : null,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.errorTitle,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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

/// App-bar menu for choosing which model transcribes.
///
/// Lists whatever models this build actually ships (see
/// [WhisperModelCatalog]); it is not a hardcoded pair, so adding a `.bin` to
/// `assets/models/` makes it appear here with no change to this widget.
class _ModelMenu extends ConsumerWidget {
  const _ModelMenu({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final models = ref.watch(availableWhisperModelsProvider).value ?? const [];
    final selected = ref.watch(selectedWhisperModelProvider).value;

    // A picker over fewer than two options is just clutter.
    if (models.length < 2) return const SizedBox.shrink();

    return PopupMenuButton<WhisperModelDescriptor>(
      enabled: enabled,
      icon: const Icon(Icons.tune),
      tooltip: l10n.transcriptionModelTitle,
      onSelected: (model) async {
        await ref.read(selectedWhisperModelProvider.notifier).select(model);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(l10n.modelSwitched(_labelFor(l10n, model)))),
          );
      },
      itemBuilder: (context) => [
        PopupMenuItem<WhisperModelDescriptor>(
          enabled: false,
          child: Text(
            l10n.transcriptionModelTitle,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const PopupMenuDivider(),
        for (final model in models)
          PopupMenuItem<WhisperModelDescriptor>(
            value: model,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                model == selected ? Icons.check : Icons.radio_button_unchecked,
              ),
              title: Text(_labelFor(l10n, model)),
              subtitle: Text(_hintFor(l10n, model)),
            ),
          ),
      ],
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
