import 'dart:math' as math;

/// El plan de cartera del usuario: cuánto quiere de cada ticker.
class AllocationPlan {
  const AllocationPlan({
    this.targets = const {},
    this.driftThreshold = 5,
    this.notify = true,
  });

  /// {TICKER: porcentaje}. Vacío = todavía no armó el plan.
  final Map<String, double> targets;

  /// Puntos de desvío a partir de los que avisa (y la Home lo marca).
  final double driftThreshold;

  /// Aviso semanal si se aleja del plan.
  final bool notify;

  bool get isEmpty => targets.isEmpty;

  double get targetSum => targets.values.fold(0, (a, b) => a + b);

  /// Los objetivos suman 100 (con medio punto de redondeo, como la base).
  bool get sumsTo100 => isEmpty || (targetSum - 100).abs() <= 0.5;

  static AllocationPlan fromRow(Map<String, dynamic> row) {
    final raw = row['targets'];
    return AllocationPlan(
      targets: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is num && (e.value as num) > 0)
              e.key.toString().toUpperCase(): (e.value as num).toDouble(),
      },
      driftThreshold: (row['drift_threshold'] as num?)?.toDouble() ?? 5,
      notify: row['notify'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toRow() => {
    'targets': {
      for (final e in targets.entries)
        if (e.value > 0) e.key: _round(e.value, 2),
    },
    'drift_threshold': driftThreshold,
    'notify': notify,
  };

  AllocationPlan copyWith({
    Map<String, double>? targets,
    double? driftThreshold,
    bool? notify,
  }) => AllocationPlan(
    targets: targets ?? this.targets,
    driftThreshold: driftThreshold ?? this.driftThreshold,
    notify: notify ?? this.notify,
  );
}

/// Un ticker del plan: lo que vale hoy, su peso y su objetivo.
class AllocationRow {
  const AllocationRow({
    required this.ticker,
    required this.value,
    required this.currentPct,
    required this.targetPct,
  });

  final String ticker;
  final double value;
  final double currentPct;
  final double targetPct;

  /// Puntos porcentuales por encima (+) o por debajo (−) del objetivo.
  double get drift => currentPct - targetPct;
}

/// Cuentas del plan de cartera. Puras: los valores entran en dólares.
abstract final class AllocationMath {
  /// Una fila por ticker que tiene o que está en el plan, de mayor a menor
  /// objetivo (y después por valor).
  static List<AllocationRow> rows({
    required Map<String, double> values,
    required Map<String, double> targets,
  }) {
    final total = values.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    final tickers = {...values.keys, ...targets.keys};
    final rows = [
      for (final t in tickers)
        AllocationRow(
          ticker: t,
          value: math.max(0, values[t] ?? 0),
          currentPct: total > 0 ? math.max(0, values[t] ?? 0) / total * 100 : 0,
          targetPct: targets[t] ?? 0,
        ),
    ];
    rows.sort((a, b) {
      final byTarget = b.targetPct.compareTo(a.targetPct);
      if (byTarget != 0) return byTarget;
      final byValue = b.value.compareTo(a.value);
      return byValue != 0 ? byValue : a.ticker.compareTo(b.ticker);
    });
    return rows;
  }

  /// El mayor desvío, en puntos (siempre positivo). 0 sin plan.
  static double maxDrift(List<AllocationRow> rows) =>
      rows.fold(0.0, (m, r) => math.max(m, r.drift.abs()));

  /// Cómo repartir un aporte de [amount] para acercarse al plan, solo con
  /// compras: a cada ticker le falta `max(0, objetivo × (total + aporte) −
  /// valor)`; el aporte se reparte en proporción a lo que falta. Como lo
  /// que falta suma al menos el aporte, nunca se pasa.
  static Map<String, double> contribution({
    required Map<String, double> values,
    required Map<String, double> targets,
    required double amount,
  }) {
    if (!(amount > 0) || targets.isEmpty) return const {};
    final targetSum = targets.values.fold(0.0, (a, b) => a + b);
    if (!(targetSum > 0)) return const {};
    final total = values.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    final after = total + amount;
    final missing = <String, double>{
      for (final e in targets.entries)
        e.key: math.max(
          0,
          e.value / targetSum * after - math.max(0, values[e.key] ?? 0),
        ),
    };
    final missingSum = missing.values.fold(0.0, (a, b) => a + b);
    if (!(missingSum > 0)) return const {};
    return {
      for (final e in missing.entries)
        if (e.value > 0) e.key: _round(amount * e.value / missingSum, 2),
    };
  }

  /// Objetivos iguales a los pesos de hoy (para empezar el plan),
  /// redondeados a enteros que suman 100.
  static Map<String, double> fromCurrentWeights(Map<String, double> values) {
    final positive = {
      for (final e in values.entries)
        if (e.value > 0) e.key: e.value,
    };
    final total = positive.values.fold(0.0, (a, b) => a + b);
    if (!(total > 0)) return const {};
    return roundTo100({
      for (final e in positive.entries) e.key: e.value / total * 100,
    });
  }

  /// Escala los objetivos para que sumen 100, en enteros (método del mayor
  /// resto: el redondeo no deja la suma en 99 o 101).
  static Map<String, double> roundTo100(Map<String, double> targets) {
    final sum = targets.values.where((v) => v > 0).fold(0.0, (a, b) => a + b);
    if (!(sum > 0)) return const {};
    final scaled = {
      for (final e in targets.entries)
        if (e.value > 0) e.key: e.value / sum * 100,
    };
    final floors = {for (final e in scaled.entries) e.key: e.value.floor()};
    var left = 100 - floors.values.fold(0, (a, b) => a + b);
    final byRemainder =
        scaled.keys.toList()..sort((a, b) {
          final ra = scaled[a]! - floors[a]!;
          final rb = scaled[b]! - floors[b]!;
          final c = rb.compareTo(ra);
          return c != 0 ? c : a.compareTo(b);
        });
    for (final k in byRemainder) {
      if (left <= 0) break;
      floors[k] = floors[k]! + 1;
      left--;
    }
    return {
      for (final e in floors.entries)
        if (e.value > 0) e.key: e.value.toDouble(),
    };
  }
}

double _round(double v, int decimals) {
  final f = math.pow(10, decimals);
  return (v * f).roundToDouble() / f;
}
