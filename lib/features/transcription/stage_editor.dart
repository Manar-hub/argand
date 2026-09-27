import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/captions/caption_controller.dart';
import '../../core/captions/caption_cue.dart';
import '../../core/captions/caption_grouper.dart';
import '../../core/captions/speaker_palette.dart';
import '../../core/database/database.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/translation_texts.dart';
import '../../core/timeline/timeline_sentences.dart';
import '../../core/timeline/timeline_selection.dart';
import '../../core/video/export_options.dart';
import 'clip_controller.dart';
import 'timeline_history.dart';
import 'transcript_repository.dart';

part 'stage_editor.g.dart';

/// Placements being changed right now, before they are saved.
///
/// **Held apart from the database while a finger is down.** A drag produces
/// sixty positions a second; writing each would put sixty rows in the undo
/// log and sixty queries behind every frame. The stage draws from here while
/// the gesture runs, and one write -- one undo step -- lands when it ends.
@riverpod
class StageLive extends _$StageLive {
  @override
  Map<TimelineItem, ItemTransform> build(String projectId) => const {};

  void show(Map<TimelineItem, ItemTransform> placements) =>
      state = Map.unmodifiable(placements);

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

/// How long a placement change takes to settle when it is not under a finger
/// -- a quarter turn from the Rotate tool, an undo. The same figure as every
/// other movement in the editor.
const Duration _settle = Duration(milliseconds: 220);

/// Where [item] sits: being dragged, or as stored.
///
/// Sentences have no row of their own, so their stored placement is passed
/// in [sentences], resolved from their words by whoever has them.
ItemTransform placementOf(
  TimelineItem item, {
  required Map<TimelineItem, ItemTransform> live,
  required List<MediaClip> clips,
  required List<TranscribeLayer> layers,
  required List<TextLayer> texts,
  Map<TimelineItem, ItemTransform> sentences = const {},
}) {
  if (live[item] case final moving?) return moving;
  return switch (item.kind) {
    TimelineItemKind.clip =>
      clips.where((c) => c.id == item.id).firstOrNull?.framing ??
          ItemTransform.identity,
    TimelineItemKind.layer =>
      layers.where((l) => l.id == item.id).firstOrNull?.captionPlacement ??
          ItemTransform.captionDefault,
    TimelineItemKind.text =>
      texts.where((t) => t.id == item.id).firstOrNull?.placement ??
          ItemTransform.identity,
    TimelineItemKind.sentence =>
      sentences[item] ?? ItemTransform.captionDefault,
    // Sound has no place on the picture.
    TimelineItemKind.audio => ItemTransform.identity,
  };
}

/// Which item on the stage is having its words typed, if any.
///
/// **A provider rather than editor state** because the tools start it from
/// outside the stage: the Text tool adds a text and opens it for typing
/// straight away, and the strip's Edit text does the same for a selected one.
///
/// **Kept alive**, because the ask can come before anything listens: right
/// after a project opens the player is still loading and there is no stage
/// yet. Auto-disposed, the request was dropped at the end of that frame and
/// the new text appeared without its keyboard.
@Riverpod(keepAlive: true)
class StageEditing extends _$StageEditing {
  @override
  TimelineItem? build(String projectId) => null;

  bool _fresh = false;

  /// Whether the item being opened was just made and holds only its
  /// placeholder -- the Text tool's new text -- so typing starts from empty
  /// with the placeholder as a hint, rather than from a word to delete.
  bool get fresh => _fresh;

  void start(TimelineItem item, {bool fresh = false}) {
    _fresh = fresh;
    state = item;
  }

  void stop() {
    _fresh = false;
    if (state != null) state = null;
  }
}

/// The clip's picture, placed as its framing says, inside the output frame.
///
/// Fitted first (the render's `LAYOUT_SCALE_TO_FIT`), then moved, turned and
/// scaled -- the order the render applies them in, so zooming in crops at the
/// frame's edge and zooming out shows black around the picture.
class StagePicture extends ConsumerWidget {
  const StagePicture({
    super.key,
    required this.projectId,
    required this.clipId,
    required this.sourceSize,
    required this.picture,
  });

