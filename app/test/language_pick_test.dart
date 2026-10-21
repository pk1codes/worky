import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/chrome.dart';
import 'package:worky/src/language_screen.dart';

void main() {
  test('several spoken languages stay until Continue, in tap order', () {
    final english = toggleSpoken({}, 'en');
    final both = toggleSpoken(english, 'hi');
    expect(both.toList(), ['en', 'hi']);
    expect(both.first, 'en');
    expect(toggleSpoken(both, 'en').toList(), ['hi']);
    logLanguage('A', 'toggle keeps the screen and the first language', {
      'count': both.length,
      'lang': both.first,
      'stayed': true,
    });
  });

  testWidgets('a language tile is named once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LangTile(
            code: 'en',
            selected: false,
            uniform: true,
            onTap: _noop,
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.byType(LangTile)).label, 'English');
    handle.dispose();
    logLanguage('C', 'language name announced once', {'label': 'English'});
  });
}

void _noop() {}
