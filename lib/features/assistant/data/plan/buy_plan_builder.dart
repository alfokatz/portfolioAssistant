import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

/// Un instrumento que eligió el modelo para una clase de activo del plan.
class BuyPlanPick {
  const BuyPlanPick(this.ticker, this.assetClass);

  final String ticker;
  final PlanAssetClass assetClass;
}

/// La compra mensual de un plan: qué comprar cada mes y cuánto a cada uno.
///
/// El modelo elige los instrumentos (cualquier ticker, nunca de una lista
/// fija); acá se reparten según la cartera del plan con reglas fijas:
/// - cada clase de activo recibe su porcentaje del plan; una clase sin
///   instrumento reparte el suyo entre las demás;
/// - dentro de una clase, cada acción individual pesa como mucho
///   [maxStockShare] del total y los ETFs se llevan el resto (la base);
/// - el rendimiento por dividendos ponderado (dato real de Yahoo) reemplaza
///   al supuesto si cubre al menos [minYieldCoverage] de la compra.
abstract final class BuyPlanBuilder {
  static const buyPlanIdKey = 'buy_plan_id';
  static const maxStockShare = 0.15;
  static const minYieldCoverage = 0.7;

  /// En un plan de vivir de dividendos, una parte de acciones que rinde
  /// menos que esto no es "de dividendos" (un ETF de mercado total ronda
  /// el 1,3%).
  static const minDividendYieldPct = 2.0;

  /// [base] es el resultado de `get_goal_projection` del plan; [info], el de
  /// [DividendFetcher.fetch] (`tickers`) para los tickers de [picks].
  static Map<String, Object?> build({
    required Map<String, Object?> base,
    required List<BuyPlanPick> picks,
    required Map<String, Object?> info,
  }) {
    final plan = base['plan'];
    final inputs = SavingsPlanInputs.fromJson(
      plan is Map ? plan['inputs'] : null,
    );
    if (inputs == null) return {'status': 'needs_plan'};

    // Tickers que Yahoo no conoce: fuera (probablemente mal escritos).
    final unknown = <String>[];
    final valid = <BuyPlanPick>[];
    final seen = <String>{};
    for (final p in picks) {
      if (!seen.add(p.ticker)) continue;
      final i = info[p.ticker];
      if (i is Map && i['status'] == 'empty') {
        unknown.add(p.ticker);
      } else {
        valid.add(p);
      }
    }
    if (valid.isEmpty) {
      return {'status': 'needs_retry', 'unknown_tickers': unknown};
    }

    String kindOf(String t) {
      final i = info[t];
      return i is Map && i['kind'] is String
          ? i['kind'] as String
          : DividendFetcher.kindOther;
    }

    final problems = _dividendPlanProblems(inputs, valid, info, kindOf);
    if (problems.isNotEmpty) {
      return {
        'status': 'needs_retry',
        'reason':
            'This plan lives off dividends. Pick again: ${problems.join('; ')}.',
        if (unknown.isNotEmpty) 'unknown_tickers': unknown,
      };
    }

    // Peso de cada clase según el plan, con las clases sin instrumento
    // repartidas en proporción entre las que tienen.
    final allocation = PlanAssumptions.allocationFor(
      inputs.risk,
      shortTerm: inputs.shortTerm,
    );
    final present = {for (final p in valid) p.assetClass};
    final presentTotal = allocation.entries
        .where((e) => present.contains(e.key))
        .fold<double>(0, (a, e) => a + e.value);
    final classShare = <PlanAssetClass, double>{
      for (final c in present)
        c:
            presentTotal > 0
                ? (allocation[c] ?? 0) / presentTotal
                : 1 / present.length,
    };
    final merged = [
      for (final c in allocation.keys)
        if (!present.contains(c) && (allocation[c] ?? 0) > 0) c.key,
    ];

    final share = <String, double>{};
    for (final c in present) {
      final members = [
        for (final p in valid)
          if (p.assetClass == c) p.ticker,
      ];
      final stocks = members.where(
        (t) => kindOf(t) == DividendFetcher.kindStock,
      );
      final funds = members.where(
        (t) => kindOf(t) != DividendFetcher.kindStock,
      );
      final total = classShare[c]!;
      if (funds.isEmpty) {
        for (final t in members) {
          share[t] = total / members.length;
        }
        continue;
      }
      final each = total / members.length;
      var used = 0.0;
      for (final t in stocks) {
        final s = each < maxStockShare ? each : maxStockShare;
        share[t] = s;
        used += s;
      }
      for (final t in funds) {
        share[t] = (total - used) / funds.length;
      }
    }

    final pcts = _wholePercents(share);

    // Rendimiento ponderado con los datos reales.
    var covered = 0.0;
    var weighted = 0.0;
    for (final e in share.entries) {
      final i = info[e.key];
      final y = i is Map ? i['dividend_yield_pct'] : null;
      if (y is num) {
        covered += e.value;
        weighted += e.value * y;
      }
    }
    final realYield =
        covered >= minYieldCoverage && weighted > 0
            ? weighted / covered / 100
            : null;

    // El plan con el rendimiento real: con un ingreso pedido y dividendos,
    // cambia el capital que hace falta (y con él, el ahorro mensual).
    var updated = inputs;
    if (realYield != null) {
      final desired = inputs.desiredMonthlyIncome;
      updated = inputs.copyWith(
        dividendYield: realYield,
        targetAmount:
            desired != null && inputs.incomeStrategy == IncomeStrategy.dividends
                ? SavingsPlanCalculator.capitalForDividends(desired, realYield)
                : null,
      );
    }
    final before = SavingsPlan.build(inputs);
    final after = SavingsPlan.build(updated);
    final monthly = after.monthlyUsed;
    final amounts = _amounts(monthly, pcts);

    int r(double v) => v.round();
    final items = [
      for (final p in valid)
        {
          'ticker': p.ticker,
          'asset_class': p.assetClass.key,
          'asset_class_label': p.assetClass.label,
          'kind': kindOf(p.ticker),
          'pct': pcts[p.ticker],
          'monthly_amount': amounts[p.ticker],
          ...?_infoFields(info[p.ticker]),
        },
    ];
    final updatedId = GoalProjectionBuilder.planIdFor(updated);
    final goal = {
      ...(base['active_goal'] as Map? ?? const {}),
      'target_amount': updated.targetAmount,
    };
    final result = <String, Object?>{
      'status': 'ok',
      'monthly_amount': r(monthly),
      'items': items,
      'weighted_dividend_yield_pct':
          realYield == null ? null : _round2(realYield * 100),
      'yield_source': realYield != null ? 'real' : 'assumption',
      'assumed_dividend_yield_pct': PlanAssumptions.dividendYield * 100,
      'yield_coverage_pct': (covered * 100).round(),
      if (merged.isNotEmpty) 'classes_without_instrument': merged,
      if (unknown.isNotEmpty) 'unknown_tickers': unknown,
      'plan_before': {
        'target_amount': r(inputs.targetAmount),
        'required_monthly_savings': r(
          before.requiredMonthly[PlanScenario.base]!,
        ),
      },
      'plan_after': {
        'target_amount': r(updated.targetAmount),
        'required_monthly_savings': r(
          after.requiredMonthly[PlanScenario.base]!,
        ),
        'annual_dividends_at_target': r(
          updated.targetAmount * updated.effectiveDividendYield,
        ),
      },
      // Mismo formato que get_goal_projection: el plan actualizado se
      // puede mostrar con QaSavingsPlan.
      GoalProjectionBuilder.planIdKey: updatedId,
      'plan': after.toToolResult(),
      'active_goal': goal,
      'risk_source': base['risk_source'],
      'risk_adjusted_for_short_horizon':
          base['risk_adjusted_for_short_horizon'],
      'starting_capital_source': base['starting_capital_source'],
      'has_complete_goal': true,
    };
    result[buyPlanIdKey] = _idFor(items, updatedId);
    return result;
  }

