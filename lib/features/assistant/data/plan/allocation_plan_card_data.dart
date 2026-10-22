import 'package:portfolio_assistant/features/assistant/tools/plan_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Un ticker del plan en la card: objetivo, peso de hoy y desvío (puntos).
class AllocationCardRow {
  const AllocationCardRow({
    required this.ticker,
    required this.targetPct,
    required this.currentPct,
    required this.driftPts,
  });

  final String ticker;
  final double targetPct;
  final double currentPct;
  final double driftPts;
}

/// El plan de cartera tal como lo trajo `get_allocation_plan` en la
/// conversación — nunca lo que escribió el modelo: la card
/// `QaAllocationPlan` pone cada porcentaje y monto desde acá. Gana la
/// llamada `ok` más reciente.
class AllocationPlanCardData {
  const AllocationPlanCardData({
    required this.rows,
    required this.thresholdPts,
    this.portfolioValueUsd,
    this.contributionUsd,
    this.split = const {},
  });

  /// De mayor a menor objetivo (lo que tiene fuera del plan, al final).
  final List<AllocationCardRow> rows;
  final double thresholdPts;
  final double? portfolioValueUsd;
  final double? contributionUsd;

  /// {ticker: monto} del aporte, de mayor a menor.
  final Map<String, double> split;

  bool get hasHoldings => rows.any((r) => r.currentPct > 0);

  List<AllocationCardRow> get offPlan => [
    for (final r in rows)
      if (hasHoldings && r.driftPts.abs() >= thresholdPts) r,
  ];

  /// Peso que tendría cada ticker después del aporte (necesita el valor
  /// de la cartera; si no vino, vacío).
  Map<String, double> get weightsAfter {
    final total = portfolioValueUsd;
    final amount = contributionUsd;
    if (total == null || amount == null || !(total + amount > 0)) {
      return const {};
    }
    return {
      for (final r in rows)
        r.ticker:
            (r.currentPct / 100 * total + (split[r.ticker] ?? 0)) /
            (total + amount) *
            100,
    };
  }

  /// Todos los números que la card puede mostrar (para el chequeo de que
  /// el texto no invente cifras).
  List<double> get backingNumbers => [
    thresholdPts,
    for (final r in rows) ...[
      r.targetPct,
      r.currentPct,
      r.driftPts,
      r.driftPts.abs(),
    ],
    if (portfolioValueUsd != null) portfolioValueUsd!,
    if (contributionUsd != null) contributionUsd!,
    ...split.values,
    ...weightsAfter.values,
    offPlan.length.toDouble(),
  ];

  static AllocationPlanCardData? from(TurnEvidence evidence) {
    for (final call in evidence.calls.reversed) {
      if (call.name != PlanTools.getAllocationPlan || call.status != 'ok') {
        continue;
      }
      return fromJson(call.result);
    }
    return null;
  }

  static AllocationPlanCardData? fromJson(Map<String, dynamic> json) {
    final rows = [
      for (final r in (json['rows'] as List? ?? const []))
        if (r is Map && r['ticker'] is String)
          AllocationCardRow(
            ticker: (r['ticker'] as String).toUpperCase(),
            targetPct: _number(r['target_pct']) ?? 0,
            currentPct: _number(r['current_pct']) ?? 0,
            driftPts: _number(r['drift_pts']) ?? 0,
          ),
    ];
    if (rows.isEmpty) return null;
    final contribution = json['contribution'];
    final split = <String, double>{};
    double? amount;
    if (contribution is Map) {
      amount = _number(contribution['amount_usd']);
      for (final s in (contribution['split'] as List? ?? const [])) {
        if (s is Map && s['ticker'] is String) {
          final v = _number(s['amount_usd']);
          if (v != null && v > 0) {
            split[(s['ticker'] as String).toUpperCase()] = v;
          }
        }
      }
    }
    return AllocationPlanCardData(
      rows: rows,
      thresholdPts: _number(json['drift_threshold']) ?? 5,
      portfolioValueUsd: _number(json['portfolio_value_usd']),
      contributionUsd: amount,
      split: split,
    );
  }

  static double? _number(Object? v) => v is num ? v.toDouble() : null;
}
