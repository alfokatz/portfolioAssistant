import 'package:portfolio_assistant/features/assistant/tools/plan_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/report_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Un ticker de la lista de seguimiento en la card `QaWatchlist`.
class WatchlistCardItem {
  const WatchlistCardItem({
    required this.ticker,
    this.price,
    this.dayPct,
    this.sinceAddedPct,
    this.alertsOn = true,
  });

  final String ticker;
  final double? price;
  final double? dayPct;
  final double? sinceAddedPct;
  final bool alertsOn;
}

/// La lista de seguimiento tal como la trajo `get_watchlist` — nunca lo
/// que escribió el modelo. Gana la llamada `ok` más reciente.
class WatchlistCardData {
  const WatchlistCardData(this.items);

  final List<WatchlistCardItem> items;

  /// Para el chequeo de que el texto no repita ni invente cifras.
  List<double> get backingNumbers => [
    for (final i in items) ...[
      if (i.price != null) i.price!,
      if (i.dayPct != null) i.dayPct!,
      if (i.dayPct != null) i.dayPct!.abs(),
      if (i.sinceAddedPct != null) i.sinceAddedPct!,
      if (i.sinceAddedPct != null) i.sinceAddedPct!.abs(),
    ],
    items.length.toDouble(),
  ];

  static WatchlistCardData? from(TurnEvidence evidence) {
    for (final call in evidence.calls.reversed) {
      if (call.name != PlanTools.getWatchlist || call.status != 'ok') continue;
      final items = [
        for (final i in (call.result['items'] as List? ?? const []))
          if (i is Map && i['ticker'] is String)
            WatchlistCardItem(
              ticker: (i['ticker'] as String).toUpperCase(),
              price: _num(i['price']),
              dayPct: _num(i['day_change_pct']),
              sinceAddedPct: _num(i['since_added_pct']),
              alertsOn: i['alerts_on'] != false,
            ),
      ];
      return items.isEmpty ? null : WatchlistCardData(items);
    }
    return null;
  }
}

/// Lo que más movió la cartera en la semana (del informe).
class ReportCardMover {
  const ReportCardMover({
    required this.ticker,
    required this.movePct,
    this.why,
  });

  final String ticker;
  final double movePct;
  final String? why;
}

/// El informe semanal tal como lo trajo `get_weekly_report` (lo mismo que
/// muestra la Home).
class WeeklyReportCardData {
  const WeeklyReportCardData({
    required this.weekStart,
    required this.changePct,
    required this.changeAbs,
    this.valueEnd,
    this.sp500Pct,
    this.movers = const [],
    this.reading,
  });

  /// Lunes de la semana ("2026-10-19").
  final String weekStart;
  final double changePct;
  final double changeAbs;
  final double? valueEnd;
  final double? sp500Pct;
  final List<ReportCardMover> movers;
  final String? reading;

  List<double> get backingNumbers => [
    changePct,
    changePct.abs(),
    changeAbs,
    changeAbs.abs(),
    if (valueEnd != null) valueEnd!,
    if (sp500Pct != null) sp500Pct!,
    if (sp500Pct != null) sp500Pct!.abs(),
    for (final m in movers) ...[m.movePct, m.movePct.abs()],
  ];

  static WeeklyReportCardData? from(TurnEvidence evidence) {
    for (final call in evidence.calls.reversed) {
      if (call.name != ReportTools.getWeeklyReport || call.status != 'ok') {
        continue;
      }
      final r = call.result['report'];
      if (r is! Map) return null;
      final pct = _num(r['change_pct']);
      final abs = _num(r['change_abs']);
      if (pct == null || abs == null) return null;
      return WeeklyReportCardData(
        weekStart: '${r['week'] ?? ''}',
        changePct: pct,
        changeAbs: abs,
        valueEnd: _num(r['value_end']),
        sp500Pct: _num(r['sp500_pct']),
        movers: [
          for (final m in (r['movers'] as List? ?? const []))
            if (m is Map &&
                m['ticker'] is String &&
                _num(m['move_pct']) != null)
              ReportCardMover(
                ticker: m['ticker'] as String,
                movePct: _num(m['move_pct'])!,
                why: m['why'] is String ? m['why'] as String : null,
              ),
        ],
        reading: r['reading'] is String ? r['reading'] as String : null,
      );
    }
    return null;
  }
}

double? _num(Object? v) => v is num ? v.toDouble() : null;
