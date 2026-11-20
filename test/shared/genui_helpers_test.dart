import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';

void main() {
  group('GenUiHelpers', () {
    test('safeEnum returns default for invalid value', () {
      expect(
        GenUiHelpers.safeEnum('UP', ['up', 'down'], defaultValue: 'neutral'),
        'neutral',
      );
    });

    test('safeDouble parses string numbers', () {
      expect(GenUiHelpers.safeDouble('42.5', defaultValue: 0), 42.5);
      expect(GenUiHelpers.safeDouble('invalid', defaultValue: 1), 1);
    });

    test('safeString handles null', () {
      expect(GenUiHelpers.safeString(null, defaultValue: 'x'), 'x');
    });

    test('safeDoubleList maps list', () {
      expect(
        GenUiHelpers.safeDoubleList([1, '2.5', null]),
        [1, 2.5, 0],
      );
    });
  });
}