  final String projectId;
  final String? clipId;
  final Size sourceSize;
  final Widget picture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipId = this.clipId;
    final live = ref.watch(stageLiveProvider(projectId));
    final item = clipId == null
        ? null
        : (kind: TimelineItemKind.clip, id: clipId);
    final placement = item == null
        ? ItemTransform.identity
        : placementOf(
            item,
            live: live,
            clips: ref.watch(projectClipsProvider(projectId)).value ?? const [],
            layers: const [],
            texts: const [],
          );

    // Settles smoothly after a tool or an undo, follows the finger exactly
    // while one is down, and is simply there with animations off.
    final moving = item != null && live.containsKey(item);
    final duration = moving || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _settle;

    final fitted = FittedBox(
      fit: BoxFit.contain,
      child: SizedBox.fromSize(size: sourceSize, child: picture),
    );

    return LayoutBuilder(
      builder: (context, frame) => TweenAnimationBuilder<ItemTransform>(
        tween: _PlacementTween(end: placement),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: fitted,
        builder: (context, value, child) => _placed(
          value,
          frame.biggest,
          child: child!,
        ),
      ),
    );
  }
}

class _PlacementTween extends Tween<ItemTransform> {
  _PlacementTween({required ItemTransform end}) : super(begin: end, end: end);

  @override
  ItemTransform lerp(double t) => ItemTransform.lerp(begin!, end!, t);
}

/// [child] moved, turned and scaled about the frame's centre by [t].
Widget _placed(ItemTransform t, Size frame, {required Widget child}) {
  return Transform.translate(
    offset: Offset(t.x * frame.width / 2, -t.y * frame.height / 2),
    child: Transform.rotate(
      angle: t.rotation * math.pi / 180,
      child: Transform.scale(scale: t.scale, child: child),
    ),
  );
}

/// Everything drawn over the picture -- captions and texts -- and, when
/// [editable], everything that edits it.
///
/// **One gesture surface for every kind of item.** A drag, pinch or twist
/// anywhere on the frame moves whatever is selected, all of it at once; a tap
/// picks an item; a hold adds it to a multi-selection; tapping the selected
/// text or caption again types into it where it stands. Resizing from a
/// corner handle is the same gesture started on a handle.
///
/// **Each caption is its own sentence.** Tapping one picks that sentence
/// alone, to move, size or retype without touching the others; picking its
/// layer (on the timeline) moves every sentence not placed on its own.
class StageEditor extends ConsumerStatefulWidget {
  const StageEditor({
    super.key,
    required this.projectId,
    required this.clipId,
    required this.sourceSize,
    required this.mediaPositionMs,
    required this.editable,
  });

  final String projectId;

  /// The clip on the stage, whose picture and captions are drawn.
  final String? clipId;

  final Size sourceSize;

  /// Where the player is inside the clip's media.
  final int mediaPositionMs;

  /// False in Script mode, which shows the result without editing it.
  final bool editable;

  @override
  ConsumerState<StageEditor> createState() => _StageEditorState();
}

/// A caption on screen now: the words showing, the sentence they belong to,
/// and where it sits.
typedef _ShownCaption = ({
  Transcript transcript,
  CaptionCue cue,
  TimelineItem item,
  ItemTransform placement,

  /// The sentence's own placement, or null while it follows its layer.
  ItemTransform? own,

  /// How it looks: its own, else its layer's, else the default.
  ItemLook look,
});

class _StageEditorState extends ConsumerState<StageEditor> {
  /// The outline of each selected item on screen, for finding which corner a
  /// resize starts from.
  final Map<TimelineItem, GlobalKey> _outlines = {};

