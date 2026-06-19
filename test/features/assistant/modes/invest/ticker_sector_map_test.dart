import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/ticker_sector_map.dart';

void main() {
  group('tickerSectorMap', () {
    test('includes LATAM and ETF tickers', () {
      expect(sectorForTicker('GGAL'), 'Financials');
      expect(sectorForTicker('YPF'), 'Energy');
      expect(sectorForTicker('MELI'), 'Consumer');
      expect(sectorForTicker('SPY'), 'Financials');
      expect(sectorForTicker('QQQ'), 'Technology');
    });

    test('returns null for unknown tickers', () {
      expect(sectorForTicker('ZZZZ'), isNull);
    });
  });
}
