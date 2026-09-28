import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/database.dart';
import '../../core/theme/app_color_picker.dart';
import '../../core/theme/app_panel_cells.dart';
import '../../core/theme/app_segment_row.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/timeline_selection.dart';
import '../../core/timeline/timeline_sentences.dart';
import '../../l10n/app_localizations.dart';
import 'clip_controller.dart';
import 'timeline_history.dart';
import 'transcript_repository.dart';

part 'style_panel.g.dart';

/// How a sentence looks: its own look, else its layer's, else the default.
@riverpod
Future<ItemLook> sentenceLook(Ref ref, String projectId, String sentenceId) {
  final sentence = sentenceOf(
    (kind: TimelineItemKind.sentence, id: sentenceId),
  );
  if (sentence == null) return Future.value(ItemLook.defaults);

  final words =
      ref.watch(transcriptWordsProvider(sentence.transcriptId)).value ??
          const <Word>[];
  ref.watch(projectLayersProvider(projectId));
  final own = words
      .where((w) => w.position == sentence.fromPosition)
      .firstOrNull
      ?.ownLook;
  if (own != null) return Future.value(own);

  return ref
      .read(transcriptRepositoryProvider)
      .layerLookOfTranscript(sentence.transcriptId)
      .then((look) => look ?? ItemLook.defaults);
}

/// The panel's items: what about the look is being changed.
enum _StyleItem { font, color, shadow, mode, highlight }

/// What a change reaches: what is selected, everything its speakers say, or
/// every caption.
enum _StyleScope { selected, speaker, all }

/// Font, colours, shadow and caption style for what is selected -- one text,
/// several sentences, a whole layer -- or for every caption at once.
class StylePanel extends ConsumerStatefulWidget {
  const StylePanel({super.key, required this.projectId, this.anchor});

  final String projectId;

  /// The toolbar cell that opened the panel -- the toolbar's cell count and
  /// which one -- when the panel sits directly above that toolbar. The panel
  /// then links down to it the same way its own options link to its items.
  final ({int count, int index})? anchor;

  @override
  ConsumerState<StylePanel> createState() => _StylePanelState();
}

class _StylePanelState extends ConsumerState<StylePanel> {
  _StyleItem _item = _StyleItem.font;
  _StyleScope _scope = _StyleScope.selected;

  /// Whether Colour is editing the background rather than the words.
  bool _background = false;

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  /// The selected texts, sentences, translation lines and layers.
  List<TimelineItem> _selected(Set<TimelineItem> selection) => [
        for (final item in selection)
          if (item.kind != TimelineItemKind.clip &&
              item.kind != TimelineItemKind.audio &&
              item.kind != TimelineItemKind.image)
            item,
      ];

  /// Who speaks a sentence or a translation line -- the sentence's first
  /// word's speaker, as its colour is chosen -- or null when undiarized.
  int? _speakerOf(TimelineItem item, List<TimelineSentence> sentences) {
    switch (item.kind) {
      case TimelineItemKind.sentence:
        final at = sentenceOf(item)!;
        return sentences
            .where((s) =>
                s.transcriptId == at.transcriptId &&
                s.fromPosition == at.fromPosition)
            .firstOrNull
            ?.speaker;
      case TimelineItemKind.translation:
        final line = ref
            .read(projectTranslationLinesProvider(widget.projectId))
            .where((l) => l.line.id == item.id)
            .firstOrNull
            ?.line;
        if (line == null) return null;
        return sentences
            .where((s) =>
                s.transcriptId == line.transcriptId &&
                s.fromPosition <= line.firstWord &&
                line.firstWord <= s.toPosition)
            .firstOrNull
            ?.speaker;
      case TimelineItemKind.clip:
      case TimelineItemKind.layer:
      case TimelineItemKind.text:
      case TimelineItemKind.audio:
      case TimelineItemKind.image:
        return null;
    }
  }

