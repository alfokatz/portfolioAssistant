import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_json.dart';

void main() {
  test('non-finite numbers become null, in maps and lists; the rest stays', () {
    final safe = widgetJsonSafe({
      'a': double.nan,
      'b': double.infinity,
      'c': 1.5,
      'd': 2,
      'e': 'x',
      'f': [double.negativeInfinity, 3.0, null],
      'g': {'h': double.nan, 'i': true},
    });
    expect(safe, {
      'a': null,
      'b': null,
      'c': 1.5,
      'd': 2,
      'e': 'x',
      'f': [null, 3.0, null],
      'g': {'h': null, 'i': true},
    });
    expect(() => jsonEncode(safe), returnsNormally);
  });
}