  /// Un plan de vivir de dividendos necesita una parte de acciones que
  /// pague dividendos: 2+ instrumentos, al menos una acción individual y
  /// ninguno que rinda casi nada (con el dato real de Yahoo).
  static List<String> _dividendPlanProblems(
    SavingsPlanInputs inputs,
    List<BuyPlanPick> picks,
    Map<String, Object?> info,
    String Function(String) kindOf,
  ) {
    if (inputs.desiredMonthlyIncome == null ||
        inputs.incomeStrategy != IncomeStrategy.dividends) {
      return const [];
    }
    final equities = [
      for (final p in picks)
        if (p.assetClass == PlanAssetClass.equities) p.ticker,
    ];
    final lowYield = [
      for (final t in equities)
        if (info[t] case {
          'dividend_yield_pct': final num y,
        } when y < minDividendYieldPct)
          '$t (${y.toStringAsFixed(1)}%)',
    ];
    return [
      if (equities.length < 2)
        'equities need 2-4 instruments: 2 dividend-focused ETFs and 1-2 '
            'individual dividend stocks',
      if (equities.length >= 2 &&
          !equities.any((t) => kindOf(t) == DividendFetcher.kindStock))
        'add 1-2 individual dividend-paying stocks to equities',
      if (lowYield.isNotEmpty)
        'these barely pay dividends, replace them with dividend-focused '
            'ones: ${lowYield.join(', ')}',
    ];
  }

  static Map<String, Object?>? _infoFields(Object? i) {
    if (i is! Map) return null;
    return {
      for (final k in const [
        'name',
        'price',
        'dividend_yield_pct',
        'dividend_per_share_annual',
        'ex_dividend_date',
      ])
        if (i[k] != null) k: i[k],
      if (i['status'] == 'failed') 'data_status': 'failed',
    };
  }

  /// Porcentajes enteros que suman 100 (mayor resto).
  static Map<String, int> _wholePercents(Map<String, double> share) {
    final total = share.values.fold<double>(0, (a, b) => a + b);
    final raw = {for (final e in share.entries) e.key: e.value / total * 100};
    final out = {for (final e in raw.entries) e.key: e.value.floor()};
    var missing = 100 - out.values.fold<int>(0, (a, b) => a + b);
    final byRest =
        raw.keys.toList()..sort(
          (a, b) =>
              (raw[b]! - raw[b]!.floor()).compareTo(raw[a]! - raw[a]!.floor()),
        );
    for (final k in byRest) {
      if (missing <= 0) break;
      out[k] = out[k]! + 1;
      missing--;
    }
    return out;
  }

  /// Montos redondeados que suman el aporte (el redondeo va al mayor).
  static Map<String, int> _amounts(double monthly, Map<String, int> pcts) {
    final total = monthly.round();
    final out = {
      for (final e in pcts.entries) e.key: (total * e.value / 100).round(),
    };
    final diff = total - out.values.fold<int>(0, (a, b) => a + b);
    if (diff != 0 && out.isNotEmpty) {
      final largest = pcts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      out[largest.key] = out[largest.key]! + diff;
    }
    return out;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _idFor(List<Map<String, Object?>> items, String planId) {
    var hash = 0x811c9dc5;
    final key = jsonEncode([
      planId,
      for (final i in items) [i['ticker'], i['pct']],
    ]);
    for (final byte in utf8.encode(key)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'buy-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
