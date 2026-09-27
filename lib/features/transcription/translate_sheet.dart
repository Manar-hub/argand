import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/translation/translator.dart';
import '../../l10n/app_localizations.dart';
import 'transcript_repository.dart';

/// What the language picker answered.
sealed class TranslationPick {
  const TranslationPick();
}

/// Translate into [code]; its pack is on the device.
class TranslateInto extends TranslationPick {
  const TranslateInto(this.code);
  final String code;
}

/// No translation: "Off" in the Transcribe sheet, "Remove translation" on
/// captions.
class TranslateNone extends TranslationPick {
  const TranslateNone();
}

/// Asks which language to translate into, fetching its pack when it is not
/// on the device yet -- the language list of an offline translator, where
/// what is downloaded is marked and anything else is a tap away.
///
/// [current] is listed first. [noneLabel], when given, adds a first row that
/// answers [TranslateNone]. Null when dismissed.
Future<TranslationPick?> pickTranslationLanguage(
  BuildContext context, {
  String? current,
  String? noneLabel,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<TranslationPick>(
    context: context,
    builder: (context) => AppDialog(
      title: l10n.translateTitle,
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: _LanguageList(current: current, noneLabel: noneLabel),
      ),
      actions: [
        AppDialogAction(
          label: l10n.editCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class _LanguageList extends ConsumerStatefulWidget {
  const _LanguageList({this.current, this.noneLabel});

  final String? current;
  final String? noneLabel;

  @override
  ConsumerState<_LanguageList> createState() => _LanguageListState();
}

class _LanguageListState extends ConsumerState<_LanguageList> {
  /// Which packs are on the device; filled in as the checks come back.
  final Map<String, bool> _downloaded = {};

  /// The pack being fetched, if any. One at a time.
  String? _fetching;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final translator = ref.read(translatorProvider);
    for (final language in translator.languages) {
      final here = await translator.isDownloaded(language.code);
      if (!mounted) return;
      setState(() => _downloaded[language.code] = here);
    }
  }

  Future<void> _pick(TranslationLanguage language) async {
    if (_fetching != null) return;
    if (_downloaded[language.code] != true) {
      setState(() {
        _fetching = language.code;
        _failed = false;
      });
      try {
        await ref.read(translatorProvider).download(language.code);
      } on TranslationException {
        if (mounted) {
          setState(() {
            _fetching = null;
            _failed = true;
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _fetching = null;
        _downloaded[language.code] = true;
      });
    }
    if (mounted) Navigator.of(context).pop(TranslateInto(language.code));
  }

  Future<void> _delete(TranslationLanguage language) async {
    await ref.read(translatorProvider).delete(language.code);
    if (mounted) setState(() => _downloaded[language.code] = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final languages = [...ref.watch(translatorProvider).languages];
    // The last choice first, then what is already here, then the rest.
    int rank(TranslationLanguage l) => l.code == widget.current
        ? 0
        : _downloaded[l.code] == true
            ? 1
            : 2;
    languages.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.translateDownloadFailed,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              if (widget.noneLabel case final none?)
                ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  leading: const Icon(Icons.block),
                  title: Text(none, style: theme.textTheme.titleSmall),
                  onTap: () =>
                      Navigator.of(context).pop(const TranslateNone()),
                ),
              for (final language in languages)
                _row(context, l10n, theme, language),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    TranslationLanguage language,
  ) {
    final here = _downloaded[language.code] == true;
    final fetching = _fetching == language.code;
    final chosen = language.code == widget.current;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: Icon(
        chosen
            ? Icons.check
            : here
                ? Icons.offline_pin_outlined
                : Icons.download_outlined,
        color: chosen ? theme.colorScheme.secondary : null,
      ),
      title: Text(language.name, style: theme.textTheme.titleSmall),
      subtitle: here
          ? null
          : Text(fetching ? l10n.translateDownloading : l10n.translatePackSize),
      trailing: fetching
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : here && language.code != 'en'
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.translateDeletePack,
                  onPressed: () => _delete(language),
                )
              : null,
      onTap: () => _pick(language),
    );
  }
}

/// Translates [transcriptIds] into a language the user picks, beside the
/// transcripts, then says how it went. [hasTranslation] adds "Remove
/// translation" to the list.
///
/// Fetches the transcripts' own language packs too when they are missing --
/// a pack is needed at both ends.
Future<void> translateTranscripts(
  BuildContext context,
  WidgetRef ref, {
  required List<String> transcriptIds,
  bool hasTranslation = false,
}) async {
  if (transcriptIds.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final current = await ref.read(translationTargetProvider.future);
  if (!context.mounted) return;

  final pick = await pickTranslationLanguage(
    context,
    current: current,
    noneLabel: hasTranslation ? l10n.translateRemove : null,
  );
  if (pick == null || !context.mounted) return;

  final repository = ref.read(transcriptRepositoryProvider);
  if (pick is TranslateNone) {
    for (final id in transcriptIds) {
      await repository.removeTranslation(id);
    }
    return;
  }
  final to = (pick as TranslateInto).code;

  final failure = await _withProgress(
    context,
    l10n.translateWorking,
    () => runTranslation(ref, transcriptIds: transcriptIds, to: to),
  );

  final name = ref
      .read(translatorProvider)
      .languages
      .where((language) => language.code == to)
      .firstOrNull
      ?.name;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(
        failure == null
            ? l10n.translateDone(name ?? to)
            : translationFailureMessage(l10n, failure),
      ),
    ));
}

/// Translates [transcriptIds] into [to], fetching any missing source pack
/// first. Returns why it failed, or null when every transcript was
/// translated.
Future<TranslationFailure?> runTranslation(
  WidgetRef ref, {
  required List<String> transcriptIds,
  required String to,
}) async {
  return ref.read(transcriptRepositoryProvider).translateAll(
        transcriptIds: transcriptIds,
        to: to,
        translator: ref.read(translatorProvider),
      );
}

String translationFailureMessage(
  AppLocalizations l10n,
  TranslationFailure failure,
) =>
    switch (failure) {
      TranslationFailure.unsupportedSource => l10n.translateUnsupported,
      TranslationFailure.downloadFailed => l10n.translateDownloadFailed,
      TranslationFailure.failed => l10n.translateFailed,
    };

/// Runs [work] behind a small modal that says what is happening.
Future<T> _withProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AppDialog(
        title: label,
        content: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: LinearProgressIndicator(),
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    navigator.pop();
  }
}
