import 'package:portfolio_assistant/features/assistant/utils/period_labels.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// El movimiento de un ticker en un período (`periods.{period}` de
/// `get_quote` o `position_periods.{T}.{period}` de `get_portfolio_details`).
class TickerPeriodMove {
  const TickerPeriodMove({
    required this.label,
    required this.changePct,
    required this.priceStart,
    required this.priceEnd,
    required this.sufficientHistory,
    this.changeAbs,
  });

  final String label;
  final double changePct;
  final double priceStart;
  final double priceEnd;
  final double? changeAbs;
  final bool sufficientHistory;
}

/// Los números de las cards de precio de UN ticker (`QaPriceChart`,
/// `QaTickerSnapshot`, `QaTickerMove`), sacados de los resultados de las
/// tools del turno y no de lo que escribió el modelo: el modelo solo elige
/// el ticker y el período, y la app pone los números. Escribe menos (la
/// respuesta llega antes) y no hay cifras mal copiadas (ver
/// docs/superpowers/research/2026-10-15-porty-latencia.md, A1).
///
/// Si una tool se llamó varias veces en la conversación, gana la más
/// reciente con dato para el ticker.
class TickerPriceData {
  const TickerPriceData._({
    required this.ticker,
    required this.currentPrice,
    required this.weightPct,
    required this.periods,
  });

  final String ticker;
  final double? currentPrice;

  /// Peso en la cartera (solo tickers propios, de `get_quote`).
  final double? weightPct;

  /// Por clave de [PeriodLabels.durations] (`day`, `week`, `month`…).
  final Map<String, TickerPeriodMove> periods;

  static TickerPriceData? from(TurnEvidence evidence, String ticker) {
    final t = ticker.trim().toUpperCase();
    if (t.isEmpty) return null;
    double? price;
    double? weight;
    Map<String, TickerPeriodMove>? periods;

    for (final call in evidence.calls.reversed) {
      final Map<String, Object?>? source;
      switch (call.name) {
        case 'get_quote':
          final entry = _entryFor(call.result['tickers'], t);
          if (entry == null || entry['fetch_ok'] != true) continue;
          price ??= _num(entry['current_price']);
          weight ??= _num(entry['weight_pct']);
          source = _map(entry['periods']);
        case 'get_portfolio_details':
          source = _entryFor(call.result['position_periods'], t);
        default:
          continue;
      }
      if (periods == null && source != null) {
        final parsed = _periods(source);
        if (parsed.isNotEmpty) periods = parsed;
      }
      if (price != null && weight != null && periods != null) break;
    }
    if (price == null && periods == null) return null;
    return TickerPriceData._(
      ticker: t,
      currentPrice: price,
      weightPct: weight,
      periods: periods ?? const {},
    );
  }

  /// Los números que el texto puede citar sin inventar nada.
  List<double> get backingNumbers => [
    if (currentPrice != null) currentPrice!,
    if (weightPct != null) weightPct!,
    for (final p in periods.values) ...[
      p.changePct,
      p.changePct.abs(),
      p.priceStart,
      p.priceEnd,
      if (p.changeAbs != null) p.changeAbs!,
      if (p.changeAbs != null) p.changeAbs!.abs(),
      _round2((p.priceEnd - p.priceStart).abs()),
    ],
  ];

  /// El payload de la card con sus números puestos desde la evidencia.
  ///
  /// El modelo manda `ticker` (+ `initialRange`) y, si el usuario nombró
  /// una ventana, `period` (clave de [PeriodLabels.durations]). Acá se
  /// completan los campos que las cards leen (`currentPrice`,
  /// `dayChangePct`…, y con `period`: `periodLabel`, `changePct`,
  /// `priceStart`, `priceEnd`). Lo que la evidencia no tiene queda como lo
  /// mandó el modelo (respuestas de versiones anteriores, que todavía
  /// copiaban los números).
  static Map<String, Object?> fillPayload(
    Map<String, Object?> payload,
    TurnEvidence evidence,
  ) {
    final ticker = payload['ticker'];
    if (ticker is! String) return payload;
    final data = from(evidence, ticker);
    if (data == null) return payload;

    final out = {...payload};
    if (data.currentPrice != null) out['currentPrice'] = data.currentPrice;
    if (data.weightPct != null) out['weightPct'] = data.weightPct;
    for (final (key, field) in _snapshotFields) {
      final move = data.periods[key];
      if (move == null) continue;
      if (move.sufficientHistory) {
        out[field] = move.changePct;
      } else {
        // Sin historia suficiente el % no dice nada: mejor no mostrarlo.
        out.remove(field);
      }
    }

    final period = payload['period'];
    final move = period is String ? data.periods[period] : null;
    if (move != null) {
      out['periodLabel'] = move.label;
      out['changePct'] = move.changePct;
      out['priceStart'] = move.priceStart;
      out['priceEnd'] = move.priceEnd;
    }
    return out;
  }

  static const _snapshotFields = [
    ('day', 'dayChangePct'),
    ('week', 'weekChangePct'),
    ('month', 'monthChangePct'),
  ];

  static Map<String, TickerPeriodMove> _periods(Map<String, Object?> raw) => {
    for (final key in PeriodLabels.durations.keys)
      if (_map(raw[key]) case final p?)
        if (_num(p['change_pct']) case final pct?)
          key: TickerPeriodMove(
            label: p['label_es'] is String ? p['label_es'] as String : '',
            changePct: pct,
            priceStart: _num(p['price_start']) ?? 0,
            priceEnd: _num(p['price_end']) ?? 0,
            changeAbs: _num(p['change_abs']),
            sufficientHistory: p['has_sufficient_history'] != false,
          ),
  };

  /// La entrada de [ticker] en un mapa por ticker (sin importar
  /// mayúsculas).
  static Map<String, Object?>? _entryFor(Object? byTicker, String ticker) {
    final map = _map(byTicker);
    if (map == null) return null;
    for (final e in map.entries) {
      if (e.key.toUpperCase() == ticker) return _map(e.value);
    }
    return null;
  }

  static Map<String, Object?>? _map(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : null;

  static double? _num(Object? v) =>
      v is num && v.isFinite ? v.toDouble() : null;

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));
}
