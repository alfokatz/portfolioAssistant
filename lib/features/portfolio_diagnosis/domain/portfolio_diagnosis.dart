import 'dart:math' as math;

import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_display_name.dart';

/// Lo que Porty encuentra al mirar la cartera por primera vez (el "aha" de
/// docs/superpowers/plans/2026-10-26-aha-moment.md). Todo sale de datos
/// reales y se calcula en la app, sin el modelo.
enum DiagnosisKind {
  /// Una empresa que tiene directo y también adentro de sus ETFs (o en
  /// varios ETFs a la vez): pesa más de lo que parece.
  overlap,

  /// Un sector que pesa mucho contando lo que hay adentro de los fondos.
  sector,

  /// La posición más grande pesa mucho.
  topHolding,

  /// Las 3 más grandes son casi toda la cartera.
  topThree,

  /// Lo que le cobran por año sus fondos.
  fees,

  /// Cómo le fue contra haber puesto lo mismo, el mismo día, en el S&P 500.
  vsMarket,

  /// La mejor y la peor posición.
  bestWorst,

  /// Nada llamativo: está repartida.
  spread,
}

enum DiagnosisTone { attention, good, neutral }

class DiagnosisFinding {
  const DiagnosisFinding({
    required this.kind,
    required this.tone,
    required this.score,
    this.ticker,
    this.sector,
    this.via = const [],
    this.numbers = const {},
  });

  final DiagnosisKind kind;
  final DiagnosisTone tone;

  /// Qué tan llamativo es (para elegir los que se muestran). Lo que no se
  /// ve a simple vista (solapamiento, sector adentro de los fondos) pesa
  /// más que lo obvio (la posición más grande).
  final double score;

  /// La empresa o posición de la que habla.
  final String? ticker;
  final String? sector;

  /// Los fondos por los que llega (solapamiento y sector).
  final List<String> via;

  /// Los números, en las unidades de la app: porcentajes de 0 a 100 y
  /// montos en USD.
  final Map<String, double> numbers;
}

/// Lo que se sabe de un fondo (Yahoo `topHoldings`, `fundProfile`), ya
/// parseado por `EtfHoldingsFetcher`.
class FundLook {
  const FundLook({
    this.holdings = const {},
    this.sectors = const {},
    this.expenseRatioPct,
    this.stockPct,
  });

  /// Sus posiciones principales: símbolo → % del fondo.
  final Map<String, double> holdings;

  /// Su reparto por sector (de la parte en acciones): sector → %.
  final Map<String, double> sectors;

  /// Costo anual, en % de lo invertido (0,03 = 0,03 %).
  final double? expenseRatioPct;

  /// Qué parte del fondo está en acciones (para escalar los sectores).
  final double? stockPct;

  /// Desde la salida de `EtfHoldingsFetcher.parse` (lo que ve el modelo).
  factory FundLook.fromJson(Map<String, Object?> json) {
    double? n(Object? v) => v is num ? v.toDouble() : null;
    return FundLook(
      holdings: {
        for (final h in (json['top_holdings'] as List? ?? const []))
          if (h is Map && h['symbol'] is String && n(h['weight_pct']) != null)
            DiagnosisMath.normalizeSymbol(h['symbol'] as String):
                n(h['weight_pct'])!,
      },
      sectors: {
        for (final s in (json['sectors'] as List? ?? const []))
          if (s is Map && s['sector'] is String && n(s['weight_pct']) != null)
            s['sector'] as String: n(s['weight_pct'])!,
      },
      expenseRatioPct: n(json['expense_ratio_pct']),
      stockPct: n(json['stock_position_pct']),
    );
  }
}

/// Lo que hace falta para el diagnóstico. Lo que no se pudo traer (Yahoo
/// caído) queda vacío y esos hallazgos simplemente no salen.
class DiagnosisInputs {
  const DiagnosisInputs({
    required this.valuations,
    this.lots = const [],
    this.sectorByTicker = const {},
    this.funds = const {},
    this.sp500 = const [],
    required this.now,
  });

