import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/langs.dart';

void main() {
  test('language pack has twelve spoken names', () {
    expect(kLangs, hasLength(12));
    for (final code in kLangs) {
      expect(kAutonym[code], isNotEmpty);
      expect(kLangColor[code], isNotNull);
    }
  });
}
