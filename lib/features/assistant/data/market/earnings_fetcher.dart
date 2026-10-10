import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/entities/earnings_surprise.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_history_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_calendar_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_history_repository_impl.dart';

const _fiscalQuarterLabels = ['T1', 'T2', 'T3', 'T4'];

/// Próximo reporte (fecha, momento del día, período fiscal, EPS esperado),
/// último resultado e historial de EPS de los últimos trimestres por
/// ticker — Finnhub `/calendar/earnings` + `/stock/earnings`.
///
/// El calendario muchas veces no trae el `epsActual` del último reporte;
/// `/stock/earnings` sí, así que `latest_result` cae al trimestre más
/// reciente del historial cuando el calendario no lo tiene.
class EarningsFetcher {
  EarningsFetcher({
    EarningsCalendarRepository? repository,
    EarningsHistoryRepository? historyRepository,
    Duration? cacheTtl,
  }) : _repository = repository ?? FinnhubEarningsCalendarRepositoryImpl(),
       // Un fake de calendario sin fake de historial (tests) no debe
       // terminar pegándole a Finnhub de verdad.
       _history =
           historyRepository ??
           (repository == null ? FinnhubEarningsHistoryRepositoryImpl() : null),
       _cache = TtlCache(cacheTtl ?? const Duration(hours: 6));

  /// Trimestres de historial que se le mandan al modelo (y dibuja la card).
  static const maxHistory = 4;

  final EarningsCalendarRepository _repository;
  final EarningsHistoryRepository? _history;
  final TtlCache<Map<String, Object?>> _cache;

  /// `{status: ok|empty|failed, earnings: {TICKER: {next_report?,
  /// latest_result?, history?}}}`.
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
      // Los tres requests arrancan juntos; se esperan de a uno solo para
      // conservar los tipos.
      final nextF = _repository.getNextEarningsDate(ticker);
      final latestF = _repository.getLatestEarningsResult(ticker);
      final historyF = _history?.getEpsHistory(ticker);

      var failed = false;
      T? onError<T>(Object _) {
        failed = true;
        return null;
      }

      final next = (await nextF).fold(onError<EarningsCalendarEntry>, (v) => v);
      final latest = (await latestF).fold(
        onError<EarningsReportResult>,
        (v) => v,
      );
      final quarters =
          historyF == null
              ? const <EarningsSurprise>[]
              : (await historyF).fold(
                    onError<List<EarningsSurprise>>,
                    (v) => v,
                  ) ??
                  const <EarningsSurprise>[];
      // Solo trimestres comparables, del más viejo al más nuevo: el orden
      // en que se leen (y se dibujan) de izquierda a derecha.
      final comparable =
          quarters
              .where((q) => q.hasEpsComparison)
              .take(maxHistory)
              .toList()
              .reversed
              .toList();

      final entry = <String, Object?>{};
      if (next != null) entry['next_report'] = _nextReportToJson(next);
      if (latest != null && latest.hasEpsComparison) {
        entry['latest_result'] = _latestResultToJson(latest);
      } else if (comparable.isNotEmpty) {
        entry['latest_result'] = _quarterToJson(comparable.last);
      }
      if (comparable.isNotEmpty) {
        entry['history'] = [for (final q in comparable) _quarterToJson(q)];
      }
      if (entry.isEmpty && failed) return null;
      // Un resultado parcial (p. ej. el historial falló) se devuelve pero
      // no se cachea: el próximo turno lo vuelve a intentar completo.
      if (!failed) _cache.put(ticker, entry);
      return entry;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _nextReportToJson(EarningsCalendarEntry entry) {
    final timing = _timingLabel(entry.hour);
    return {
      'date': _isoDate(entry.reportDate),
      'date_label': _dateLabel(entry.reportDate),
      'fiscal_period_label': _fiscalPeriodLabel(
        entry.fiscalQuarter,
        entry.fiscalYear,
      ),
      if (timing != null) 'timing_label': timing,
      if (entry.epsEstimate != null) 'eps_estimate': entry.epsEstimate,
    };
  }

  Map<String, Object?> _latestResultToJson(EarningsReportResult result) {
    return {
      'report_date_label': _dateLabel(result.reportDate),
      'eps_actual': result.epsActual,
      'eps_estimate': result.epsEstimate,
      'surprise_pct': _surprisePct(result.epsActual!, result.epsEstimate!),
      'beat': result.beatEstimate,
    };
  }

  Map<String, Object?> _quarterToJson(EarningsSurprise q) {
    final label = _fiscalPeriodLabel(q.fiscalQuarter, q.fiscalYear);
    return {
      if (label.isNotEmpty) 'fiscal_period_label': label,
      'eps_actual': q.epsActual,
      'eps_estimate': q.epsEstimate,
      'surprise_pct':
          q.surprisePercent != null
              ? _round1(q.surprisePercent!)
              : _surprisePct(q.epsActual!, q.epsEstimate!),
      'beat': q.beatEstimate,
    };
  }

  static double? _surprisePct(double actual, double estimate) {
    if (estimate == 0) return null;
    return _round1((actual - estimate) / estimate.abs() * 100);
  }

  static double _round1(double v) => double.parse(v.toStringAsFixed(1));

  static String? _timingLabel(String? hour) => switch (hour) {
    'bmo' => 'Antes de la apertura',
    'amc' => 'Después del cierre',
    'dmh' => 'Durante la sesión',
    _ => null,
  };

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

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