  /// Una por ticker (como la Home).
  final List<PositionValuation> valuations;

  /// Cada compra, con su fecha y su costo (para comparar con el S&P 500).
  final List<PositionValuation> lots;

  /// Sector de cada acción (no de los fondos).
  final Map<String, String> sectorByTicker;

  /// Los tickers que son fondos, con lo que se sabe de ellos.
  final Map<String, FundLook> funds;

  /// Cierres diarios del S&P 500.
  final List<PriceCandle> sp500;
  final DateTime now;
}

class PortfolioDiagnosis {
  const PortfolioDiagnosis({
    required this.findings,
    required this.positions,
    required this.funds,
  });

  /// Los que se muestran, del más llamativo al menos (hasta [maxShown]).
  final List<DiagnosisFinding> findings;

  /// Cuántas posiciones tiene (con pocas, se le sugiere sumar el resto).
  final int positions;

  /// Cuántas de esas son fondos.
  final int funds;

  static const maxShown = 3;

  bool get anyAttention =>
      findings.any((f) => f.tone == DiagnosisTone.attention);
}

abstract final class DiagnosisMath {
  /// Yahoo escribe `BRK-B`; la app, `BRK.B`.
  static String normalizeSymbol(String symbol) =>
      symbol.trim().toUpperCase().replaceAll('-', '.');

  /// Cierre del S&P 500 del día [date] o del último día hábil antes.
  /// `null` si la serie no llega tan atrás.
  static double? closeOn(List<PriceCandle> candles, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    PriceCandle? best;
    for (final c in candles) {
      final d = DateTime(c.date.year, c.date.month, c.date.day);
      if (d.isAfter(day)) continue;
      if (best == null || c.date.isAfter(best.date)) best = c;
    }
    if (best == null) return null;
    // Más de una semana sin cierre antes de esa fecha: la serie no cubre.
    if (day.difference(best.date).inDays > 7) return null;
    return best.close > 0 ? best.close : null;
  }
}

abstract final class PortfolioDiagnosisBuilder {
  // Umbrales: lo que sale tiene que ser llamativo de verdad, no relleno.
  static const _topHoldingPct = 25.0;
  static const _topThreePct = 60.0;
  static const _overlapMinPct = 4.0;
  static const _sectorPct = 35.0;
  static const _feesMinUsd = 10.0;
  static const _feesMinPct = 0.25;
  static const _vsMarketMinDiffPct = 2.0;
  static const _vsMarketMinDays = 30;
  static const _bestPct = 25.0;
  static const _worstPct = -20.0;

  static PortfolioDiagnosis build(DiagnosisInputs inputs) {
    final values = {
      for (final v in inputs.valuations)
        if (v.marketValue > 0)
          DiagnosisMath.normalizeSymbol(v.position.ticker): v.marketValue,
    };
    final total = values.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) {
      return const PortfolioDiagnosis(findings: [], positions: 0, funds: 0);
    }
    final weights = {
      for (final MapEntry(:key, :value) in values.entries)
        key: value / total * 100,
    };
    final funds = {
      for (final MapEntry(:key, :value) in inputs.funds.entries)
        if (weights.containsKey(DiagnosisMath.normalizeSymbol(key)))
          DiagnosisMath.normalizeSymbol(key): value,
    };

