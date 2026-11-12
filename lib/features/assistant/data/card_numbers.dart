import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/analysis_widgets.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ticker_price_data.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Los números de las cards de datos los pone la app, no el modelo: el
/// modelo elige la card y QUÉ mostrar (ticker, período, métricas…) y acá
/// se completan las cifras desde las tools del turno o el PORTFOLIO_BRIEF.
/// Escribe menos (la respuesta llega antes) y no hay cifras mal copiadas
/// (ver docs/superpowers/research/2026-10-15-porty-latencia.md, A1).
///
/// Lo aplica `AssistantAnswerReview.postProcess` antes de mostrar la
/// respuesta, así los números quedan escritos en el componente. Lo que la
/// evidencia no tiene queda como lo mandó el modelo (respuestas de
/// versiones anteriores, que todavía copiaban los números).
abstract final class CardNumbers {
  static const components = {
    'QaPriceChart',
    'QaTickerSnapshot',
    'QaTickerMove',
    'QaPeriodChange',
    'QaPositionsSnapshot',
    'QaPnLBreakdown',
    'QaEarningsCalendar',
    'QaFundamentals',
  };

  static Map<String, Object?> fill(
    Map<String, Object?> component,
    TurnEvidence evidence,
  ) => switch (component['component']) {
    'QaPriceChart' ||
    'QaTickerSnapshot' ||
    'QaTickerMove' => TickerPriceData.fillPayload(component, evidence),
    'QaPeriodChange' => _periodChange(component, _brief(evidence)),
    'QaPositionsSnapshot' => _positionsSnapshot(component, _brief(evidence)),
    'QaPnLBreakdown' => _pnlBreakdown(component, _brief(evidence)),
    'QaEarningsCalendar' => _earnings(component, evidence),
    'QaFundamentals' => _fundamentals(component, evidence),
    _ => component,
  };

  // --- Cartera (PORTFOLIO_BRIEF) -------------------------------------------

  /// `period` = clave de `period_returns`.
  static Map<String, Object?> _periodChange(
    Map<String, Object?> c,
    Map<String, Object?>? brief,
  ) {
    final period = c['period'];
    final p = _map(_map(brief?['period_returns'])?[period]);
    if (period is! String || p == null) return c;
    if (p['has_sufficient_history'] == false) return c;
    return {
      ...c,
      if (p['label_es'] is String) 'periodLabel': p['label_es'],
      if (_num(p['pnl_abs']) case final v?) 'changeAbs': v,
      if (_num(p['pnl_pct']) case final v?) 'changePct': v,
      if (_num(p['value_start']) case final v?) 'valueStart': v,
      if (_num(p['value_end']) case final v?) 'valueEnd': v,
    };
  }

  /// Los totales de la cartera abierta y el reparto por peso.
  static Map<String, Object?> _positionsSnapshot(
    Map<String, Object?> c,
    Map<String, Object?>? brief,
  ) {
    if (brief == null || brief['has_positions'] != true) return c;
    final positions = [
      for (final p in (brief['positions'] as List? ?? const []))
        if (p is Map && p['ticker'] is String)
          {'ticker': p['ticker'], 'weightPct': _num(p['weight_pct']) ?? 0},
    ]..sort(
      (a, b) => (b['weightPct'] as double).compareTo(a['weightPct'] as double),
    );
    return {
      ...c,
      if (_num(brief['total_value']) case final v?) 'totalValue': v,
      if (_num(brief['total_pnl_abs']) case final v?) 'pnlAbs': v,
      if (_num(brief['total_pnl_pct']) case final v?) 'pnlPct': v,
      'positionsCount': positions.length,
      'positions': positions,
    };
  }

  /// `scope`: `open` (desde la compra, posiciones abiertas) o `closed`
  /// (resultado realizado de lo vendido).
  static Map<String, Object?> _pnlBreakdown(
    Map<String, Object?> c,
    Map<String, Object?>? brief,
  ) {
    if (brief == null) return c;
    switch (c['scope']) {
      case 'open':
        if (brief['has_positions'] != true) return c;
        return {
          ...c,
          if (_num(brief['total_cost_basis']) case final v?) 'costBasis': v,
          if (_num(brief['total_value']) case final v?) 'currentValue': v,
          if (_num(brief['total_pnl_abs']) case final v?) 'gainLoss': v,
          if (_num(brief['total_pnl_pct']) case final v?) 'gainLossPercent': v,
        };
      case 'closed':
        final cost = _num(brief['closed_pnl_total_cost_basis']);
        final abs = _num(brief['closed_pnl_total_abs']);
        if (cost == null || abs == null) return c;
        return {
          ...c,
          'costBasis': cost,
          'currentValue': _round2(cost + abs),
          'gainLoss': abs,
          if (_num(brief['closed_pnl_total_pct']) case final v?)
            'gainLossPercent': v,
        };
      default:
        return c;
    }
  }

  // --- Earnings (get_earnings) ----------------------------------------------

