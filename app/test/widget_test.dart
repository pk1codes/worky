import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/chrome.dart';
import 'package:worky/src/langs.dart';

void main() {
  test('language pack has twelve spoken names', () {
    expect(kLangs, hasLength(12));
    for (final code in kLangs) {
      expect(kAutonym[code], isNotEmpty);
      expect(kLangColor[code], isNotNull);
    }
  });

  testWidgets('labeled icon keeps the word inside the 72px button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BigIcon(
            icon: Icons.check,
            label: 'Delete account',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(IconButton));
    expect(size, const Size(72, 72));
    expect(find.text('Delete account'), findsOneWidget);
  });
}
