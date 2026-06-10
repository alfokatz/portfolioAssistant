import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_extractor.dart';

void main() {
  group('TickerExtractor', () {
    test('extracts uppercase tickers from message', () {
      expect(
        TickerExtractor.extractTickers('Qué pasó con AAPL y NVDA hoy?'),
        ['AAPL', 'NVDA'],
      );
    });

    test('filters Spanish and English stop words in caps', () {
      expect(
        TickerExtractor.extractTickers('YO QUE COMO EL LA A I'),
        isEmpty,
      );
    });

    test('returns max 3 unique tickers', () {
      expect(
        TickerExtractor.extractTickers(
          'AAPL MSFT GOOG AMZN TSLA META',
        ),
        ['AAPL', 'MSFT', 'GOOG'],
      );
    });

    test('does not duplicate repeated tickers', () {
      expect(
        TickerExtractor.extractTickers('AAPL AAPL NVDA'),
        ['AAPL', 'NVDA'],
      );
    });

    test('ignores lowercase tokens', () {
      expect(
        TickerExtractor.extractTickers('aapl nvda'),
        isEmpty,
      );
    });

    test('extracts tickers up to 5 letters', () {
      expect(
        TickerExtractor.extractTickers('Compare GOOGL and AMZN'),
        ['GOOGL', 'AMZN'],
      );
    });

    test('does not extract C from accented Como at start of question', () {
      expect(
        TickerExtractor.extractTickers('¿Cómo está el mercado?'),
        isEmpty,
      );
    });

    test('does not extract false positives from all-caps Spanish sentence', () {
      expect(
        TickerExtractor.extractTickers('¿COMO ESTA EL MERCADO?'),
        isEmpty,
      );
    });

    test('still extracts explicit single-letter ticker as whole word', () {
      expect(
        TickerExtractor.extractTickers('¿Cómo está C hoy?'),
        ['C'],
      );
    });
  });
}
