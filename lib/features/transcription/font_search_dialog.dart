import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fonts/custom_fonts.dart';
import '../../core/monetization/monetization.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_shine.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../core/timeline/item_look.dart';
import '../../l10n/app_localizations.dart';
import '../monetization/pro_screen.dart';

/// Every font, searchable, with adding your own at the top (Pro). Comes back
/// with the edit that applies the chosen one, or null when nothing was.
Future<ItemLook Function(ItemLook)?> showFontSearch(
  BuildContext context, {
  required ItemLook current,
}) =>
    showDialog<ItemLook Function(ItemLook)>(
      context: context,
      builder: (_) => _FontSearch(current: current),
    );

/// One font in the list.
typedef _Entry = ({
  String label,
  String family,
  bool selected,
  ItemLook Function(ItemLook) apply,
});

class _FontSearch extends ConsumerStatefulWidget {
  const _FontSearch({required this.current});

  final ItemLook current;

  @override
  ConsumerState<_FontSearch> createState() => _FontSearchState();
}

class _FontSearchState extends ConsumerState<_FontSearch> {
  final _query = TextEditingController();
  bool _adding = false;
  String? _note;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _addFont(AppLocalizations l10n, {required bool pro}) async {
    if (!pro) {
      await showProScreen(context);
      return;
    }
    setState(() {
      _adding = true;
      _note = null;
    });
    // Any file: Android filters fonts by type unreliably, so the extension
    // is checked here instead.
    final picked = await FilePicker.pickFile(type: FileType.any);
    CustomFont? font;
    if (picked != null) {
      font = await ref.read(customFontsProvider.notifier).add(
            fileName: picked.name,
            bytes: await picked.readAsBytes(),
          );
    }
    if (!mounted) return;
    setState(() {
      _adding = false;
      _note = picked != null && font == null ? l10n.fontSearchNotAFont : null;
    });
    // Added and chosen in one go.
    if (font != null) {
      final id = font.id;
      Navigator.of(context).pop((ItemLook look) => look.copyWith(customFont: id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pro = ref.watch(proUnlockedProvider).value ?? false;
    final custom = ref.watch(customFontsProvider).value ?? const [];
    final current = widget.current;

    final entries = <_Entry>[
      for (final font in LookFont.values)
        (
          label: font.label,
          family: font.drawFamily,
          selected: current.customFont == null && current.font == font,
          apply: (look) => look.copyWith(font: font),
        ),
      for (final font in custom)
        (
          label: font.name,
          family: font.family,
          selected: current.customFont == font.id,
          apply: (look) => look.copyWith(customFont: font.id),
        ),
    ];

    return AppDialog(
      title: l10n.fontSearchTitle,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.fontSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _note!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _FontList(
              add: _AddFontRow(
                label: _adding ? l10n.fontSearchAdding : l10n.fontSearchAdd,
                pro: pro,
                onTap: _adding ? null : () => _addFont(l10n, pro: pro),
              ),
              entries: [
                for (final entry in entries)
                  if (entry.label
                      .toLowerCase()
                      .contains(_query.text.trim().toLowerCase()))
                    entry,
              ],
              emptyLabel: l10n.fontSearchNone,
              onPick: (entry) => Navigator.of(context).pop(entry.apply),
            ),
          ],
        ),
      ),
      actions: [
        AppDialogAction(
          label: l10n.editCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Adding a font, as the list's first row: gold words and a glint while it
/// is a Pro feature not yet owned, a plain row once it is.
class _AddFontRow extends StatelessWidget {
  const _AddFontRow({
    required this.label,
    required this.pro,
    required this.onTap,
  });

  final String label;
  final bool pro;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = pro
        ? theme.colorScheme.onSurface
        : AppTheme.proGoldText(theme.brightness);

    final row = Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _FontList.rowHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: ink),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return pro ? row : AppShine(color: AppTheme.proGold, child: row);
  }
}

/// The fonts in one outlined box, ruled between, each named in itself; the
/// chosen one filled with the action colour. Adding one comes first.
class _FontList extends StatefulWidget {
  const _FontList({
    required this.add,
    required this.entries,
    required this.emptyLabel,
    required this.onPick,
  });

  final Widget add;
  final List<_Entry> entries;
  final String emptyLabel;
  final ValueChanged<_Entry> onPick;

  /// Short, but a comfortable thumb target.
  static const double rowHeight = 44;

  @override
  State<_FontList> createState() => _FontListState();
}

class _FontListState extends State<_FontList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final entries = widget.entries;
    final rule = surface.outlined
        ? surface.outline
        : theme.colorScheme.onSurface.withValues(alpha: 0.12);
    // Six rows and a part of the next, so the list reads as one that goes on;
    // less on a short screen.
    final height = math.min(
      _FontList.rowHeight * 6.5,
      MediaQuery.sizeOf(context).height * 0.36,
    );

    Widget fontRow(_Entry entry) {
      final ink = entry.selected
          ? theme.colorScheme.onSecondary
          : theme.colorScheme.onSurface;
      return Semantics(
        selected: entry.selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onPick(entry),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: _FontList.rowHeight,
            color: entry.selected
                ? theme.colorScheme.secondary
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.centerLeft,
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: entry.family, fontSize: 18, color: ink),
            ),
          ),
        ),
      );
    }

    final rows = <Widget>[
      widget.add,
      if (entries.isEmpty)
        SizedBox(
          height: _FontList.rowHeight,
          child: Center(
            child: Text(
              widget.emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      for (final entry in entries) fontRow(entry),
    ];

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: surface.outlined
            ? null
            : theme.colorScheme.surfaceContainerHighest,
        border: surface.border,
      ),
      // A thin bar that is always there, so the list is seen to go on: the
      // outline's ink, no track, square like everything else.
      child: RawScrollbar(
        controller: _scroll,
        thumbVisibility: true,
        thickness: 3,
        radius: Radius.zero,
        crossAxisMargin: 2,
        mainAxisMargin: 2,
        thumbColor: theme.colorScheme.onSurface.withValues(alpha: 0.35),
        child: ListView.separated(
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, _) => ColoredBox(
            color: rule,
            child: const SizedBox(height: 1.5, width: double.infinity),
          ),
          itemBuilder: (_, index) => rows[index],
        ),
      ),
    );
  }
}
