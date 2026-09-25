import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:argand/features/transcription/clip_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineItem clip(String id) => (kind: TimelineItemKind.clip, id: id);
TimelineItem layer(String id) => (kind: TimelineItemKind.layer, id: id);

void main() {
  group('tapSelection', () {
    test('a tap picks one thing, replacing what was selected', () {
      final selection =
          tapSelection({clip('a'), layer('L')}, clip('b'), multi: false);

      expect(selection, {clip('b')});
    });

    test('tapping the one selected thing puts it down', () {
      expect(tapSelection({clip('a')}, clip('a'), multi: false), isEmpty);
    });

    test('tapping one of several picks just that one', () {
      // Not a toggle: outside multi-select, a tap means "this one".
      expect(
        tapSelection({clip('a'), clip('b')}, clip('a'), multi: false),
        {clip('a')},
      );
    });

    test('while multi-selecting, taps add and remove', () {
      var selection = tapSelection({clip('a')}, layer('L'), multi: true);
      expect(selection, {clip('a'), layer('L')});

      selection = tapSelection(selection, clip('a'), multi: true);
      expect(selection, {layer('L')});
    });
  });

  group('TimelineSelection', () {
    late ProviderContainer container;
    const project = 'p';

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    TimelineSelection notifier() =>
        container.read(timelineSelectionProvider(project).notifier);
    Set<TimelineItem> selection() =>
        container.read(timelineSelectionProvider(project));
    bool multi() => container.read(timelineMultiSelectProvider(project));

    test('a long press starts multi-select, and taps then add', () {
      notifier().tap(clip('a'));
      notifier().longPress(layer('L'));
      expect(multi(), isTrue);

      notifier().tap(clip('b'));
      expect(selection(), {clip('a'), layer('L'), clip('b')});
    });

    test('emptying the selection ends multi-select', () {
      notifier().longPress(clip('a'));
      notifier().tap(clip('a'));

      expect(selection(), isEmpty);
      expect(multi(), isFalse, reason: 'the next tap should pick one again');

      notifier().tap(clip('b'));
      notifier().tap(clip('c'));
      expect(selection(), {clip('c')});
    });

    test('Done clears and leaves multi-select', () {
      notifier().longPress(clip('a'));
      notifier().longPress(clip('b'));
      notifier().clear();

      expect(selection(), isEmpty);
      expect(multi(), isFalse);
    });
  });

  group('toggleSelection', () {
    test('a tap adds, and a second tap takes it away', () {
      var selection = toggleSelection(const {}, clip('a'));
      expect(selection, {clip('a')});

      selection = toggleSelection(selection, clip('a'));
      expect(selection, isEmpty);
    });

    test('tapping a second thing keeps the first', () {
      // The whole point of a set: cut a clip and the layer over it in one
      // stroke. A tap that replaced the selection would make that impossible.
      final selection =
          toggleSelection(toggleSelection(const {}, clip('a')), layer('L'));

      expect(selection, {clip('a'), layer('L')});
    });

    test('a clip and a layer sharing an id are different things', () {
      final selection =
          toggleSelection(toggleSelection(const {}, clip('x')), layer('x'));

      expect(selection, hasLength(2));
    });

    test('the input is left alone', () {
      final original = {clip('a')};
      toggleSelection(original, layer('L'));

      expect(original, {clip('a')});
    });
  });

  group('prunedSelection', () {
    test('drops what no longer exists', () {
      // A tool acting on a removed row would report success having done
      // nothing, which is worse than the row quietly leaving the selection.
      final pruned = prunedSelection(
        {clip('a'), clip('gone'), layer('L')},
        clipIds: {'a'},
        layerIds: {'L'},
      );

      expect(pruned, {clip('a'), layer('L')});
    });

    test('a clip id is not mistaken for a layer id', () {
      final pruned = prunedSelection(
        {layer('a')},
        clipIds: {'a'},
        layerIds: const {},
      );

      expect(pruned, isEmpty);
    });
  });

  group('idsOfKind', () {
    test('separates the kinds', () {
      final selection = {clip('a'), clip('b'), layer('L')};

      expect(idsOfKind(selection, TimelineItemKind.clip), {'a', 'b'});
      expect(idsOfKind(selection, TimelineItemKind.layer), {'L'});
    });

    test('is empty when nothing of that kind is selected', () {
      expect(idsOfKind({clip('a')}, TimelineItemKind.layer), isEmpty);
    });
  });
}
