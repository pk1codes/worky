import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/browse_screen.dart';
import 'package:worky/src/chrome.dart';
import 'package:worky/src/langs.dart';
import 'package:worky/src/session.dart';

void main() {
  test('whatsapp numbers use a real mobile check', () {
    expect(validPhone('+919876543210'), isTrue);
    expect(validPhone('+91910000101'), isFalse);
  });

  test('third card scrolls fully into a phone-width row', () {
    const viewport = 336.0;
    const maxExtent = 308.0;
    final target = stripRevealOffset(
      index: 2,
      pixels: 0,
      viewport: viewport,
      maxExtent: maxExtent,
    );
    expect(target, 308);
    const start = 12.0 + 2 * (150.0 + 12.0);
    const end = start + 296.0;
    expect(start, greaterThanOrEqualTo(target));
    expect(end, lessThanOrEqualTo(target + viewport));
  });

  testWidgets('third poster stays inside a phone-width strip', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 336,
              height: 210,
              child: ListView.separated(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey(index),
                  width: index == 2 ? 296 : 150,
                  height: 190,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final position = scroll.position;
    scroll.jumpTo(
      stripRevealOffset(
        index: 2,
        pixels: position.pixels,
        viewport: position.viewportDimension,
        maxExtent: position.maxScrollExtent,
      ),
    );
    await tester.pump();
    final box = tester.getRect(find.byKey(const ValueKey(2)));
    final strip = tester.getRect(find.byType(ListView));
    expect(box.left, greaterThanOrEqualTo(strip.left));
    expect(box.right, lessThanOrEqualTo(strip.right));
  });

  test('an open card already on screen does not scroll', () {
    expect(
      stripRevealOffset(index: 0, pixels: 0, viewport: 336, maxExtent: 308),
      0,
    );
  });

  test('language pack has twelve spoken names', () {
    expect(kLangs, hasLength(12));
    for (final code in kLangs) {
      expect(kAutonym[code], isNotEmpty);
      expect(kLangColor[code], isNotNull);
    }
  });

  testWidgets('labeled icon keeps the word inside the 72px button', (
    tester,
  ) async {
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
    expect(
      tester.getSize(find.byType(IconButton)).height,
      greaterThanOrEqualTo(64),
    );
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

  testWidgets('header flag is a 16px named circle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            label: 'India',
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
              child: CircleFlag('IN', size: 16),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('India'), findsOneWidget);
    expect(tester.getSize(find.byType(CircleFlag)), const Size(16, 16));
    expect(tester.takeException(), isNull);
  });
}
