import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_calendar_repository_impl.dart';

const _fiscalQuarterLabels = ['T1', 'T2', 'T3', 'T4'];

/// Adds `earnings_calendar` and `earnings_calendar_status` to the explore
/// snapshot for every ticker already present in `explore_tickers`.
///
/// A diferencia de las noticias, no se gatea por una detección de keywords
/// en el mensaje: una consulta a Finnhub por ticker es barata (una request
/// HTTP), así que se trae siempre que haya tickers en el snapshot y sea el
/// modelo — vía las reglas de prompt — quien decida si la pregunta amerita
/// mostrar el widget de calendario de resultados.
class ExploreEarningsEnricher {
  ExploreEarningsEnricher({EarningsCalendarRepository? earningsRepository})
    : _earningsRepository =
          earningsRepository ?? FinnhubEarningsCalendarRepositoryImpl();

  final EarningsCalendarRepository _earningsRepository;

  /// [earnings_calendar_status] is one of: `ok`, `empty`, `failed`. A
  /// fourth state, `locked` (user's plan doesn't include this), is NOT set
  /// here — this enricher only ever runs when the caller already confirmed
  /// the user is entitled (see `ExploreContextBuilder.build`'s
  /// `earningsAllowed` param, which sets `locked` directly without calling
  /// this class at all).
  Future<Map<String, Object?>> enrich({
    required Map<String, Object?> snapshot,
  }) async {
    final exploreTickers = snapshot['explore_tickers'];
    final tickers =
        exploreTickers is Map<String, Object?> ? exploreTickers.keys : const <String>[];

    if (tickers.isEmpty) {
      return {
        ...snapshot,
        'earnings_calendar': <String, Object?>{},
        'earnings_calendar_status': 'empty',
      };
    }

    final calendar = <String, Object?>{};
    var anyFailed = false;

    for (final ticker in tickers) {
      // Defensa extra sobre el contrato Either de EarningsCalendarRepository:
      // si una implementación del repo llega a lanzar en vez de devolver
      // Left, un ticker con problemas no debe tumbar el resto del snapshot.
      try {
        final nextResult = await _earningsRepository.getNextEarningsDate(
          ticker,
        );
        final latestResult = await _earningsRepository
            .getLatestEarningsResult(ticker);

        final next = nextResult.fold((_) {
          anyFailed = true;
          return null;
        }, (value) => value);
        final latest = latestResult.fold((_) {
          anyFailed = true;
          return null;
        }, (value) => value);

        final entry = <String, Object?>{};
        if (next != null) entry['next_report'] = _nextReportToJson(next);
        if (latest != null && latest.hasEpsComparison) {
          entry['latest_result'] = _latestResultToJson(latest);
        }
        if (entry.isNotEmpty) calendar[ticker] = entry;
      } catch (_) {
        anyFailed = true;
      }
    }

    final status = calendar.isNotEmpty ? 'ok' : (anyFailed ? 'failed' : 'empty');

    return {
      ...snapshot,
      'earnings_calendar': calendar,
      'earnings_calendar_status': status,
    };
  }

  Map<String, Object?> _nextReportToJson(EarningsCalendarEntry entry) {
    return {
      'date_label': _dateLabel(entry.reportDate),
      'fiscal_period_label': _fiscalPeriodLabel(
        entry.fiscalQuarter,
        entry.fiscalYear,
      ),
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