  /// What each sentence on screen has of its own, from the last build: a
  /// gesture needs it to record what undo should restore.
  Map<TimelineItem, _ShownCaption> _shown = const {};

  Map<TimelineItem, ItemTransform>? _start;
  Offset _startFocal = Offset.zero;

  /// Set when the gesture began on a corner handle: the centre it scales
  /// about, in global coordinates.
  Offset? _resizeCentre;

  // Typing in place.
  TimelineItem? _editing;
  TextEditingController? _field;
  final FocusNode _focus = FocusNode();

  /// The placeholder shown faintly while a new text is still empty.
  String? _hint;

  /// What a caption edit will replace: the words showing when typing began,
  /// fixed then so the playhead moving on cannot retarget it.
  ({String transcriptId, int from, int to})? _captionTarget;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Leaving the field -- the keyboard's Done, a tap elsewhere, the item
      // scrolling out of view -- saves what was typed.
      if (!_focus.hasFocus && _editing != null) _commit();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _field?.dispose();
    super.dispose();
  }

  GlobalKey _outlineKey(TimelineItem item) =>
      _outlines.putIfAbsent(item, GlobalKey.new);

  TimelineSelection get _selection =>
      ref.read(timelineSelectionProvider(widget.projectId).notifier);

  StageEditing get _editingNotifier =>
      ref.read(stageEditingProvider(widget.projectId).notifier);

  /// A tap on an item: picks it -- or, when it is already the one thing
  /// picked, opens it for typing where it stands.
  void _tap(TimelineItem item, {required bool typable}) {
    final selection = ref.read(timelineSelectionProvider(widget.projectId));
    final multi = ref.read(timelineMultiSelectProvider(widget.projectId));
    if (typable &&
        !multi &&
        selection.length == 1 &&
        selection.contains(item)) {
      _editingNotifier.start(item);
      return;
    }
    _selection.tap(item);
  }

  void _hold(TimelineItem item) {
    HapticFeedback.selectionClick();
    _selection.longPress(item);
  }

  /// Opens [item] for typing, starting from [text].
  void _beginEditing(
    TimelineItem item,
    String text, {
    ({String transcriptId, int from, int to})? caption,
  }) {
    final fresh = _editingNotifier.fresh;
    _field?.dispose();
    // **A cursor at the end, nothing selected.** Selecting the words put the
    // platform's highlight and drag handles around them -- the words looked
    // replaced before anything was typed. Now they stay exactly as they were,
    // and only become editable.
    final start = fresh ? '' : text;
    _field = TextEditingController(text: start)
      ..selection = TextSelection.collapsed(offset: start.length);
    _hint = fresh ? text : null;
    _editing = item;
    _captionTarget = caption;
    // After this frame, once the field exists to take focus -- which is what
    // brings the keyboard up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == item) _focus.requestFocus();
    });
  }

  Future<void> _commit() async {
    final item = _editing;
    final typed = _field?.text.trim() ?? '';
    final caption = _captionTarget;
    _editing = null;
    _captionTarget = null;
    if (_focus.hasFocus) _focus.unfocus();
    _editingNotifier.stop();
    if (item == null) return;

    final repository = ref.read(transcriptRepositoryProvider);
    switch (item.kind) {
      case TimelineItemKind.text:
        // Emptied is removed: a text with no words is nothing on screen and
        // an untappable sliver on the track.
        if (typed.isEmpty) {
          await repository.removeTextLayer(item.id);
          _selection.clear();
        } else {
          await repository.editTextLayer(id: item.id, content: typed);
        }
      case TimelineItemKind.sentence:
        if (caption == null || typed.isEmpty) return;
        await repository.replaceSentence(
          transcriptId: caption.transcriptId,
          fromPosition: caption.from,
          toPosition: caption.to,
          text: typed,
        );
        // Retyping can change how many words the sentence has, so the
        // selection's word range no longer names it; put it down rather than
        // leave it pointing at the wrong words.
        _selection.clear();
      case TimelineItemKind.clip:
      case TimelineItemKind.layer:
      case TimelineItemKind.audio:
        break;
    }
    if (mounted) setState(() {});
  }

  ({
    List<MediaClip> clips,
    List<TranscribeLayer> layers,
    List<TextLayer> texts,
  }) _rows() => (
        clips: ref.read(projectClipsProvider(widget.projectId)).value ??
            const [],
        layers: ref.read(projectLayersProvider(widget.projectId)).value ??
            const [],
        texts: ref.read(projectTextLayersProvider(widget.projectId)).value ??
            const [],
      );

  void _gestureStart(ScaleStartDetails details) {
    final selection = ref.read(timelineSelectionProvider(widget.projectId));
    if (selection.isEmpty || _editing != null) return;

    final rows = _rows();
    _start = {
      for (final item in selection)
        // A sentence not on screen has no words in hand to place; it keeps
        // its place rather than being moved from a guess.
        if (item.kind != TimelineItemKind.sentence || _shown.containsKey(item))
          item: placementOf(
            item,
            live: const {},
            clips: rows.clips,
            layers: rows.layers,
            texts: rows.texts,
            sentences: {
              for (final entry in _shown.entries)
                entry.key: entry.value.placement,
            },
          ),
    };
    _startFocal = details.focalPoint;
    _resizeCentre =
        details.pointerCount == 1 ? _handleCentreAt(details.focalPoint) : null;
  }

  /// The centre of the selected item whose corner handle is under [point],
  /// if any.
  Offset? _handleCentreAt(Offset point) {
    const reach = 28.0;
    for (final entry in _outlines.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;

      final size = box.size;
      for (final corner in [
        Offset.zero,
        Offset(size.width, 0),
        Offset(0, size.height),
        Offset(size.width, size.height),
      ]) {
        if ((box.localToGlobal(corner) - point).distance <= reach) {
          return box.localToGlobal(size.center(Offset.zero));
        }
      }
    }
    return null;
  }

  void _gestureUpdate(ScaleUpdateDetails details, Size frame) {
    final start = _start;
    if (start == null) return;

    final centre = _resizeCentre;
    final pan = details.focalPoint - _startFocal;
    final resize = centre == null
        ? null
        : (details.focalPoint - centre).distance /
            math.max((_startFocal - centre).distance, 1);

    ref.read(stageLiveProvider(widget.projectId).notifier).show({
      for (final MapEntry(key: item, value: from) in start.entries)
        item: _keepUpright(
          item,
          resize != null
              ? from.afterGesture(
                  frameWidth: frame.width,
                  frameHeight: frame.height,
                  pinch: resize,
                )
              : from.afterGesture(
                  frameWidth: frame.width,
                  frameHeight: frame.height,
                  panX: pan.dx,
                  panY: pan.dy,
                  pinch: details.scale,
                  turnRadians: details.rotation,
                ),
        ),
    });
  }

  /// Captions stay level: a turned subtitle is a puzzle, not a style.
  ItemTransform _keepUpright(TimelineItem item, ItemTransform t) =>
      item.kind == TimelineItemKind.layer ||
              item.kind == TimelineItemKind.sentence
          ? t.copyWith(rotation: 0)
          : t;

  Future<void> _gestureEnd() async {
    final start = _start;
    _start = null;
    _resizeCentre = null;
    if (start == null) return;

    final live = ref.read(stageLiveProvider(widget.projectId));
    await ref.read(transcriptRepositoryProvider).applyPlacements(
      projectId: widget.projectId,
      changes: [
        for (final MapEntry(key: item, value: from) in start.entries)
          (
            kind: item.kind,
            id: item.id,
            // A sentence that followed its layer goes back to following it
            // on undo, rather than being pinned where the layer was.
            before: item.kind == TimelineItemKind.sentence
                ? _shown[item]?.own
                : from,
            after: live[item] ?? from,
          ),
      ],
    );
    if (mounted) {
      ref.read(stageLiveProvider(widget.projectId).notifier).clear();
    }
  }

  /// The captions showing now, one per transcript on the clip, each as the
  /// sentence it belongs to.
  Map<TimelineItem, _ShownCaption> _captionsNow({
    required List<Transcript> transcripts,
    required List<TranscribeLayer> layers,
    required List<TimelineSentence> sentences,
  }) {
    final shown = <TimelineItem, _ShownCaption>{};
    for (final transcript in transcripts) {
      final cues = ref.watch(captionCuesProvider(transcript.id)).value;
      final cue = cues == null ? null : cueAt(cues, widget.mediaPositionMs);
      if (cue == null || cue.words.isEmpty) continue;

      final layer =
          layers.where((l) => l.id == transcript.layerId).firstOrNull;
      final first = cue.words.first.position;
      final sentence = sentences
          .where((s) =>
              s.transcriptId == transcript.id &&
              s.fromPosition <= first &&
              first <= s.toPosition)
          .firstOrNull;

      // A cue is a slice of a sentence; the sentence is what is placed. With
      // no sentence to hand -- words not yet grouped -- the cue stands in.
      final item = sentenceItem(
        transcriptId: transcript.id,
        fromPosition: sentence?.fromPosition ?? first,
        toPosition: sentence?.toPosition ?? cue.words.last.position,
      );
      final own = cue.words.first.captionPlacement;
      shown[item] = (
        transcript: transcript,
        cue: cue,
        item: item,
        placement:
            own ?? layer?.captionPlacement ?? ItemTransform.captionDefault,
        own: own,
        look: cue.words.first.ownLook ?? layer?.look ?? ItemLook.defaults,
      );
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final clipId = widget.clipId;
    final live = ref.watch(stageLiveProvider(projectId));
    final selection = widget.editable
        ? ref.watch(timelineSelectionProvider(projectId))
        : const <TimelineItem>{};
    final clips = ref.watch(projectClipsProvider(projectId)).value ?? const [];
    final layers =
        ref.watch(projectLayersProvider(projectId)).value ?? const [];
    final texts =
        ref.watch(projectTextLayersProvider(projectId)).value ?? const [];
    // What the gutter's eyes have hidden is not drawn -- nor exported.
    final hidden = ref.watch(hiddenTracksProvider(projectId));
    // Drawn like texts but never picked: a translation is changed by
    // translating again, not by dragging or retyping it on the picture.
    final translations = hidden.contains(TimelineTrack.translation)
        ? const <TextLayer>[]
        : ref.watch(projectTranslationTextsProvider(projectId));
    final transcripts = clipId == null
        ? const <Transcript>[]
        : ref.watch(clipTranscriptsProvider(clipId)).value ?? const [];

    _shown = _captionsNow(
      transcripts: transcripts,
      layers: layers,
      sentences: transcripts.isEmpty
          ? const []
          : ref.watch(projectSentencesProvider(projectId)),
    );

    ItemTransform where(TimelineItem item) => placementOf(
          item,
          live: live,
          clips: clips,
          layers: layers,
          texts: texts,
          sentences: {
            for (final entry in _shown.entries)
              entry.key: entry.value.placement,
          },
        );

    // Texts are timed in project time; the player reports media time.
    final clip = clips.where((c) => c.id == clipId).firstOrNull;
    final placement = clipId == null
        ? null
        : ref.watch(projectTimelineProvider(projectId)).placementOf(clipId);
    final projectMs = placement == null || clip == null
        ? null
        : placement.startMs + widget.mediaPositionMs - (clip.trimStartMs ?? 0);

    // Typing starts when asked -- by a second tap, or by a tool -- and only
    // once the item is on screen to type into.
    final wanted = widget.editable
        ? ref.watch(stageEditingProvider(projectId))
        : null;
    if (wanted != null && wanted != _editing) {
      final text = wanted.kind == TimelineItemKind.text
          ? texts.where((t) => t.id == wanted.id).firstOrNull
          : null;
      final shownCaption = _shown[wanted];
      if (text != null &&
          projectMs != null &&
          projectMs >= text.startMs &&
          projectMs < text.endMs) {
        _beginEditing(wanted, text.content);
      } else if (shownCaption != null) {
        _beginEditing(
          wanted,
          shownCaption.cue.text,
          caption: (
            transcriptId: shownCaption.transcript.id,
            from: shownCaption.cue.words.first.position,
            to: shownCaption.cue.words.last.position,
          ),
        );
      }
    }

    // Only what is selected keeps an outline key; a key left behind would be
    // found by the next resize and scale something no longer selected.
    _outlines.removeWhere((item, _) => !selection.contains(item));

    return LayoutBuilder(
      builder: (context, box) {
        final frame = box.biggest;
        final shortEdge = math.min(frame.width, frame.height);
        final clipItem = clipId == null
            ? null
            : (kind: TimelineItemKind.clip, id: clipId);
        final typing = _editing != null;

        final children = <Widget>[
          // The picture itself answers taps anywhere nothing else does. While
          // typing, a tap there is the way out of the field.
          if (widget.editable && clipItem != null && !typing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tap(clipItem, typable: false),
                onLongPress: () => _hold(clipItem),
              ),
            ),
          if (clipItem != null && selection.contains(clipItem))
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _placed(
                    where(clipItem),
                    frame,
                    child: _Outline(
                      key: _outlineKey(clipItem),
                      scale: where(clipItem).scale,
                      child: SizedBox.fromSize(
                        size: _fittedSize(widget.sourceSize, frame),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!hidden.contains(TimelineTrack.layers))
          for (final shown in _shown.values)
            _anchored(
              where(shown.item),
              frame,
              child: _item(
                item: shown.item,
                selected: selection.contains(shown.item),
                scale: where(shown.item).scale,
                style: _captionStyle(shown.cue, shown.look, shortEdge),
                text: shown.cue.text,
                rich: _captionSpan(
                  shown.cue,
                  shown.look,
                  _captionStyle(shown.cue, shown.look, shortEdge),
                  widget.mediaPositionMs,
                ),
                padded: false,
              ),
            ),
          if (projectMs != null && !hidden.contains(TimelineTrack.texts))
            for (final text in texts)
              if (projectMs >= text.startMs && projectMs < text.endMs)
                _anchored(
                  where((kind: TimelineItemKind.text, id: text.id)),
                  frame,
                  child: _item(
                    item: (kind: TimelineItemKind.text, id: text.id),
                    selected: selection
                        .contains((kind: TimelineItemKind.text, id: text.id)),
                    scale: where((kind: TimelineItemKind.text, id: text.id))
                        .scale,
                    style: _textLayerStyle(
                      text.itemLook ?? ItemLook.defaults,
                      shortEdge,
                    ),
                    text: text.content,
                    padded: true,
                  ),
                ),
          if (projectMs != null)
            for (final line in translations)
              if (projectMs >= line.startMs && projectMs < line.endMs)
                _anchored(
                  ItemTransform(x: line.x, y: line.y, scale: line.scale),
                  frame,
                  child: IgnorePointer(
                    child: Text(
                      line.content,
                      textAlign: TextAlign.center,
                      textDirection: translationDirectionOf(line.content),
                      style: _textLayerStyle(
                        ItemLook.decode(line.look) ?? ItemLook.defaults,
                        shortEdge,
                      ),
                    ),
                  ),
                ),
        ];

        final stack = Stack(clipBehavior: Clip.none, children: children);
        if (!widget.editable) return IgnorePointer(child: stack);
        if (typing) return stack;

        return GestureDetector(
          onScaleStart: _gestureStart,
          onScaleUpdate: (details) => _gestureUpdate(details, frame),
          onScaleEnd: (_) => _gestureEnd(),
          child: stack,
        );
      },
    );
  }

  /// A caption or text: its words as the render draws them -- or, while it
  /// is being typed into, a field in exactly that style, in exactly that
  /// place, so typing reads as changing the words on the picture rather than
  /// filling in a form.
  Widget _item({
    required TimelineItem item,
    required bool selected,
    required double scale,
    required TextStyle style,
    required String text,
    required bool padded,
    InlineSpan? rich,
  }) {
    if (item == _editing && _field != null) {
      // **Exactly the resting look, now editable.** No outline or handles
      // while typing, the same style, no text scaling, and a text layer's
      // padding spaces drawn as plate on either side -- so nothing on the
      // picture moves or changes the moment the cursor appears.
      final field = TextField(
        controller: _field,
        focusNode: _focus,
        style: style,
        textAlign: TextAlign.center,
        maxLines: null,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: Colors.white,
        cursorWidth: 1.5,
        // Every border and fill spelled out as none. `collapsed` alone still
        // let the app theme's focused border through -- an accent pill
        // around the words the moment they became editable.
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          hintText: _hint ?? '',
          hintStyle: style.copyWith(
            color: (style.color ?? Colors.white).withValues(alpha: 0.5),
          ),
        ),
        onSubmitted: (_) => _focus.unfocus(),
        onTapOutside: (_) => _focus.unfocus(),
      );

      return MediaQuery.withNoTextScaling(
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 8),
            child: padded
                ? ColoredBox(
                    color: style.backgroundColor ?? Colors.transparent,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _spaceWidth(style),
                      ),
                      child: field,
                    ),
                  )
                : field,
          ),
        ),
      );
    }

    final words = rich != null
        ? Text.rich(
            rich,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
          )
        : Text(
            // Padded the way the render pads a text layer, so the plate
            // reaches past the first and last letters.
            padded ? ' $text ' : text,
            textAlign: TextAlign.center,
            // Pixels in the output, so never scaled by the reader's text size.
            textScaler: TextScaler.noScaling,
            style: style,
          );
    if (!widget.editable) return words;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(item, typable: true),
      onLongPress: () => _hold(item),
      child: selected
          ? _Outline(key: _outlineKey(item), scale: scale, child: words)
          : words,
    );
  }
}

