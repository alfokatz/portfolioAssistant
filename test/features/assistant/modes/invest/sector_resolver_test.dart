import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/yahoo_sector_client.dart';

class _FakeYahooSectorClient extends YahooSectorClient {
  _FakeYahooSectorClient(this._sectors) : super(dio: null);

  final Map<String, String?> _sectors;

  @override
  Future<Map<String, String?>> fetchSectors(List<String> tickers) async {
    return {
      for (final ticker in tickers)
        ticker.toUpperCase(): _sectors[ticker.toUpperCase()],
    };
  }
}

void main() {
  group('SectorResolver', () {
    test('uses static map with Spanish labels', () async {
      final resolved = await SectorResolver.resolveForTickers(
        ['AAPL', 'NVDA'],
        yahooClient: _FakeYahooSectorClient({}),
      );

      expect(resolved['AAPL'], 'Tecnología');
      expect(resolved['NVDA'], 'Tecnología');
    });

    test('falls back to Yahoo for unknown tickers', () async {
      final resolved = await SectorResolver.resolveForTickers(
        ['GGAL'],
        yahooClient: _FakeYahooSectorClient({
          'GGAL': 'Financial Services',
        }),
      );

      expect(resolved['GGAL'], 'Finanzas');
    });

    test('uses Sin clasificar when Yahoo returns null', () async {
      final resolved = await SectorResolver.resolveForTickers(
        ['UNKNOWN'],
        yahooClient: _FakeYahooSectorClient({}),
      );

      expect(resolved['UNKNOWN'], 'Sin clasificar');
    });

    test('uses Sin clasificar when Yahoo client throws', () async {
      final resolved = await SectorResolver.resolveForTickers(
        ['UNKNOWN'],
        yahooClient: _ThrowingYahooSectorClient(),
      );

      expect(resolved['UNKNOWN'], 'Sin clasificar');
    });
  });
}

class _ThrowingYahooSectorClient extends YahooSectorClient {
  @override
  Future<Map<String, String?>> fetchSectors(List<String> tickers) async {
    throw StateError('network down');
  }
}