  /// What a change reaches, for the scope chosen over [selected].
  List<TimelineItem> _targets(List<TimelineItem> selected, _StyleScope scope) {
    final sentences = ref.read(projectSentencesProvider(widget.projectId));
    final lines = ref.read(projectTranslationLinesProvider(widget.projectId));
    final captions = selected.isEmpty ||
        selected.any((t) =>
            t.kind == TimelineItemKind.sentence ||
            t.kind == TimelineItemKind.layer);
    final translations =
        selected.any((t) => t.kind == TimelineItemKind.translation);

    switch (selected.isEmpty ? _StyleScope.all : scope) {
      case _StyleScope.selected:
        return selected;
      case _StyleScope.speaker:
        final speakers = {
          for (final item in selected)
            if (item.kind == TimelineItemKind.sentence ||
                item.kind == TimelineItemKind.translation)
              _speakerOf(item, sentences),
        };
        final sentencePicked =
            selected.any((t) => t.kind == TimelineItemKind.sentence);
        return [
          if (sentencePicked)
            for (final sentence in sentences)
              if (speakers.contains(sentence.speaker))
                sentenceItem(
                  transcriptId: sentence.transcriptId,
                  fromPosition: sentence.fromPosition,
                  toPosition: sentence.toPosition,
                ),
          if (translations)
            for (final line in lines)
              if (speakers.contains(_speakerOf(
                (kind: TimelineItemKind.translation, id: line.line.id),
                sentences,
              )))
                (kind: TimelineItemKind.translation, id: line.line.id),
        ];
      case _StyleScope.all:
        final layers =
            ref.read(projectLayersProvider(widget.projectId)).value ??
                const [];
        return [
          if (captions)
            for (final layer in layers)
              (kind: TimelineItemKind.layer, id: layer.id),
          if (translations)
            for (final line in lines)
              (kind: TimelineItemKind.translation, id: line.line.id),
        ];
    }
  }

  /// [item]'s own look (null when it has none) and the look it shows.
  Future<({ItemLook? own, ItemLook shown})> _lookOf(TimelineItem item) async {
    final repository = ref.read(transcriptRepositoryProvider);
    switch (item.kind) {
      case TimelineItemKind.text:
        final texts =
            ref.read(projectTextLayersProvider(widget.projectId)).value ??
                const [];
        final own =
            texts.where((t) => t.id == item.id).firstOrNull?.itemLook;
        return (own: own, shown: own ?? ItemLook.defaults);
      case TimelineItemKind.layer:
        final layers =
            ref.read(projectLayersProvider(widget.projectId)).value ??
                const [];
        final own = layers.where((l) => l.id == item.id).firstOrNull?.look;
        return (own: own, shown: own ?? ItemLook.defaults);
      case TimelineItemKind.sentence:
        final sentence = sentenceOf(item)!;
        final own = await repository.sentenceLook(
          transcriptId: sentence.transcriptId,
          fromPosition: sentence.fromPosition,
        );
        final layer =
            await repository.layerLookOfTranscript(sentence.transcriptId);
        return (own: own, shown: own ?? layer ?? ItemLook.defaults);
      case TimelineItemKind.translation:
        final line = await repository.findTranslationLine(item.id);
        final own = ItemLook.decode(line?.look);
        final layer = line == null
            ? null
            : await repository.layerLookOfTranscript(line.transcriptId);
        return (own: own, shown: own ?? layer ?? ItemLook.defaults);
      case TimelineItemKind.clip:
      case TimelineItemKind.audio:
      case TimelineItemKind.image:
        return (own: null, shown: ItemLook.defaults);
    }
  }

