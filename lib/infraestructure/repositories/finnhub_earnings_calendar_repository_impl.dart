import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Nunca lanza: ante red/timeout/401 devuelve `Left(HttpError)`; ante un
/// ticker sin dato (sin reporte próximo, o sin resultado ya publicado)
/// devuelve `Right(null)` — la misma distinción absence-vs-error que ya usa
/// el resto de la capa de datos externa de la app.
class FinnhubEarningsCalendarRepositoryImpl implements EarningsCalendarRepository {
  FinnhubEarningsCalendarRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  ) async {
    final result = await _fetchCalendar(
      ticker,
      from: DateTime.now(),
      to: DateTime.now().add(const Duration(days: 180)),
    );

    return result.fold((error) => Left(error), (entries) {
      final today = _dateOnly(DateTime.now());
      final upcoming =
          entries.where((e) => !e.date.isBefore(today)).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      if (upcoming.isEmpty) return const Right(null);

      final next = upcoming.first;
      return Right(
        EarningsCalendarEntry(
          ticker: ticker.toUpperCase(),
          reportDate: next.date,
          fiscalQuarter: next.quarter,
          fiscalYear: next.year,
          epsEstimate: next.epsEstimate,
        ),
      );
    });
  }

  @override
  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  ) async {
    final result = await _fetchCalendar(
      ticker,
      from: DateTime.now().subtract(const Duration(days: 200)),
      to: DateTime.now(),
    );

    return result.fold((error) => Left(error), (entries) {
      final reported =
          entries.where((e) => e.epsActual != null).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (reported.isEmpty) return const Right(null);

      final latest = reported.first;
      return Right(
        EarningsReportResult(
          ticker: ticker.toUpperCase(),
          reportDate: latest.date,
          epsActual: latest.epsActual,
          epsEstimate: latest.epsEstimate,
          revenueActual: latest.revenueActual,
          revenueEstimate: latest.revenueEstimate,
        ),
      );
    });
  }

  Future<Either<HttpError, List<_RawEarningsEntry>>> _fetchCalendar(
    String ticker, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_client.hasApiKey) {
      return Left(
        HttpError(
          code: 'missing_api_key',
          message: 'FINNHUB_API_KEY no configurada',
        ),
      );
    }

    try {
      final response = await _client.get(
        '/calendar/earnings',
        queryParameters: {
          'symbol': ticker.toUpperCase(),
          'from': FinnhubHttpClient.formatDate(from),
          'to': FinnhubHttpClient.formatDate(to),
        },
      );

      if (response.statusCode != 200) {
        return Left(HttpError(code: 'finnhub_error_${response.statusCode}'));
      }

      final data = response.data;
      final raw = data is Map ? data['earningsCalendar'] : null;
      if (raw is! List) return const Right([]);

      final upperTicker = ticker.toUpperCase();
      final entries =
          raw
              .whereType<Map>()
              .map(_parseEntry)
              .whereType<_RawEarningsEntry>()
              .where((e) => e.symbol.toUpperCase() == upperTicker)
              .toList();
      return Right(entries);
    } on DioException catch (e) {
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  _RawEarningsEntry? _parseEntry(Map raw) {
    final dateStr = raw['date'] as String?;
    final symbol = raw['symbol'] as String?;
    if (dateStr == null || symbol == null) return null;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return null;

    return _RawEarningsEntry(
      symbol: symbol,
      date: date,
      quarter: (raw['quarter'] as num?)?.toInt(),
      year: (raw['year'] as num?)?.toInt(),
      epsActual: (raw['epsActual'] as num?)?.toDouble(),
      epsEstimate: (raw['epsEstimate'] as num?)?.toDouble(),
      revenueActual: (raw['revenueActual'] as num?)?.toDouble(),
      revenueEstimate: (raw['revenueEstimate'] as num?)?.toDouble(),
    );
  }

  static DateTime _dateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);
}

class _RawEarningsEntry {
  _RawEarningsEntry({
    required this.symbol,
    required this.date,
    this.quarter,
    this.year,
    this.epsActual,
    this.epsEstimate,
    this.revenueActual,
    this.revenueEstimate,
  });

  final String symbol;
  final DateTime date;
  final int? quarter;
  final int? year;
  final double? epsActual;
  final double? epsEstimate;
  final double? revenueActual;
  final double? revenueEstimate;
}
