import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diarization/diarization_controller.dart';
import '../../core/theme/app_controls.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/translation/translator.dart';
import '../../core/whisper/transcription_language_controller.dart';
import '../../core/whisper/vad_controller.dart';
import '../../core/whisper/whisper_model_catalog.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../l10n/app_localizations.dart';
import '../settings/pack_screens.dart';
import 'translate_sheet.dart';

/// The choices that shape a transcription run: model, language, silence
/// skipping and diarization.
class TranscriptionOptions extends ConsumerWidget {
  const TranscriptionOptions({super.key, this.dense = false});

  /// Trims the padding for use inside a dialog, where a sheet's breathing room
  /// pushes the buttons off a short screen.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final models = ref.watch(availableWhisperModelsProvider).value ?? const [];
    final selectedModel = ref.watch(selectedWhisperModelProvider).value;
    final language = ref.watch(selectedTranscriptionLanguageProvider).value;
    final skipSilence = ref.watch(silenceSkippingEnabledProvider).value;
    final diarize = ref.watch(speakerDiarizationEnabledProvider).value;
    final translateTo = ref.watch(translationTargetProvider).value;
    final translateName = translateTo == null
        ? l10n.translateOff
        : ref
                .watch(translatorProvider)
                .languages
                .where((language) => language.code == translateTo)
                .firstOrNull
                ?.name ??
            translateTo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always shown, even with one model on the device: it used to hide
        // below two, so once Small became a download the choice vanished from
        // where a run starts.
        _SectionHeader(label: l10n.transcriptionModelTitle, dense: dense),
        for (final model in models)
          _ChoiceTile(
            dense: dense,
            selected: model == selectedModel,
            title: whisperModelLabel(l10n, model),
            onTap: () =>
                ref.read(selectedWhisperModelProvider.notifier).select(model),
          ),
        ListTile(
          dense: dense,
          contentPadding: dense
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
              : null,
          leading: const Icon(Icons.download_outlined),
          title: Text(
            l10n.transcriptionMoreModels,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: const Icon(Icons.chevron_right),
          // The same page as Settings' -- a model added there is chosen
          // here on the way back.
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const ModelPacksScreen()),
          ),
        ),
        const Divider(),
        _SectionHeader(label: l10n.transcriptionLanguageTitle, dense: dense),
        for (final option in TranscriptionLanguage.values)
          _ChoiceTile(
            dense: dense,
            selected: option == language,
            title: _languageLabel(l10n, option),
            onTap: () => ref
                .read(selectedTranscriptionLanguageProvider.notifier)
                .select(option),
          ),
        // Also translate what comes back, beside the transcription. Off
        // unless chosen; the choice carries to the next run like the rest.
        ListTile(
          dense: dense,
          contentPadding: dense
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
              : null,
          leading: const Icon(Icons.translate),
          title: Text(
            l10n.translateToOption,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(translateName),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () async {
            final pick = await pickTranslationLanguage(
              context,
              current: translateTo,
              noneLabel: l10n.translateOff,
            );
            final target = ref.read(translationTargetProvider.notifier);
            switch (pick) {
              case TranslateInto(:final code):
                await target.select(code);
              case TranslateNone():
                await target.select(null);
              case null:
                break;
            }
          },
        ),
        const Divider(),
        _ToggleTile(
          dense: dense,
          // Falls back to the declared default only for the instant before
          // the stored value has been read; `onChanged` stays null until
          // then so a tap cannot race the load and write the wrong value.
          value: skipSilence ?? SilenceSkippingEnabled.defaultEnabled,
          title: l10n.silenceSkippingTitle,
          subtitle: l10n.silenceSkippingHint,
          onChanged: skipSilence == null
              ? null
              : (value) => ref
                  .read(silenceSkippingEnabledProvider.notifier)
                  .setEnabled(value),
        ),
        _ToggleTile(
          dense: dense,
          value: diarize ?? SpeakerDiarizationEnabled.defaultEnabled,
          title: l10n.diarizationTitle,
          subtitle: l10n.diarizationHint,
          onChanged: diarize == null
              ? null
              : (value) => ref
                  .read(speakerDiarizationEnabledProvider.notifier)
                  .setEnabled(value),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.dense = false});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        dense ? AppSpacing.xs : AppSpacing.lg,
        AppSpacing.md,
        dense ? AppSpacing.xs : AppSpacing.lg,
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
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.dense = false,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // `ListTile.selected` tints the whole row with the primary colour, which
    // for a fill colour like yellow means unreadable text.
    return ListTile(
      dense: dense,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
          : null,
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
      onTap: onTap,
    );
  }
}

/// Localized name for a known model, falling back to its raw id.
String whisperModelLabel(AppLocalizations l10n, WhisperModelDescriptor model) {
  return switch (model.id) {
    'base' => l10n.modelNameBase,
    'small-q5_1' => l10n.modelNameSmallQ51,
    _ => readableModelId(model.id),
  };
}

/// A model dropped into the folder, named from its id: the size first, as
/// the named models read, then whatever else the filename says --
/// `medium-q4_0` -> `Medium (q4_0)`.
String readableModelId(String id) {
  final dash = id.indexOf('-');
  final size = dash < 0 ? id : id.substring(0, dash);
  final rest = dash < 0 ? '' : id.substring(dash + 1);
  if (size.isEmpty) return id;
  final name = '${size[0].toUpperCase()}${size.substring(1)}';
  return rest.isEmpty ? name : '$name ($rest)';
}

/// Exhaustive over [TranscriptionLanguage] rather than falling back to the
/// code, unlike the model labels above: this enum is closed and every entry is
/// one this build deliberately offers.
String _languageLabel(AppLocalizations l10n, TranscriptionLanguage language) {
  return switch (language) {
    TranscriptionLanguage.auto => l10n.languageAuto,
    TranscriptionLanguage.english => l10n.languageEnglish,
  };
}

/// Asks for the transcription choices before a run starts.
Future<bool> showTranscriptionOptions(
  BuildContext context, {
  String? warning,
  TextEditingController? name,
}) async {
  final l10n = AppLocalizations.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: l10n.transcribeOptionsTitle,
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (warning != null) ...[
                Text(
                  warning,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const TranscriptionOptions(dense: true),
              // A new project's name, last: the file's name when left empty.
              if (name != null) ...[
                _SectionHeader(label: l10n.transcribeNameTitle, dense: true),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: TextField(
                    controller: name,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: l10n.transcribeNameHint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppDialogAction(
          label: l10n.transcribeOptionsConfirm,
          emphasis: AppDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        AppDialogAction(
          label: l10n.editCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );

  return confirmed == true;
}

/// A setting that is on or off: the whole row toggles it, with the square
/// `AppToggle` in place of Material's pill switch.
class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.dense,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final bool dense;
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return MergeSemantics(
      child: ListTile(
        dense: dense,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: AppToggle(value: value, onChanged: onChanged),
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged(!value),
      ),
    );
  }
}
