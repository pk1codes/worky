import 'package:flutter_test/flutter_test.dart';
import 'package:worky/src/api.dart';

void main() {
  test('a 429 longer than 10 seconds is the daily contact cap', () {
    expect(ApiException(429, retryAfter: 11).dayCap, isTrue);
    expect(ApiException(429, retryAfter: 10).dayCap, isFalse);
    expect(ApiException(404, retryAfter: 99).dayCap, isFalse);
  });
}
