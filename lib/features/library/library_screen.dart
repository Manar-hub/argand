import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
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
        // Disabled mid-import: every setting behind this button changes what a
        // later stage of the running pipeline would do -- which weights load,
        // which language is declared, whether silence is skipped, whether
        // speakers are labelled.
        actions: [_SettingsButton(enabled: import is! ImportRunning)],
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
      ImportStage.identifyingSpeakers => percent == null
          ? l10n.stageIdentifyingSpeakers
          : l10n.identifyingSpeakersPercent(percent),
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
          padding: const EdgeInsets.only(bottom: 16),
          children: [
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
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
    return ListTile(
      leading: Icon(selected ? Icons.check : Icons.radio_button_unchecked),
      title: Text(title),
      subtitle: Text(subtitle),
      selected: selected,
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
