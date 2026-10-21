import 'dart:ui' as ui;

import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('the wordmark keeps space between each letter', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load('assets/worky.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final bytes = (await image.toByteData())!;
    final gaps = <int>[];
    var empty = 0;
    var seenInk = false;
    for (var x = 0; x < image.width; x++) {
      var ink = false;
      for (var y = 0; y < image.height; y += 2) {
        final i = (y * image.width + x) * 4;
        if (bytes.getUint8(i + 3) > 20) {
          ink = true;
          break;
        }
      }
      if (ink) {
        if (seenInk && empty > 8) gaps.add(empty);
        seenInk = true;
        empty = 0;
      } else {
        empty++;
      }
    }
    expect(gaps.length, greaterThanOrEqualTo(4));
    expect(gaps.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(40));

    final phone = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetHeight: 90,
    );
    final phoneFrame = await phone.getNextFrame();
    final phoneImage = phoneFrame.image;
    final phoneBytes = (await phoneImage.toByteData())!;
    final phoneGaps = <int>[];
    empty = 0;
    seenInk = false;
    for (var x = 0; x < phoneImage.width; x++) {
      var ink = false;
      for (var y = 0; y < phoneImage.height; y++) {
        final i = (y * phoneImage.width + x) * 4;
        if (phoneBytes.getUint8(i + 3) > 20) {
          ink = true;
          break;
        }
      }
      if (ink) {
        if (seenInk && empty > 2) phoneGaps.add(empty);
        seenInk = true;
        empty = 0;
      } else {
        empty++;
      }
    }
    expect(phoneGaps.length, greaterThanOrEqualTo(4));
    expect(phoneGaps.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(8));
  });

  test('a saved India number can be confirmed, and does not skip setup', () {
    expect(indiaMobileDigits('+919876543210'), '9876543210');
    expect(indiaMobileDigits('+96550000000'), isNull);
    expect(indiaMobileDigits(null), isNull);
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

  testWidgets('a tall open strip scrolls its details above the Post button', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: 72),
              children: const [
                SizedBox(height: 80),
                SizedBox(key: Key('strip'), height: 560),
                SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
    final strip = tester.getRect(find.byKey(const Key('strip')));
    final list = tester.getRect(find.byType(ListView));
    scroll.jumpTo(
      revealOpenOffset(
        topInViewport: strip.top - list.top,
        height: strip.height,
        pixels: scroll.position.pixels,
        viewport: scroll.position.viewportDimension,
        maxExtent: scroll.position.maxScrollExtent,
      ),
    );
    await tester.pump();
    final moved = tester.getRect(find.byKey(const Key('strip')));
    final view = tester.getRect(find.byType(ListView));
    expect(moved.bottom, lessThanOrEqualTo(view.bottom - 72 + 1));
  });

  test('an open strip scrolls until its details clear the Post button', () {
    final target = revealOpenOffset(
      topInViewport: 80,
      height: 560,
      pixels: 0,
      viewport: 400,
      maxExtent: 800,
    );
    expect(target, 80 + 560 - (400 - 72));
  });

  test('an open strip already clear of the Post button stays put', () {
    expect(
      revealOpenOffset(
        topInViewport: 0,
        height: 200,
        pixels: 40,
        viewport: 400,
        maxExtent: 800,
      ),
      40,
    );
  });

  test('a closed card leaves most of a phone map visible', () {
    const cap = 640.0;
    final closed = mapSheetExtent(cardOpen: false, cap: cap);
    final open = mapSheetExtent(cardOpen: true, cap: cap);
    expect(cap - closed, greaterThan(closed));
    expect(cap - open, lessThan(80));
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
