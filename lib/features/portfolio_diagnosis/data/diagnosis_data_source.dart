import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/etf_holdings_fetcher.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';

/// Lo que el diagnóstico necesita de afuera: qué tickers son fondos (y qué
/// tienen adentro), el sector de las acciones y la serie del S&P 500. Todo
/// por el proxy `yahoo`, sin el modelo y sin gastar consultas: funciona en
/// Free.
class DiagnosisDataSource {
  DiagnosisDataSource({
    required QuoteRepository quotes,
    EtfHoldingsFetcher? etfs,
    YahooCompanyProfileClient? profiles,
  }) : _quotes = quotes,
       _etfs = etfs ?? EtfHoldingsFetcher(),
       _profiles = profiles ?? YahooCompanyProfileClient();

  final QuoteRepository _quotes;
  final EtfHoldingsFetcher _etfs;
  final YahooCompanyProfileClient _profiles;

  static const sp500Ticker = '^GSPC';

  /// Cada parte con su tope: lo que no llega a tiempo queda vacío y ese
  /// hallazgo no sale (el resto, sí).
  static const _timeout = Duration(seconds: 10);

  /// Fondos con lo que se sabe de ellos. Lo que no es fondo, afuera.
  Future<Map<String, FundLook>> funds(List<String> tickers) async {
    if (tickers.isEmpty) return const {};
    try {
      final result = await _etfs.fetch(tickers).timeout(_timeout);
      final etfs = result['etfs'];
      if (etfs is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in etfs.entries)
          if (value is Map)
            '$key'.toUpperCase(): FundLook.fromJson(
              Map<String, Object?>.from(value),
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Sector (en español) de cada acción. Sin dato, "Sin clasificar".
  Future<Map<String, String>> sectors(List<String> stocks) async {
    if (stocks.isEmpty) return const {};
    try {
      final profiles = await _profiles.fetchProfiles(stocks).timeout(_timeout);
      return SectorResolver.fromProfiles(stocks, profiles);
    } catch (_) {
      return const {};
    }
  }

  Future<List<PriceCandle>> sp500() async {
    try {
      final result = await _quotes
          .getHistoricalDaily(sp500Ticker)
          .timeout(_timeout);
      return result.fold<List<PriceCandle>>(
        (_) => const [],
        (candles) => candles,
      );
    } catch (_) {
      return const [];
    }
  }
}

final diagnosisDataSourceProvider = Provider<DiagnosisDataSource>(
  (ref) => DiagnosisDataSource(quotes: ref.watch(quoteRepositoryProvider)),
);