/// How wide one space is in [style]: the padding a text layer's plate has
/// either side of its words, which the typing field draws as plate.
double _spaceWidth(TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: ' ', style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The size a picture of [source] is fitted to inside [frame].
Size _fittedSize(Size source, Size frame) {
  if (source.isEmpty) return frame;
  final fit = math.min(frame.width / source.width, frame.height / source.height);
  return source * fit;
}

/// [child] centred on [t]'s point in the frame, then turned and scaled about
/// its own centre -- how an overlay is anchored in the render
/// (`setBackgroundFrameAnchor`).
Widget _anchored(ItemTransform t, Size frame, {required Widget child}) {
  return Positioned(
    left: (t.x + 1) / 2 * frame.width,
    top: (1 - t.y) / 2 * frame.height,
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: Transform.rotate(
        angle: t.rotation * math.pi / 180,
        child: Transform.scale(
          scale: t.scale,
          child: ConstrainedBox(
            // Room to wrap, so a long line breaks rather than running off.
            constraints: BoxConstraints(maxWidth: frame.width * 0.9),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// A selected item's outline and corner handles.
///
/// In the theme's accent, flat and hard-edged like the rest of the app, and
/// kept the same thickness however far the item is scaled.
class _Outline extends StatelessWidget {
  const _Outline({super.key, required this.scale, required this.child});

  /// The item's own scale, divided out of the line and handle sizes.
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final unit = 1 / (scale <= 0 ? 1 : scale);
    final handle = 10 * unit;

    Widget corner({double? left, double? top, double? right, double? bottom}) =>
        Positioned(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          width: handle,
          height: handle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: Colors.black, width: 1.2 * unit),
            ),
          ),
        );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // A little room inside the outline, so the handles sit off the
        // item's edge rather than over its first and last letters.
        Padding(padding: EdgeInsets.all(4 * unit), child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 2 * unit),
              ),
            ),
          ),
        ),
        corner(left: -handle / 2, top: -handle / 2),
        corner(right: -handle / 2, top: -handle / 2),
        corner(left: -handle / 2, bottom: -handle / 2),
        corner(right: -handle / 2, bottom: -handle / 2),
      ],
    );
  }
}

