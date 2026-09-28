import 'package:argand/core/theme/theme_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reveal's mechanics, which are checkable. How it *feels* is not, and
/// nothing here claims otherwise.
void main() {
  /// Pumps a reveal over a coloured page and hands back its state.
  Future<ThemeRevealState> pumpReveal(WidgetTester tester,
      {bool disableAnimations = false}) async {
    final key = GlobalKey<ThemeRevealState>();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeReveal(
            key: key,
            child: const ColoredBox(
              color: Color(0xFF112233),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  testWidgets('the theme change happens, and the photograph is cleaned up',
      (tester) async {
    final reveal = await pumpReveal(tester);

    var changed = false;
    final running = reveal.reveal(
      center: const Offset(40, 60),
      change: () => changed = true,
    );

    // The capture is asynchronous, so the switch lands a beat later -- but it
    // must land before any of the animation is shown.
    await tester.pump();
    await tester.pump();
    expect(changed, isTrue);

    await tester.pumpAndSettle();
    await running;

    // Nothing of the old screen is left painted over the new one.
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('with animations disabled it switches and captures nothing',
      (tester) async {
    final reveal = await pumpReveal(tester, disableAnimations: true);

    var changed = false;
    await reveal.reveal(
      center: Offset.zero,
      change: () => changed = true,
    );

    // Synchronous: an accessibility setting that asks for no animation should
    // not also pay for a full-screen capture.
    expect(changed, isTrue);
    await tester.pump();
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('a second sweep cannot start on top of the first',
      (tester) async {
    final reveal = await pumpReveal(tester);

    var first = 0;
    final running = reveal.reveal(
      center: const Offset(10, 10),
      change: () => first++,
    );
    await tester.pump();
    await tester.pump();

    // Mid-sweep, ask again. The change still applies -- refusing it would leave
    // the toggle showing something the app is not -- but no second capture is
    // taken and no second animation begins.
    var second = 0;
    await tester.pump(const Duration(milliseconds: 120));
    await reveal.reveal(
      center: const Offset(300, 300),
      change: () => second++,
    );
    expect(second, 1);

    await tester.pumpAndSettle();
    await running;
    expect(first, 1);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('it survives being disposed mid-sweep', (tester) async {
    final reveal = await pumpReveal(tester);

    final running = reveal.reveal(
      center: const Offset(50, 50),
      change: () {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Navigating away while the sweep runs must not leave a dangling image or
    // throw from a `setState` after dispose.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await running;

    expect(tester.takeException(), isNull);
  });
}