  /// Applies [edit] to each target's own look, as one undoable step.
  Future<void> _apply(
    List<TimelineItem> targets,
    bool resetSentences,
    ItemLook Function(ItemLook) edit,
  ) async {
    final changes = <LookChange>[];
    for (final item in targets) {
      final look = await _lookOf(item);
      changes.add((
        kind: item.kind,
        id: item.id,
        before: look.own,
        after: edit(look.shown),
      ));
    }

    // Every caption through its transcription: the sentences' own looks
    // give way to it.
    final transcripts = resetSentences
        ? {
            for (final sentence
                in ref.read(projectSentencesProvider(widget.projectId)))
              sentence.transcriptId,
          }.toList()
        : const <String>[];

    await ref.read(transcriptRepositoryProvider).applyLooks(
          projectId: widget.projectId,
          changes: changes,
          resetSentencesIn: transcripts,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selection = ref.watch(timelineSelectionProvider(widget.projectId));
    final layers =
        ref.watch(projectLayersProvider(widget.projectId)).value ?? const [];
    final texts =
        ref.watch(projectTextLayersProvider(widget.projectId)).value ??
            const [];

    // Rebuilt as the rows the targets come from change.
    ref.watch(projectSentencesProvider(widget.projectId));
    final lines = ref.watch(projectTranslationLinesProvider(widget.projectId));

    final selected = _selected(selection);
    final targets = _targets(selected, _scope);
    // Captions -- rather than only texts or translations -- among what the
    // change reaches: they have caption styles as well.
    final captions = targets.any((t) =>
        t.kind == TimelineItemKind.sentence ||
        t.kind == TimelineItemKind.layer);
    final resetSentences = (selected.isEmpty || _scope == _StyleScope.all) &&
        targets.any((t) => t.kind == TimelineItemKind.layer);

    // What the controls show: the first target's look.
    final first = targets.firstOrNull;
    final ItemLook current = switch (first?.kind) {
      TimelineItemKind.text =>
        texts.where((t) => t.id == first!.id).firstOrNull?.itemLook ??
            ItemLook.defaults,
      TimelineItemKind.layer =>
        layers.where((l) => l.id == first!.id).firstOrNull?.look ??
            ItemLook.defaults,
      TimelineItemKind.sentence => ref
              .watch(sentenceLookProvider(widget.projectId, first!.id))
              .value ??
          ItemLook.defaults,
      // Its own, else its transcription's, as it is drawn.
      TimelineItemKind.translation => () {
          final line =
              lines.where((l) => l.line.id == first!.id).firstOrNull;
          return ItemLook.decode(line?.line.look) ??
              layers.where((l) => l.id == line?.layerId).firstOrNull?.look ??
              ItemLook.defaults;
        }(),
      _ => ItemLook.defaults,
    };

    final items = [
      (_StyleItem.font, Icons.font_download_outlined, l10n.styleFont),
      (_StyleItem.color, Icons.palette_outlined, l10n.styleColor),
      (_StyleItem.shadow, Icons.blur_on, l10n.styleShadow),
      if (captions)
        (_StyleItem.mode, Icons.subtitles_outlined, l10n.styleCaption),
      if (captions && current.usesHighlight)
        (_StyleItem.highlight, Icons.highlight, l10n.styleHighlight),
    ];
    // An item that has just gone -- the highlight, after choosing Standard --
    // hands over to the first rather than leaving nothing chosen.
    final item = items.any((entry) => entry.$1 == _item)
        ? _item
        : _StyleItem.font;

    void change(ItemLook Function(ItemLook) edit) {
      if (targets.isEmpty) return;
      _apply(targets, resetSentences, edit);
    }

    // **Grows up from the toolbar**: the Style button, a link up to the row
    // of items, the chosen item, a link up to its options. Each child sits
    // above its parent, joined to it like a folder tab.
    return LayoutBuilder(
      builder: (context, constraints) {
        final anchor = widget.anchor;
        // Where the toolbar's Style cell has its edges, across the full
        // width -- the toolbar runs edge to edge, with no outer line.
        final toolbarEdges = anchor == null
            ? null
            : appLinkEdges(
                width: constraints.maxWidth,
                count: anchor.count,
                index: anchor.index,
                border: 0,
                rule: appRuleWidth(context),
              );
        // The same two points in the items row's own frame, inset by the
        // panel's side margin.
        final itemsOpening = toolbarEdges == null
            ? null
            : (
                toolbarEdges.$1 - AppSpacing.md,
                toolbarEdges.$2 - AppSpacing.md,
              );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: _body(
                context,
                l10n: l10n,
                theme: theme,
                captions: captions,
                selected: selected,
                targets: targets,
                scoped: selected.any((t) =>
                    t.kind == TimelineItemKind.sentence ||
                    t.kind == TimelineItemKind.layer ||
                    t.kind == TimelineItemKind.translation),
                perSpeaker: selected.any((t) =>
                    t.kind == TimelineItemKind.sentence ||
                    t.kind == TimelineItemKind.translation),
                onlyTranslations: selected.isNotEmpty &&
                    selected.every(
                        (t) => t.kind == TimelineItemKind.translation),
                items: items,
                item: item,
                current: current,
                change: change,
                itemsOpening: itemsOpening,
              ),
            ),
            if (toolbarEdges != null)
              AppLinkChannel(
                height: AppSpacing.sm,
                edges: (_) => toolbarEdges,
                repaintKey: toolbarEdges,
              )
            else
              const SizedBox(height: AppSpacing.xs),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context, {
    required AppLocalizations l10n,
    required ThemeData theme,
    required bool captions,
    required List<TimelineItem> selected,
    required List<TimelineItem> targets,
    required bool scoped,
    required bool perSpeaker,
    required bool onlyTranslations,
    required List<(_StyleItem, IconData, String)> items,
    required _StyleItem item,
    required ItemLook current,
    required void Function(ItemLook Function(ItemLook)) change,
    required (double, double)? itemsOpening,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only when there is a choice: with captions or translation lines
        // selected, style just them, everything their speakers say, or
        // every one.
        if (scoped) ...[
          AppSegmentRow<_StyleScope>(
            selected: !perSpeaker && _scope == _StyleScope.speaker
                ? _StyleScope.selected
                : _scope,
            items: {
              _StyleScope.selected:
                  l10n.styleScopeSelected(selected.length),
              if (perSpeaker) _StyleScope.speaker: l10n.styleScopeSpeaker,
              _StyleScope.all: onlyTranslations
                  ? l10n.styleScopeAllTranslations
                  : l10n.styleScopeAll,
            },
            onSelected: (scope) => setState(() => _scope = scope),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (targets.isEmpty)
          DecoratedBox(
            // No frame and no shadow: the rows inside are strips with
            // their own box, and a box round them read as boxes in a box.
            // Only the card's tone, which on paper is the page's own.
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l10n.styleNothing,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          // The chosen item's options in a rectangle below, linked to it
          // like a folder tab -- the same panel as the video settings.
          AppLinkedPanel(
            // Options above, items below, the whole panel above the
            // toolbar: each child over its parent.
            upward: true,
            itemsOpening: itemsOpening,
            selected: items.indexWhere((entry) => entry.$1 == item),
            items: [
              for (final (value, icon, label) in items)
                AppPanelItem(
                  icon: icon,
                  label: label,
                  selected: item == value,
                  onTap: () => setState(() => _item = value),
                ),
            ],
            // Anchored at the bottom, where the panel is anchored: it grows up
            // from the toolbar, so a change of height has to move its top edge,
            // not its bottom.
            child: AnimatedSize(
              duration: _motion,
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: _motion,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                // Only the arriving options take space; the leaving ones fade
                // out pinned to the same bottom edge rather than being centred
                // over them.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    for (final child in previous)
                      Positioned(left: 0, right: 0, bottom: 0, child: child),
                    ?current,
                  ],
                ),
                // A short rise as they fade in, from the items below.
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(item),
                  child: switch (item) {
                    _StyleItem.font => _FontOptions(
                        current: current.font,
                        onChanged: (font) =>
                            change((look) => look.copyWith(font: font)),
                      ),
                    _StyleItem.color => Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSegmentRow<bool>(
                              selected: _background,
                              items: {
                                false: l10n.styleColorText,
                                true: l10n.styleColorBackground,
                              },
                              onSelected: (background) =>
                                  setState(() => _background = background),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            AnimatedSwitcher(
                              duration: _motion,
                              child: _background
                                  ? AppColorPicker(
                                      key: const ValueKey('background'),
                                      current: current.backgroundArgb,
                                      defaultLabel: l10n.styleColorNone,
                                      onChanged: (argb) => change(
                                        (look) => look.copyWith(
                                          backgroundArgb: () => argb,
                                        ),
                                      ),
                                    )
                                  : AppColorPicker(
                                      key: const ValueKey('text'),
                                      current: current.colorArgb,
                                      // A caption's default colour is its
                                      // speaker's.
                                      defaultLabel: captions
                                          ? l10n.styleColorSpeaker
                                          : l10n.styleColorDefault,
                                      onChanged: (argb) => change(
                                        (look) => look.copyWith(
                                          colorArgb: () => argb,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    _StyleItem.shadow => Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: _ShadowDial(
                          current: current.shadow,
                          onBackground: current.backgroundArgb != null,
                          onChanged: (shadow) => change(
                            (look) => look.copyWith(shadow: shadow),
                          ),
                        ),
                      ),
                    _StyleItem.mode => _ModeOptions(
                        current: current.mode,
                        onChanged: (mode) =>
                            change((look) => look.copyWith(mode: mode)),
                      ),
                    _StyleItem.highlight => Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppColorPicker(
                              current: current.highlightArgb,
                              onChanged: (argb) => change(
                                (look) => look.copyWith(
                                  highlightArgb:
                                      argb ?? ItemLook.defaultHighlight,
                                ),
                              ),
                            ),
                            if (current.mode == CaptionMode.highlight) ...[
                              const SizedBox(height: AppSpacing.sm),
                              AppSegmentRow<bool>(
                                selected: current.highlightBox,
                                items: {
                                  true: l10n.styleHighlightBox,
                                  false: l10n.styleHighlightLetters,
                                },
                                onSelected: (box) => change(
                                  (look) => look.copyWith(highlightBox: box),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  },
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Every font, each named in itself.
class _FontOptions extends StatelessWidget {
  const _FontOptions({required this.current, required this.onChanged});

  final LookFont current;
  final ValueChanged<LookFont> onChanged;

  @override
  Widget build(BuildContext context) {
    // Clipped only at the sides, so the rules' bars can reach the frame's
    // edge line above and below the row.
    return AppSideClippedScroller(
      child: AppStrip(
        expand: false,
        onCard: true,
        bare: true,
        children: [
          for (final font in LookFont.values)
            SizedBox(
              width: 84,
              child: AppChoice(
                selected: font == current,
                onTap: () => onChanged(font),
                child: Text(
                  font.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: font.drawFamily, fontSize: 15),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shadow's strength, from none to strong: shows the value under the
/// finger and applies it on release, so one drag is one undo step.
class _ShadowDial extends StatefulWidget {
  const _ShadowDial({
    required this.current,
    required this.onBackground,
    required this.onChanged,
  });

  final double current;

  /// Whether the words have a background, which casts no shadow.
  final bool onBackground;

  final ValueChanged<double> onChanged;

  @override
  State<_ShadowDial> createState() => _ShadowDialState();
}

class _ShadowDialState extends State<_ShadowDial> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = _dragging ?? widget.current;
    final percent = (value * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ShadowSample(strength: widget.onBackground ? 0 : value),
            Expanded(
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: widget.onBackground
                    ? null
                    : (v) => setState(() => _dragging = v),
                onChangeEnd: widget.onBackground
                    ? null
                    : (v) {
                        setState(() => _dragging = null);
                        widget.onChanged(v);
                      },
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                percent == 0 ? l10n.styleShadowNone : '$percent%',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        if (widget.onBackground)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              l10n.styleShadowOnBackground,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// "Aa" in white over the shadow it would cast, on a mid-grey chip standing
/// in for footage.
class _ShadowSample extends StatelessWidget {
  const _ShadowSample({required this.strength});

  final double strength;

  @override
  Widget build(BuildContext context) {
    const size = 18.0;
    final shadow = captionShadowFor(strength, size);

    return Container(
      width: 40,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF8A8A8A),
        border: context.surface.border,
      ),
      child: Text(
        'Aa',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1,
          shadows: shadow == null
              ? null
              : [
                  Shadow(
                    color: Color(shadow.argb),
                    blurRadius: shadow.blur,
                    offset: Offset(0, shadow.dy),
                  ),
                ],
        ),
      ),
    );
  }
}

/// The caption modes, each shown doing what it does.
class _ModeOptions extends StatelessWidget {
  const _ModeOptions({required this.current, required this.onChanged});

  final CaptionMode current;
  final ValueChanged<CaptionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppStrip(
      onCard: true,
      bare: true,
      children: [
        for (final (mode, label) in <(CaptionMode, String)>[
          (CaptionMode.standard, l10n.styleModeStandard),
          (CaptionMode.karaoke, l10n.styleModeKaraoke),
          (CaptionMode.wordByWord, l10n.styleModeWordByWord),
          (CaptionMode.highlight, l10n.styleModeHighlight),
        ])
          AppChoice(
            selected: mode == current,
            onTap: () => onChanged(mode),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 22, child: _ModeGlyph(mode: mode)),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A tiny demonstration of a caption mode: three words, the middle one being
/// said.
class _ModeGlyph extends StatelessWidget {
  const _ModeGlyph({required this.mode});

  final CaptionMode mode;

  @override
  Widget build(BuildContext context) {
    final ink = IconTheme.of(context).color ?? Colors.black;
    // A demonstration, so a colour that shows on the panel's own surface.
    const highlight = Color(0xFFFFE14D);
    final base = TextStyle(
      color: ink,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      height: 1,
    );

    final runs = captionRunsAt(
      const [
        (text: 'Aa', startMs: 0, endMs: 10),
        (text: 'Bb', startMs: 10, endMs: 20),
        (text: 'Cc', startMs: 20, endMs: 30),
      ],
      15,
      mode,
    );

    return Center(
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final (index, run) in runs.indexed) ...[
              if (index > 0) const TextSpan(text: ' '),
              TextSpan(
                text: run.text,
                style: run.marked
                    ? mode == CaptionMode.highlight
                        ? const TextStyle(
                            backgroundColor: highlight,
                            color: Color(0xFF111111),
                          )
                        : const TextStyle(color: Color(0xFFE0A800))
                    : null,
              ),
            ],
          ],
        ),
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      ),
    );
  }
}