/// A caption as the render burns it: its look's font, its colour -- or the
/// speaker's -- its background if it has one, else its shadow, sized from
/// the frame rather than the text theme.
TextStyle _captionStyle(CaptionCue cue, ItemLook look, double shortEdge) =>
    _lookStyle(
      look,
      color: look.colorArgb != null
          ? Color(look.colorArgb!)
          : SpeakerPalette.colorFor(cue.speaker, fallback: Colors.white),
      fontSize: math.max(shortEdge * captionTextFraction, 6),
    );

/// The words' style for [look]: a background behind them, or -- only when
/// there is none -- its shadow under them (`captionShadowFor`).
TextStyle _lookStyle(
  ItemLook look, {
  required Color color,
  required double fontSize,
  FontWeight? fontWeight,
}) {
  final shadow = look.backgroundArgb == null
      ? captionShadowFor(look.shadow, fontSize)
      : null;
  return TextStyle(
    fontFamily: look.font.drawFamily,
    color: color,
    fontWeight: fontWeight,
    fontSize: fontSize,
    height: 1.2,
    backgroundColor:
        look.backgroundArgb == null ? null : Color(look.backgroundArgb!),
    shadows: shadow == null
        ? null
        : [
            Shadow(
              color: Color(shadow.argb),
              blurRadius: shadow.blur,
              offset: Offset(0, shadow.dy),
            ),
          ],
  );
}

