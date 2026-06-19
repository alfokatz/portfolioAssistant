import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/search_query_variants.dart';

void main() {
  group('SearchQueryVariants', () {
    test('includes depluralized take two variant for takes two', () {
      final variants = SearchQueryVariants.variants('takes two');

      expect(variants, contains('takes two'));
      expect(variants, contains('take two'));
    });

    test('includes hyphenated variant', () {
      expect(
        SearchQueryVariants.variants('take two'),
        contains('take-two'),
      );
    });
  });
}
