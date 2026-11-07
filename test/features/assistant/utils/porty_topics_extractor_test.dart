// De qué tickers habló el usuario en un turno (porty_topics): lo que pidió
// él, no lo que eligió el modelo, con el precio de get_quote.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_topics_extractor.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

ToolCallRecord _quote(Map<String, double?> prices, {String status = 'ok'}) =>
    ToolCallRecord(
      name: 'get_quote',
      args: {'tickers': prices.keys.toList()},
      result: {
        'status': status,
        'tickers': {
          for (final MapEntry(:key, :value) in prices.entries)
            key:
                value == null
                    ? {'fetch_ok': false}
                    : {'fetch_ok': true, 'current_price': value},
        },
      },
    );

ToolCallRecord _news(List<String> tickers) => ToolCallRecord(
  name: 'get_news',
  args: {'tickers': tickers},
  result: const {'status': 'ok'},
);

void main() {
  group('PortyTopicsExtractor', () {
    test(
      'a pointed question: the ticker, its price and whether it is held',
      () {
        final drafts = PortyTopicsExtractor.extract(
          question: '¿Cómo viene AMZN?',
          calls: [
            _quote({'AMZN': 182.5}),
          ],
          heldTickers: const {'NVDA'},
        );
        expect(drafts.single.ticker, 'AMZN');
        expect(drafts.single.priceAt, 182.5);
        expect(drafts.single.held, isFalse);
        expect(drafts.single.question, '¿Cómo viene AMZN?');
      },
    );

    test('a name resolved with search_symbol counts', () {
      final drafts = PortyTopicsExtractor.extract(
        question: '¿Qué pasa con Amazon y las tecnológicas?',
        calls: [
          const ToolCallRecord(
            name: 'search_symbol',
            args: {'query': 'Amazon'},
            result: {'status': 'resolved', 'ticker': 'AMZN'},
          ),
          _news(['AMZN', 'MSFT', 'GOOGL']),
        ],
        heldTickers: const {},
      );
      expect([for (final d in drafts) d.ticker], ['AMZN']);
    });

    test('tickers the model chose (portfolio movers, ideas) do not count', () {
      final drafts = PortyTopicsExtractor.extract(
        question: '¿Por qué bajó mi cartera?',
        calls: [
          _news(['NVDA', 'AAPL', 'MSFT', 'TSLA']),
        ],
        heldTickers: const {'NVDA', 'AAPL', 'MSFT', 'TSLA'},
      );
      expect(drafts, isEmpty);
    });

    test('the screen ticker counts even among many', () {
      final drafts = PortyTopicsExtractor.extract(
        question: '¿Y comparado con el resto?',
        calls: [
          _quote({'NVDA': 180, 'AMD': 150, 'INTC': 30}),
        ],
        heldTickers: const {'NVDA'},
        screenTicker: 'nvda',
      );
      expect([for (final d in drafts) d.ticker], ['NVDA']);
      expect(drafts.single.held, isTrue);
    });

    test('a ticker must be a whole word in the question ("SPY" is not in '
        '"ESPYA")', () {
      final drafts = PortyTopicsExtractor.extract(
        question: 'ESPYA algo de KO, MO y PG',
        calls: [
          _quote({'SPY': 500, 'KO': 70, 'MO': 50, 'PG': 160}),
        ],
        heldTickers: const {},
      );
      expect([for (final d in drafts) d.ticker], ['KO', 'MO', 'PG']);
    });

    test('locked data does not count; without a price, still recorded '
        'without one; at most 3 per turn', () {
      expect(
        PortyTopicsExtractor.extract(
          question: '¿Cómo viene AMZN?',
          calls: [
            _quote({'AMZN': null}, status: 'locked'),
          ],
          heldTickers: const {},
        ),
        isEmpty,
      );
      final noPrice = PortyTopicsExtractor.extract(
        question: '¿Qué noticias hay de AMZN?',
        calls: [
          _news(['AMZN']),
        ],
        heldTickers: const {},
      );
      expect(noPrice.single.priceAt, isNull);
      final many = PortyTopicsExtractor.extract(
        question: 'Comparame AAPL MSFT GOOGL AMZN META',
        calls: [
          _quote({'AAPL': 1, 'MSFT': 1, 'GOOGL': 1, 'AMZN': 1, 'META': 1}),
        ],
        heldTickers: const {},
      );
      expect(many, hasLength(PortyTopicsExtractor.maxPerTurn));
    });
  });
}