/// The ink for a word on a highlight box: dark, so it reads on any colour
/// the box is given. **Must match `HIGHLIGHT_INK` in `VideoExportChannel.kt`.**
const Color _highlightInk = Color(0xFF111111);

/// A caption's words as they stand at [atMs] in its look's mode: the marked
/// ones in the highlight colour, or on a box of it.
InlineSpan _captionSpan(
  CaptionCue cue,
  ItemLook look,
  TextStyle base,
  int atMs,
) {
  final runs = captionRunsAt(
    [
      for (final word in cue.words)
        (text: word.word.trim(), startMs: word.startMs, endMs: word.endMs),
    ],
    atMs,
    look.mode,
  );
  final highlight = Color(look.highlightArgb);
  final boxed = look.mode == CaptionMode.highlight && look.highlightBox;

  return TextSpan(
    style: base,
    children: [
      for (final (index, run) in runs.indexed) ...[
        if (index > 0) const TextSpan(text: ' '),
        TextSpan(
          text: run.text,
          style: run.marked
              ? boxed
                  // No shadow on the box: see `captionShadowFor`.
                  ? TextStyle(
                      backgroundColor: highlight,
                      color: _highlightInk,
                      shadows: const [],
                    )
                  : TextStyle(color: highlight)
              : null,
        ),
      ],
    ],
  );
}

/// A text layer as the render burns it: its font, colour, background or
/// shadow -- bold white in the default face.
TextStyle _textLayerStyle(ItemLook look, double shortEdge) => _lookStyle(
      look,
      color: Color(look.colorArgb ?? 0xFFFFFFFF),
      // The bundled faces are already display weights; asking them for bold
      // would have the engine smear a fake one on top.
      fontWeight: look.font == LookFont.standard ? FontWeight.bold : null,
      fontSize: math.max(shortEdge * textLayerFraction, 6),
    );
