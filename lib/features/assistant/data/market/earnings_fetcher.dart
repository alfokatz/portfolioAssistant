import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_calendar_repository_impl.dart';

const _fiscalQuarterLabels = ['T1', 'T2', 'T3', 'T4'];

/// Próximo reporte (fecha, período fiscal, EPS esperado) y último resultado
/// (EPS real vs. esperado) por ticker — Finnhub `/calendar/earnings`.
class EarningsFetcher {
  EarningsFetcher({EarningsCalendarRepository? repository, Duration? cacheTtl})
    : _repository = repository ?? FinnhubEarningsCalendarRepositoryImpl(),
      _cache = TtlCache(cacheTtl ?? const Duration(hours: 6));

  final EarningsCalendarRepository _repository;
  final TtlCache<Map<String, Object?>> _cache;

  /// `{status: ok|empty|failed, earnings: {TICKER: {next_report?,
  /// latest_result?}}}`.
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final calendar = <String, Object?>{};
    var anyFailed = false;

    final entries = await Future.wait(tickers.map(_forTicker));
    for (var i = 0; i < tickers.length; i++) {
      final entry = entries[i];
      if (entry == null) {
        anyFailed = true;
      } else if (entry.isNotEmpty) {
        calendar[tickers[i]] = entry;
      }
    }

    return {
      'status': calendar.isNotEmpty ? 'ok' : (anyFailed ? 'failed' : 'empty'),
      'earnings': calendar,
    };
  }

  /// `null` = falló; `{}` = Finnhub no tiene nada para ese ticker.
  Future<Map<String, Object?>?> _forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    try {
      final results = await Future.wait([
        _repository.getNextEarningsDate(ticker),
        _repository.getLatestEarningsResult(ticker),
      ]);
      var failed = false;
      final next = results[0].fold((_) {
        failed = true;
        return null;
      }, (value) => value as EarningsCalendarEntry?);
      final latest = results[1].fold((_) {
        failed = true;
        return null;
      }, (value) => value as EarningsReportResult?);

      final entry = <String, Object?>{};
      if (next != null) entry['next_report'] = _nextReportToJson(next);
      if (latest != null && latest.hasEpsComparison) {
        entry['latest_result'] = _latestResultToJson(latest);
      }
      if (entry.isEmpty && failed) return null;
      if (!failed) _cache.put(ticker, entry);
      return entry;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _nextReportToJson(EarningsCalendarEntry entry) {
    return {
      'date_label': _dateLabel(entry.reportDate),
      'fiscal_period_label': _fiscalPeriodLabel(
        entry.fiscalQuarter,
        entry.fiscalYear,
      ),
      if (entry.epsEstimate != null) 'eps_estimate': entry.epsEstimate,
    };
  }

  Map<String, Object?> _latestResultToJson(EarningsReportResult result) {
    return {
      'report_date_label': _dateLabel(result.reportDate),
      'eps_actual': result.epsActual,
      'eps_estimate': result.epsEstimate,
      'beat': result.beatEstimate,
    };
  }

  String _fiscalPeriodLabel(int? quarter, int? year) {
    if (quarter == null || quarter < 1 || quarter > 4 || year == null) {
      return '';
    }
    return '${_fiscalQuarterLabels[quarter - 1]} FY${year.toString().substring(2)}';
  }

  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  String _dateLabel(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';
}
