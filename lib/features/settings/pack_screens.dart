import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/delivery/asset_pack_delivery.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../l10n/app_localizations.dart';
import '../transcription/transcription_options.dart';
import 'asset_packs_controller.dart';

/// Settings -> Transcription models: every model this build ships, which are on
/// the device, and which one transcription runs with.
class ModelPacksScreen extends ConsumerWidget {
  const ModelPacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(modelPacksProvider);
    final progress = ref.watch(assetPackProgressProvider);
    final selected = ref.watch(selectedWhisperModelProvider).value;

    return _PackScaffold(
      title: l10n.settingsModels,
      note: l10n.modelsNoteShort,
      rows: entries.whenData(
        (list) => [
          for (final entry in list)
            _PackRow(
              title: whisperModelLabel(l10n, entry.model),
              progress: progress[entry.pack.name],
              status: _modelStatus(l10n, entry),
              installed: entry.installed,
              removable: entry.pack.mode == AssetPackMode.onDemand,
              pack: entry.pack,
              downloadBody: l10n.packDownloadModelBody,
              active: entry.ready && selected == entry.model,
              onSelect: entry.ready
                  ? () => ref
                      .read(selectedWhisperModelProvider.notifier)
                      .select(entry.model)
                  : null,
            ),
        ],
      ),
    );
  }

  static String _modelStatus(AppLocalizations l10n, ModelPackEntry entry) {
    if (!entry.installed) return l10n.packNotInstalled;
    if (!entry.onDevice) return l10n.packBuiltIn;
    final info = entry.info;
    if (info == null) return l10n.modelNotLoadable;
    final size = entry.sizeBytes;
    return l10n.modelReady(
      [
        info.size,
        ?info.format,
        l10n.modelLayers(info.audioLayers),
        if (size != null) l10n.packMegabytes((size / 1048576).round().toString()),
      ].join(' · '),
    );
  }
}

/// Settings -> Translation languages: every language the translator offers,
/// downloaded ones first.
class LanguagePacksScreen extends ConsumerWidget {
  const LanguagePacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(languagePacksProvider);
    final progress = ref.watch(assetPackProgressProvider);

    return _PackScaffold(
      title: l10n.settingsLanguages,
      note: l10n.languagesNote,
      rows: entries.whenData(
        (list) => [
          for (final entry in list)
            _PackRow(
              title: entry.language.name,
              progress: progress[entry.pack.name],
              status: !entry.installed
                  ? l10n.packNotInstalled
                  : entry.pack.mode == AssetPackMode.installTime
                      ? l10n.packBuiltIn
                      : l10n.packInstalled,
              installed: entry.installed,
              removable: entry.pack.mode == AssetPackMode.onDemand,
              pack: entry.pack,
              downloadBody: l10n.packDownloadLanguageBody,
            ),
        ],
      ),
    );
  }
}

class _PackScaffold extends StatelessWidget {
  const _PackScaffold({
    required this.title,
    required this.note,
    required this.rows,
  });

  final String title;
  final String note;
  final AsyncValue<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        // Full-bleed: each row carries its own padding, so the model in use
        // is filled edge to edge.
        data: (rows) => ListView(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.xl,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(note, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (i, row) in rows.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: ColoredBox(
                    color: appHairline(theme),
                    child: const SizedBox(height: appHairlineWidth),
                  ),
                ),
              row,
            ],
          ],
        ),
      ),
    );
  }
}

/// One pack: its name, where it stands, and what can be done with it.
class _PackRow extends ConsumerWidget {
  const _PackRow({
    required this.title,
    required this.status,
    required this.installed,
    required this.removable,
    required this.pack,
    required this.downloadBody,
    this.progress,
    this.active = false,
    this.onSelect,
  });

  final String title;
  final String status;
  final bool installed;
  final bool removable;
  final AssetPack pack;

  /// What the download prompt says about this kind of pack.
  final String downloadBody;

  /// A fetch under way or just failed; null otherwise.
  final AssetPackState? progress;

  /// The model in use.
  final bool active;

  /// Chooses this pack, for a model that can run; null for anything else.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(assetPackProgressProvider.notifier);
    final progress = this.progress;
    final busy = progress?.busy ?? false;
    final failed = progress?.status == AssetPackStatus.failed;
    final ink = active ? theme.colorScheme.onSecondary : null;

    final line = switch (progress?.status) {
      AssetPackStatus.pending => l10n.packWaiting,
      AssetPackStatus.downloading => progress!.fraction == null
          ? l10n.packDownloadingUnknown
          : l10n.packDownloading((progress.fraction! * 100).round()),
      AssetPackStatus.transferring => l10n.packInstalling,
      AssetPackStatus.failed => l10n.packFailed,
      _ => status,
    };

    void download() => _confirmDownload(context, controller);

    final actions = <Widget>[
      if (!installed && !busy)
        AppRaised(
          child: FilledButton(onPressed: download, child: Text(l10n.packAdd)),
        ),
      if (installed && removable && !active)
        IconButton(
          tooltip: l10n.packRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmRemove(context, controller),
        ),
    ];

    final VoidCallback? onTap = installed
        ? (active ? null : onSelect)
        : (busy ? null : download);

    return Semantics(
      selected: active,
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          color: active ? theme.colorScheme.secondary : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(color: ink),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failed
                            ? theme.colorScheme.error
                            : ink?.withValues(alpha: 0.8),
                      ),
                    ),
                    if (busy) ...[
                      const SizedBox(height: AppSpacing.xs),
                      LinearProgressIndicator(
                        value: progress!.fraction,
                        minHeight: 4,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDownload(
    BuildContext context,
    AssetPackProgress controller,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.packDownloadTitle(title),
        content: Text(downloadBody),
        actions: [
          AppDialogAction(
            label: l10n.packDownload,
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
    if (confirmed ?? false) await controller.fetch(pack);
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AssetPackProgress controller,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.packRemoveTitle(title),
        content: Text(l10n.packRemoveBody),
        actions: [
          AppDialogAction(
            label: l10n.packRemove,
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
    if (confirmed ?? false) await controller.remove(pack);
  }
}
