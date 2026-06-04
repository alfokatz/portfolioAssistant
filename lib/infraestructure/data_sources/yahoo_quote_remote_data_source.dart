import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/data_sources/quote_remote_data_source.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:yahoo_finance_data_reader/yahoo_finance_data_reader.dart';

class _CachedQuote {
  final double price;
  final DateTime fetchedAt;

  _CachedQuote({required this.price, required this.fetchedAt});
}

class YahooQuoteRemoteDataSource implements QuoteRemoteDataSource {
  final YahooFinanceDailyReader _reader;
  final Map<String, _CachedQuote> _priceCache = {};
  final Map<String, List<PriceCandle>> _historyCache = {};
  final Duration _cacheTtl;

  YahooQuoteRemoteDataSource({
    YahooFinanceDailyReader? reader,
    Duration? cacheTtl,
  })  : _reader = reader ?? YahooFinanceDailyReader(),
        _cacheTtl = cacheTtl ??
            Duration(
              minutes: int.tryParse(
                    dotenv.env['YAHOO_CACHE_TTL_MINUTES'] ?? '10',
                  ) ??
                  10,
            );

  String _symbol(String ticker) => PortfolioCalculator.normalizeTicker(ticker);

  bool _isFresh(DateTime fetchedAt) =>
      DateTime.now().difference(fetchedAt) < _cacheTtl;

  @override
  Future<double> getCurrentPrice(String ticker) async {
    final symbol = _symbol(ticker);
    final cached = _priceCache[symbol];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      return cached.price;
    }

    final candles = await getHistoricalDaily(symbol);
    if (candles.isEmpty) {
      throw Exception('No price data for $symbol');
    }
    final price = candles.last.close;
    _priceCache[symbol] = _CachedQuote(price: price, fetchedAt: DateTime.now());
    return price;
  }

  @override
  Future<List<PriceCandle>> getHistoricalDaily(String ticker) async {
    final symbol = _symbol(ticker);
    final cached = _historyCache[symbol];
    if (cached != null && cached.isNotEmpty) {
      final firstCheck = _priceCache[symbol];
      if (firstCheck != null && _isFresh(firstCheck.fetchedAt)) {
        return cached;
      }
    }

    final response = await _reader.getDailyDTOs(symbol);
    final candles = response.candlesData
        .map(
          (c) => PriceCandle(
            date: c.date,
            close: c.close,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    _historyCache[symbol] = candles;
    if (candles.isNotEmpty) {
      _priceCache[symbol] = _CachedQuote(
        price: candles.last.close,
        fetchedAt: DateTime.now(),
      );
    }
    return candles;
  }
}

final quoteRemoteDataSourceProvider = Provider<QuoteRemoteDataSource>(
  (ref) => YahooQuoteRemoteDataSource(),
);
