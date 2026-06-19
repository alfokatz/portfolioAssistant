import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/yahoo_ticker_search_client.dart';

class _FakeSearchClient extends YahooTickerSearchClient {
  _FakeSearchClient(this._resultsByQuery);

  final Map<String, List<TickerSearchHit>> _resultsByQuery;

  @override
  Future<List<TickerSearchHit>> search(String query, {int limit = 3}) async {
    final key = query.trim().toLowerCase();
    return _resultsByQuery[key]?.take(limit).toList() ?? const [];
  }
}

void main() {
  group('TickerResolver', () {
    test('prefers explicit symbols over search', () async {
      final tickers = await TickerResolver.resolveTickers(
        'AAPL vs NVDA',
        searchClient: _FakeSearchClient({
          'aapl vs nvda': [
            const TickerSearchHit(symbol: 'WRONG', quoteType: 'EQUITY'),
          ],
        }),
      );

      expect(tickers, ['AAPL', 'NVDA']);
    });

    test('searches Yahoo when no explicit symbol is present', () async {
      final tickers = await TickerResolver.resolveTickers(
        'como le fue a la accion de takes two esta semana',
        searchClient: _FakeSearchClient({
          'takes two': [
            const TickerSearchHit(
              symbol: 'TTWO',
              quoteType: 'EQUITY',
              shortName: 'Take-Two Interactive',
            ),
          ],
        }),
      );

      expect(tickers, ['TTWO']);
    });

    test('uses broad market proxy for market questions', () async {
      final tickers = await TickerResolver.resolveTickers(
        '¿Cómo está el mercado?',
        searchClient: _FakeSearchClient({}),
      );

      expect(tickers, ['SPY']);
    });
  });
}
