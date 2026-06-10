import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/broad_market_query.dart';

void main() {
  group('isBroadMarketQuery', () {
    test('detects Spanish market question', () {
      expect(isBroadMarketQuery('¿Cómo está el mercado?'), isTrue);
      expect(isBroadMarketQuery('como esta el mercado'), isTrue);
    });

    test('detects English market question', () {
      expect(isBroadMarketQuery('How is the market today?'), isTrue);
    });

    test('returns false for specific ticker question', () {
      expect(isBroadMarketQuery('¿Cómo está AAPL?'), isFalse);
    });
  });
}
