import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/api.dart';

void main() {
  test('a move from Mumbai to Kuwait leaves the cached shelf', () {
    expect(viewerLeftShelf(19.07, 72.87, 29.31, 47.97), isTrue);
    expect(viewerLeftShelf(29.31, 47.97, 29.34, 47.99), isFalse);
    expect(viewerLeftShelf(null, null, 29.31, 47.97), isFalse);
  });
}
