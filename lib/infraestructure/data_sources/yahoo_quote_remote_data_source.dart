import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  final Dio _dio;
  final Map<String, _CachedQuote> _priceCache = {};
  final Map<String, List<PriceCandle>> _historyCache = {};
  final Duration _cacheTtl;

  YahooQuoteRemoteDataSource({
    YahooFinanceDailyReader? reader,
    Duration? cacheTtl,
    Dio? dio,
  })  : _reader = reader ?? YahooFinanceDailyReader(),
        _dio = dio ?? _createIntradayDio(),
        _cacheTtl = cacheTtl ??
            Duration(
              minutes: int.tryParse(
                    dotenv.env['YAHOO_CACHE_TTL_MINUTES'] ?? '10',
                  ) ??
                  10,
            );

  String _symbol(String ticker) =>
      PortfolioCalculator.toYahooFinanceSymbol(ticker);

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

  static const _intradayChartUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart';

  static Dio _createIntradayDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        // Sin User-Agent de navegador Yahoo responde 429.
        headers: {'User-Agent': 'Mozilla/5.0'},
      ),
    );
  }

  /// OJO: depende de un endpoint NO oficial ni documentado de Yahoo (el que
  /// usa su propio sitio para los gráficos) — el paquete
  /// `yahoo_finance_data_reader` solo trae velas diarias. Por eso tiene su
  /// propio manejo de errores, separado del resto de este data source:
  /// cualquier cosa inesperada (error HTTP, timeout, o un JSON con otra
  /// forma) se trata como "sin datos" y devuelve `[]` en vez de tirar, así
  /// el gráfico cae al mismo fallback que un ticker sin histórico.
  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_intradayChartUrl/${_symbol(ticker)}',
        queryParameters: {'range': '1d', 'interval': '5m'},
      );
      return parseIntradayChart(response.data);
    } catch (e) {
      debugPrint('Yahoo intraday failed for $ticker: $e');
      return const [];
    }
  }

  /// Parsea `chart.result[0]` (`timestamp[]` en segundos UTC +
  /// `indicators.quote[0].close[]`, con `null` en los intervalos sin
  /// operaciones). Cualquier forma distinta a la esperada devuelve `[]`.
  @visibleForTesting
  static List<PriceCandle> parseIntradayChart(Object? body) {
    try {
      final result = ((body as Map)['chart'] as Map)['result'] as List;
      final first = result.first as Map;
      final timestamps = first['timestamp'] as List;
      final closes =
          (((first['indicators'] as Map)['quote'] as List).first
              as Map)['close'] as List;
      final count = timestamps.length < closes.length
          ? timestamps.length
          : closes.length;
      final candles = <PriceCandle>[];
      for (var i = 0; i < count; i++) {
        final ts = timestamps[i];
        final close = closes[i];
        if (ts is! num || close is! num) continue;
        candles.add(
          PriceCandle(
            date: DateTime.fromMillisecondsSinceEpoch(
              ts.toInt() * 1000,
              isUtc: true,
            ).toLocal(),
            close: close.toDouble(),
          ),
        );
      }
      return candles;
    } catch (_) {
      return const [];
    }
  }
}

final quoteRemoteDataSourceProvider = Provider<QuoteRemoteDataSource>(
  (ref) => YahooQuoteRemoteDataSource(),
);
