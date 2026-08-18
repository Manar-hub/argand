import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:argand/main.dart';

void main() {
  testWidgets('WhisperScreen renders in its initial ready state', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    expect(find.text('Whisper Engine Test'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Transcribe test file'), findsOneWidget);
  });
}
