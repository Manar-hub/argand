import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineItem clip(String id) => (kind: TimelineItemKind.clip, id: id);
TimelineItem layer(String id) => (kind: TimelineItemKind.layer, id: id);

void main() {
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