  /// `show`: `next` (cuándo reporta y qué se espera), `latest` (cómo le
  /// fue en el último) o `both`.
  static Map<String, Object?> _earnings(
    Map<String, Object?> c,
    TurnEvidence evidence,
  ) {
    final show = c['show'];
    if (show is! String) return c;
    final entry = _latestEntry(evidence, 'get_earnings', 'earnings', c);
    if (entry == null) return c;
    final out = {...c};

    final next = _map(entry['next_report']);
    if (next != null && (show == 'next' || show == 'both')) {
      out
        ..['nextReportDateLabel'] = next['date_label']
        ..['nextReportDate'] = next['date']
        ..['nextReportEstimated'] = next['estimated'] == true;
      if (next['timing_label'] case final String t) out['timingLabel'] = t;
      if (next['fiscal_period_label'] case final String f when f.isNotEmpty) {
        out['fiscalPeriodLabel'] = f;
      }
      if (_num(next['eps_estimate']) case final v?) out['nextEpsEstimate'] = v;
    }

    final latest = _map(entry['latest_result']);
    if (latest != null && (show == 'latest' || show == 'both')) {
      final label =
          latest['report_date_label'] ?? latest['fiscal_period_label'];
      if (label is String) out['latestReportDateLabel'] = label;
      if (_num(latest['eps_actual']) case final v?) out['epsActual'] = v;
      if (_num(latest['eps_estimate']) case final v?) out['epsEstimate'] = v;
      if (_num(latest['eps_yoy_pct']) case final v?) out['epsYoyPct'] = v;
      if (latest['beat'] case final bool b) out['beat'] = b;
      out['history'] = [
        for (final q in (entry['history'] as List? ?? const []))
          if (q is Map && _num(q['eps_actual']) != null)
            {
              'periodLabel': q['fiscal_period_label'] ?? '',
              'epsActual': _num(q['eps_actual']),
              if (_num(q['eps_estimate']) case final v?) 'epsEstimate': v,
              if (_num(q['eps_yoy_pct']) case final v?) 'epsYoyPct': v,
            },
      ];
    }
    return out;
  }

  // --- Fundamentals (get_fundamentals) --------------------------------------

  /// `metrics`: claves de [AnalysisMetric] (+ `beta`), en el orden en que
  /// se muestran. Rótulo y formato los pone la app.
  static Map<String, Object?> _fundamentals(
    Map<String, Object?> c,
    TurnEvidence evidence,
  ) {
    final keys = c['metrics'];
    if (keys is! List) return c;
    final data = _latestEntry(evidence, 'get_fundamentals', 'fundamentals', c);
    if (data == null) return c;
    final items = <Map<String, Object?>>[];
    for (final key in keys.whereType<String>()) {
      final v = _num(data[key]);
      if (v == null) continue; // Ausente: nunca se estima.
      if (key == 'beta') {
        items.add({
          'label': 'Beta',
          'value': QaFormat.decimal(v, digits: 2),
          'group': 'other',
        });
        continue;
      }
      final metric = AnalysisMetric.byKey(key);
      if (metric == null) continue;
      items.add({
        'label': metric.label,
        'value': metric.format(v),
        'group': _groupOf(metric),
      });
    }
    final out = {...c, 'items': items.take(8).toList()};
    // Industria y rango de 52 semanas, solo en la pregunta general.
    if (c['overview'] != true) return out;
    if (data['industry'] case final String i when i.isNotEmpty) {
      out['industry'] = i;
    }
    if (_num(data['week_52_low']) case final v?) out['week52Low'] = v;
    if (_num(data['week_52_high']) case final v?) out['week52High'] = v;
    final quote = TickerPriceData.from(evidence, '${c['ticker'] ?? ''}');
    if (quote?.currentPrice case final v?) out['currentPrice'] = v;
    return out;
  }

  static String _groupOf(AnalysisMetric m) => switch (m) {
    AnalysisMetric.dividendYield || AnalysisMetric.payout => 'dividend',
    _ when m.unit == AnalysisMetricUnit.percent => 'profitability',
    _ => 'valuation',
  };

  // --- Helpers --------------------------------------------------------------

  /// La entrada de `result[resultKey][TICKER]` de la llamada más reciente a
  /// [tool] con dato para el ticker de la card.
  static Map<String, Object?>? _latestEntry(
    TurnEvidence evidence,
    String tool,
    String resultKey,
    Map<String, Object?> c,
  ) {
    final ticker = '${c['ticker'] ?? ''}'.trim().toUpperCase();
    if (ticker.isEmpty) return null;
    for (final call in evidence.calls.reversed) {
      if (call.name != tool || call.status == 'locked') continue;
      final byTicker = _map(call.result[resultKey]);
      if (byTicker == null) continue;
      for (final e in byTicker.entries) {
        if (e.key.toUpperCase() != ticker) continue;
        final entry = _map(e.value);
        if (entry != null && entry.isNotEmpty) return entry;
      }
    }
    return null;
  }

  /// El PORTFOLIO_BRIEF del turno: la última línea del contexto fijo (ver
  /// `AssistantOpenAiService.pinnedContextFor`).
  static Map<String, Object?>? _brief(TurnEvidence evidence) {
    final pinned = evidence.pinnedContext;
    if (pinned == null) return null;
    try {
      final decoded = jsonDecode(
        pinned.substring(pinned.lastIndexOf('\n') + 1),
      );
      return _map(decoded);
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _map(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : null;

  static double? _num(Object? v) =>
      v is num && v.isFinite ? v.toDouble() : null;

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
