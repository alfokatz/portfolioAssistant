import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_item.dart';
import 'package:portfolio_assistant/features/weekly_report/data/investor_pulse_client.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_relevance.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';

/// Junta los datos del informe de una semana: precios (Yahoo), titulares de
/// la semana (Google News, fallback Finnhub) y earnings de la semana
/// siguiente (Finnhub). Todo determinístico: el LLM recién entra después.
///
/// Nunca lanza. Si falla una fuente, ese bloque llega vacío con su flag de
/// falla; si fallan los precios de un ticker, queda en `missingPrices`.
class WeeklyReportInputBuilder {
  WeeklyReportInputBuilder({
    required QuoteRepository quotes,
    NewsFetcher? news,
    EarningsFetcher? earnings,
    InvestorPulseClient? investorPulse,
  }) : _quotes = quotes,
       _news = news ?? NewsFetcher(),
       _earnings = earnings ?? EarningsFetcher(),
       _pulse = investorPulse ?? InvestorPulseClient();

  final QuoteRepository _quotes;
  final NewsFetcher _news;
  final EarningsFetcher _earnings;
  final InvestorPulseClient _pulse;

  static const sp500Ticker = '^GSPC';

  /// Tickers con noticias: los de más peso, más los que más movieron la
  /// cartera aunque pesen poco.
  static const newsTickersByWeight = 8;
  static const newsTickersByImpact = 3;
  static const newsPerTicker = 2;
  static const maxNews = 15;

  /// Earnings: los de más peso (cada ticker son 3 requests a Finnhub).
  static const maxEarningsTickers = 15;

  Future<WeeklyReportInput> build({
    required ReportWeek week,
    required List<Position> lots,
    List<ClosedPosition> closed = const [],
    bool numbersOnly = false,
  }) async {
    final tickers =
        {
          for (final lot in lots)
            PortfolioCalculator.normalizeTicker(lot.ticker),
        }.toList();

    final series = await Future.wait([
      for (final t in tickers) _candles(t),
      _candles(sp500Ticker),
    ]);
    final numbers = WeeklyPortfolioCalculator.compute(
      week: week,
      lots: lots,
      candles: {
        for (var i = 0; i < tickers.length; i++)
          if (series[i] != null) tickers[i]: series[i]!,
      },
      benchmark: series.last ?? const [],
      closed: closed,
    );
    // Solo números (Free/Premium sin degustación, o sin texto de Porty): sin
    // noticias, earnings ni inversores, que nadie va a leer.
    if (numbers.isEmpty || numbersOnly) {
      return WeeklyReportInput(
        numbers: numbers,
        news: const [],
        upcomingEarnings: const [],
        newsFailed: false,
        earningsFailed: false,
      );
    }

    final byWeight = [...numbers.positions]
      ..sort((a, b) => b.weightEnd.compareTo(a.weightEnd));
    final newsTickers =
        {
          for (final p in byWeight.take(newsTickersByWeight)) p.ticker,
          for (final p in numbers.positions.take(newsTickersByImpact)) p.ticker,
        }.toList();

    final results = await Future.wait([
      _weekNews(week, newsTickers, numbers),
      _nextWeekEarnings(week, [
        for (final p in byWeight.take(maxEarningsTickers)) p.ticker,
      ]),
      _investors(week, [for (final p in numbers.positions) p.ticker]),
    ]);
    final news = results[0] as ({List<WeeklyNewsItem> items, bool failed});
    final earnings =
        results[1] as ({List<UpcomingEarnings> items, bool failed});
    final investors =
        results[2] as ({List<RelatedPulseItem> items, bool failed});

    return WeeklyReportInput(
      numbers: numbers,
      news: news.items,
      upcomingEarnings: earnings.items,
      newsFailed: news.failed,
      earningsFailed: earnings.failed,
      investors: investors.items,
      investorsFailed: investors.failed,
    );
  }

  /// Titulares que intentan darle órdenes al modelo ("ignore previous
  /// instructions…"). No llegan al prompt: es más seguro que confiar en que
  /// el modelo los trate como texto.
  static bool looksLikeInstructions(String headline) =>
      _injection.hasMatch(headline);

  static final _injection = RegExp(
    r'ignore\s+(all\s+|any\s+|the\s+)?(previous|prior|above)|'
    r'disregard\s+(all\s+|the\s+)?(previous|prior|above)|'
    r'system\s+prompt|you\s+are\s+now|new\s+instructions|'
    r'ignor[aá]\s+(las\s+)?instrucciones|olvid[aá]\s+(las\s+)?instrucciones',
    caseSensitive: false,
  );