    final all =
        <DiagnosisFinding?>[
            _overlap(weights, funds),
            _sector(weights, funds, inputs.sectorByTicker),
            ..._concentration(weights, funds),
            _fees(values, funds),
            _vsMarket(inputs),
            _bestWorst(inputs.valuations),
          ].whereType<DiagnosisFinding>().toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    final shown = <DiagnosisFinding>[];
    for (final f in all) {
      if (shown.length == PortfolioDiagnosis.maxShown) break;
      // Una sola de concentración: las dos dicen lo mismo.
      final isConcentration =
          f.kind == DiagnosisKind.topHolding ||
          f.kind == DiagnosisKind.topThree;
      if (isConcentration &&
          shown.any(
            (s) =>
                s.kind == DiagnosisKind.topHolding ||
                s.kind == DiagnosisKind.topThree,
          )) {
        continue;
      }
      shown.add(f);
    }
    if (!shown.any((f) => f.tone == DiagnosisTone.attention) &&
        shown.length < PortfolioDiagnosis.maxShown) {
      final spread = _spread(weights);
      if (spread != null) shown.add(spread);
    }
    return PortfolioDiagnosis(
      findings: shown,
      positions: weights.length,
      funds: funds.length,
    );
  }

  /// Cuánto pesa de verdad cada empresa: lo directo más lo que hay adentro
  /// de cada fondo. Sale la que llega por dos lados o más y pesa más.
  static DiagnosisFinding? _overlap(
    Map<String, double> weights,
    Map<String, FundLook> funds,
  ) {
    final exposure = <String, double>{};
    final via = <String, List<String>>{};
    for (final MapEntry(key: ticker, value: w) in weights.entries) {
      if (funds.containsKey(ticker)) continue;
      exposure[ticker] = (exposure[ticker] ?? 0) + w;
    }
    for (final MapEntry(key: fund, value: look) in funds.entries) {
      final w = weights[fund] ?? 0;
      for (final MapEntry(key: symbol, value: pct) in look.holdings.entries) {
        exposure[symbol] = (exposure[symbol] ?? 0) + w * pct / 100;
        (via[symbol] ??= []).add(fund);
      }
    }
    String? best;
    for (final symbol in exposure.keys) {
      final direct = weights.containsKey(symbol) && !funds.containsKey(symbol);
      final sources = (direct ? 1 : 0) + (via[symbol]?.length ?? 0);
      if (sources < 2 || exposure[symbol]! < _overlapMinPct) continue;
      if (best == null || exposure[symbol]! > exposure[best]!) best = symbol;
    }
    if (best == null) return null;
    final total = exposure[best]!;
    final direct =
        weights.containsKey(best) && !funds.containsKey(best)
            ? weights[best]!
            : 0.0;
    return DiagnosisFinding(
      kind: DiagnosisKind.overlap,
      tone: DiagnosisTone.attention,
      score: 55 + math.min(total, 30),
      ticker: best,
      via: via[best]!..sort(),
      numbers: {'total': total, 'direct': direct},
    );
  }

  /// El sector que más pesa, contando lo de adentro de los fondos. Pesa más
  /// si a simple vista (solo las acciones directas) parecía mucho menos.
  static DiagnosisFinding? _sector(
    Map<String, double> weights,
    Map<String, FundLook> funds,
    Map<String, String> sectorByTicker,
  ) {
    final bySector = <String, double>{};
    final direct = <String, double>{};
    final via = <String, List<String>>{};
    for (final MapEntry(key: ticker, value: w) in weights.entries) {
      final fund = funds[ticker];
      if (fund == null) {
        final sector =
            sectorByTicker[ticker] ??
            sectorByTicker[ticker.replaceAll('.', '-')] ??
            SectorDisplayName.unclassified;
        bySector[sector] = (bySector[sector] ?? 0) + w;
        direct[sector] = (direct[sector] ?? 0) + w;
        continue;
      }
      final equity = (fund.stockPct ?? 100).clamp(0, 100) / 100;
      for (final MapEntry(key: sector, value: pct) in fund.sectors.entries) {
        bySector[sector] = (bySector[sector] ?? 0) + w * equity * pct / 100;
        (via[sector] ??= []).add(ticker);
      }
    }
    bySector.remove(SectorDisplayName.unclassified);
    if (bySector.isEmpty) return null;
    final top = bySector.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value < _sectorPct) return null;
    // Si casi todo el sector es una sola acción, ya lo dice la
    // concentración ("TSLA es el 81 %"): repetirlo como sector no suma.
    final biggestStock = [
      for (final MapEntry(key: t, value: w) in weights.entries)
        if (!funds.containsKey(t) &&
            (sectorByTicker[t] ?? sectorByTicker[t.replaceAll('.', '-')]) ==
                top.key)
          w,
    ].fold(0.0, math.max);
    if (biggestStock >= top.value * 0.7) return null;
    final seen = direct[top.key] ?? 0;
    final hidden = top.value - seen;
    return DiagnosisFinding(
      kind: DiagnosisKind.sector,
      tone: DiagnosisTone.attention,
      score: 40 + (top.value - _sectorPct) + (hidden >= 10 ? 15 : 0),
      sector: top.key,
      via: [...?via[top.key]]..sort(),
      numbers: {'total': top.value, 'direct': seen},
    );
  }

  static List<DiagnosisFinding> _concentration(
    Map<String, double> weights,
    Map<String, FundLook> funds,
  ) {
    final sorted =
        weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final out = <DiagnosisFinding>[];
    // Todo en un solo fondo amplio no es concentración.
    final topIsFund = funds.containsKey(top.key);
    if (sorted.length == 1) {
      if (!topIsFund) {
        out.add(
          DiagnosisFinding(
            kind: DiagnosisKind.topHolding,
            tone: DiagnosisTone.attention,
            score: 50,
            ticker: top.key,
            numbers: const {'pct': 100},
          ),
        );
      }
      return out;
    }
    if (top.value >= _topHoldingPct && !topIsFund) {
      out.add(
        DiagnosisFinding(
          kind: DiagnosisKind.topHolding,
          tone: DiagnosisTone.attention,
          score: 20 + top.value / 2,
          ticker: top.key,
          numbers: {'pct': top.value},
        ),
      );
    }
    // Tres fondos amplios arriba no es concentración: alcanza con que la
    // mayoría de las 3 sean acciones.
    final topThreeFunds =
        sorted.take(3).where((e) => funds.containsKey(e.key)).length;
    if (sorted.length >= 4 && topThreeFunds < 2) {
      final three = sorted.take(3).fold(0.0, (a, e) => a + e.value);
      if (three >= _topThreePct) {
        out.add(
          DiagnosisFinding(
            kind: DiagnosisKind.topThree,
            tone: DiagnosisTone.attention,
            score: 15 + three / 3,
            numbers: {'pct': three, 'count': sorted.length.toDouble()},
            via: [for (final e in sorted.take(3)) e.key],
          ),
        );
      }
    }
    return out;
  }

  /// Lo que cobran por año los fondos (costo anual × lo invertido).
  static DiagnosisFinding? _fees(
    Map<String, double> values,
    Map<String, FundLook> funds,
  ) {
    var annual = 0.0;
    var invested = 0.0;
    String? priciest;
    double? priciestPct;
    for (final MapEntry(key: ticker, value: look) in funds.entries) {
      final ratio = look.expenseRatioPct;
      final value = values[ticker];
      if (ratio == null || value == null) continue;
      annual += value * ratio / 100;
      invested += value;
      if (priciestPct == null || ratio > priciestPct) {
        priciest = ticker;
        priciestPct = ratio;
      }
    }
    if (invested <= 0 || priciest == null) return null;
    final avgPct = annual / invested * 100;
    if (annual >= _feesMinUsd && avgPct >= _feesMinPct) {
      return DiagnosisFinding(
        kind: DiagnosisKind.fees,
        tone: DiagnosisTone.attention,
        score: 35 + math.min(annual / 10, 20),
        ticker: priciest,
        numbers: {
          'annual': annual,
          'avg_pct': avgPct,
          'ticker_pct': priciestPct!,
        },
      );
    }
    // Fondos baratos: algo bueno para contar, si no hay nada más.
    if (avgPct <= 0.1) {
      return DiagnosisFinding(
        kind: DiagnosisKind.fees,
        tone: DiagnosisTone.good,
        score: 12,
        numbers: {'annual': annual, 'avg_pct': avgPct},
      );
    }
    return null;
  }

  /// Contra el S&P 500, compra por compra: cuánto valdría hoy lo que puso si
  /// cada compra hubiera ido al índice ese mismo día. No sirve la serie de
  /// la Home (el valor total crece con cada aporte).
  static DiagnosisFinding? _vsMarket(DiagnosisInputs inputs) {
    if (inputs.sp500.isEmpty || inputs.lots.isEmpty) return null;
    final spNow = DiagnosisMath.closeOn(inputs.sp500, inputs.now);
    if (spNow == null) return null;
    var cost = 0.0;
    var covered = 0.0;
    var actual = 0.0;
    var counterfactual = 0.0;
    DateTime? first;
    for (final lot in inputs.lots) {
      final p = lot.position;
      final lotCost = p.purchasePrice * p.quantity;
      if (lotCost <= 0) continue;
      cost += lotCost;
      final spThen = DiagnosisMath.closeOn(inputs.sp500, p.purchaseDate);
      if (spThen == null) continue;
      covered += lotCost;
      actual += lot.marketValue;
      counterfactual += lotCost / spThen * spNow;
      if (first == null || p.purchaseDate.isBefore(first)) {
        first = p.purchaseDate;
      }
    }
    if (first == null || counterfactual <= 0) return null;
    // Recién compró: todavía no dice nada.
    if (inputs.now.difference(first).inDays < _vsMarketMinDays) return null;
    // Sin la mayoría de lo invertido, la comparación engaña.
    if (covered < cost * 0.7) return null;
    final diffPct = (actual - counterfactual) / counterfactual * 100;
    if (diffPct.abs() < _vsMarketMinDiffPct) return null;
    return DiagnosisFinding(
      kind: DiagnosisKind.vsMarket,
      tone: diffPct > 0 ? DiagnosisTone.good : DiagnosisTone.attention,
      score: 45 + math.min(diffPct.abs(), 25),
      numbers: {
        'actual': actual,
        'market': counterfactual,
        'diff': actual - counterfactual,
        'diff_pct': diffPct,
        'since_year': first.year.toDouble(),
      },
    );
  }

  static DiagnosisFinding? _bestWorst(List<PositionValuation> valuations) {
    if (valuations.length < 2) return null;
    final sorted = [...valuations]
      ..sort((a, b) => b.pnlPercent.compareTo(a.pnlPercent));
    final best = sorted.first;
    final worst = sorted.last;
    final showBest = best.pnlPercent >= _bestPct;
    final showWorst = worst.pnlPercent <= _worstPct;
    if (!showBest && !showWorst) return null;
    return DiagnosisFinding(
      kind: DiagnosisKind.bestWorst,
      tone: showWorst ? DiagnosisTone.attention : DiagnosisTone.good,
      score:
          20 +
          math
              .max(
                showBest ? best.pnlPercent / 4 : 0.0,
                showWorst ? -worst.pnlPercent / 3 : 0.0,
              )
              .clamp(0.0, 25.0),
      ticker: showWorst ? worst.position.ticker : best.position.ticker,
      numbers: {
        if (showBest) 'best_pct': best.pnlPercent,
        if (showWorst) 'worst_pct': worst.pnlPercent,
      },
      via: [
        if (showBest) best.position.ticker.toUpperCase(),
        if (showWorst) worst.position.ticker.toUpperCase(),
      ],
    );
  }

  static DiagnosisFinding? _spread(Map<String, double> weights) {
    if (weights.length < 3) return null;
    final top = weights.values.reduce(math.max);
    return DiagnosisFinding(
      kind: DiagnosisKind.spread,
      tone: DiagnosisTone.good,
      score: 5,
      numbers: {'top_pct': top, 'count': weights.length.toDouble()},
    );
  }
}
