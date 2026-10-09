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
    expect(tester.getSize(find.byType(IconButton)).height, greaterThanOrEqualTo(64));
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('header icon stays within 72px', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BigIcon(
            icon: Icons.map,
            label: 'Map',
            compact: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(IconButton));
    expect(size.width, 72);
    expect(size.height, lessThanOrEqualTo(64));
  });
}