  Future<List<PriceCandle>?> _candles(String ticker) async {
    try {
      final result = await _quotes.getHistoricalDaily(ticker);
      return result.fold<List<PriceCandle>?>((_) => null, (c) => c);
    } catch (_) {
      return null;
    }
  }

  /// Titulares de lunes a viernes, intercalados por importancia del ticker
  /// (el primero de cada uno, después el segundo…), con ids `n1`… en ese
  /// orden.
  Future<({List<WeeklyNewsItem> items, bool failed})> _weekNews(
    ReportWeek week,
    List<String> tickers,
    WeeklyPortfolioNumbers numbers,
  ) async {
    if (tickers.isEmpty) {
      return (items: const <WeeklyNewsItem>[], failed: false);
    }
    try {
      final perTicker = await _news.fetchWindow(
        tickers,
        from: week.monday,
        to: week.endExclusive,
        perTicker: newsPerTicker,
      );
      final failedAll = perTicker.values.every((l) => l == null);
      // El orden de importancia: impacto en la semana (como `positions`).
      final ordered = [
        for (final p in numbers.positions)
          if (perTicker.containsKey(p.ticker)) p.ticker,
      ];
      final items = <WeeklyNewsItem>[];
      final seen = <String>{};
      for (var rank = 0; rank < newsPerTicker; rank++) {
        for (final ticker in ordered) {
          final list = perTicker[ticker];
          if (list == null || rank >= list.length) continue;
          final n = list[rank];
          // La misma nota puede venir por dos tickers (ej. GOOG y GOOGL).
          if (!seen.add(n.url)) continue;
          if (looksLikeInstructions(n.headline)) continue;
          if (items.length >= maxNews) break;
          items.add(
            WeeklyNewsItem(
              id: 'n${items.length + 1}',
              ticker: ticker,
              headline: n.headline,
              source: n.source,
              url: n.url,
              publishedAt: n.publishedAt,
            ),
          );
        }
      }
      return (items: items, failed: failedAll);
    } catch (_) {
      return (items: const <WeeklyNewsItem>[], failed: true);
    }
  }

  /// Super investors de la semana, con lo que toca la cartera primero. Los
  /// nombres de las compañías salen de la misma caché que usan las noticias.
  Future<({List<RelatedPulseItem> items, bool failed})> _investors(
    ReportWeek week,
    List<String> tickers,
  ) async {
    try {
      final results = await Future.wait([
        _pulse.fetch(week),
        Future.wait(tickers.map(_safeCompanyName)),
      ]);
      final items = results[0] as List<InvestorPulseItem>?;
      if (items == null) {
        return (items: const <RelatedPulseItem>[], failed: true);
      }
      final names = results[1] as List<String?>;
      return (
        items: InvestorPulseRelevance.selectForReport(
          items,
          holdings: {
            for (var i = 0; i < tickers.length; i++) tickers[i]: names[i],
          },
        ),
        failed: false,
      );
    } catch (_) {
      return (items: const <RelatedPulseItem>[], failed: true);
    }
  }

  Future<String?> _safeCompanyName(String ticker) async {
    try {
      return await _news.companyName(ticker);
    } catch (_) {
      return null;
    }
  }

  /// Reportes de lunes a viernes de la semana siguiente, por fecha.
  Future<({List<UpcomingEarnings> items, bool failed})> _nextWeekEarnings(
    ReportWeek week,
    List<String> tickers,
  ) async {
    if (tickers.isEmpty) {
      return (items: const <UpcomingEarnings>[], failed: false);
    }
    try {
      final result = await _earnings.fetch(tickers);
      final calendar =
          (result['earnings'] as Map?)?.cast<String, Object?>() ?? const {};
      final next = week.next;
      final items = <UpcomingEarnings>[];
      for (final MapEntry(key: ticker, value: entry) in calendar.entries) {
        final report = (entry as Map?)?['next_report'] as Map?;
        final date = DateTime.tryParse('${report?['date']}');
        if (date == null) continue;
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(next.monday) || day.isAfter(next.friday)) continue;
        items.add(
          UpcomingEarnings(
            ticker: ticker,
            date: day,
            timingLabel: report?['timing_label'] as String?,
            epsEstimate: (report?['eps_estimate'] as num?)?.toDouble(),
          ),
        );
      }
      items.sort((a, b) => a.date.compareTo(b.date));
      return (items: items, failed: result['status'] == 'failed');
    } catch (_) {
      return (items: const <UpcomingEarnings>[], failed: true);
    }
  }
}
