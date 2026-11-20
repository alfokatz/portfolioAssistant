import 'dart:math' as math;

/// Cada cuánto revisa Porty si la cartera se alejó del plan (siempre un
/// lunes a las 10, hora local; ver `daily-jobs`).
enum AllocationAlertFrequency {
  /// Todos los lunes.
  weekly,

  /// El primer lunes de cada mes.
  monthly;

  static AllocationAlertFrequency parse(Object? raw) =>
      raw == 'monthly' ? monthly : weekly;
}

/// El plan de cartera del usuario: cuánto quiere de cada ticker.
class AllocationPlan {
  const AllocationPlan({
    this.targets = const {},
    this.driftThreshold = 5,
    this.notify = true,
    this.frequency = AllocationAlertFrequency.weekly,
    this.contributionDay,
    this.contributionAmount,
  });

  /// {TICKER: porcentaje}. Vacío = todavía no armó el plan.
  final Map<String, double> targets;

  /// Puntos de desvío a partir de los que avisa (y la Home lo marca).
  final double driftThreshold;

  /// Aviso (notificación) si se aleja del plan.
  final bool notify;

  /// Cada cuánto se revisa para el aviso.
  final AllocationAlertFrequency frequency;

  /// Día del mes (1-28) en que Porty le recuerda aportar y cómo repartirlo
  /// (ver `daily-jobs`). `null` = sin recordatorio.
  final int? contributionDay;

  /// Cuánto aporta ese día; `null` si no lo dijo (el aviso sale igual).
  final double? contributionAmount;

  bool get hasContributionReminder => contributionDay != null;

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
      frequency: AllocationAlertFrequency.parse(row['notify_frequency']),
      contributionDay: switch (row['contribution_day']) {
        final num d when d >= 1 && d <= 28 => d.toInt(),
        _ => null,
      },
      contributionAmount: switch (row['contribution_amount']) {
        final num a when a > 0 => a.toDouble(),
        final String a when (double.tryParse(a) ?? 0) > 0 => double.parse(a),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toRow() => {
    'targets': {
      for (final e in targets.entries)
        if (e.value > 0) e.key: _round(e.value, 2),
    },
    'drift_threshold': driftThreshold,
    'notify': notify,
    'notify_frequency': frequency.name,
    'contribution_day': contributionDay,
    'contribution_amount':
        contributionDay == null || contributionAmount == null
            ? null
            : _round(contributionAmount!, 2),
  };

  AllocationPlan copyWith({
    Map<String, double>? targets,
    double? driftThreshold,
    bool? notify,
    AllocationAlertFrequency? frequency,
    int? Function()? contributionDay,
    double? Function()? contributionAmount,
  }) => AllocationPlan(
    targets: targets ?? this.targets,
    driftThreshold: driftThreshold ?? this.driftThreshold,
    notify: notify ?? this.notify,
    frequency: frequency ?? this.frequency,
    // Funciones: así se puede volver a null (apagar el recordatorio).
    contributionDay:
        contributionDay == null ? this.contributionDay : contributionDay(),
    contributionAmount:
        contributionAmount == null
            ? this.contributionAmount
            : contributionAmount(),
  );

  @override
  bool operator ==(Object other) =>
      other is AllocationPlan &&
      _sameTargets(other.targets, targets) &&
      other.driftThreshold == driftThreshold &&
      other.notify == notify &&
      other.frequency == frequency &&
      other.contributionDay == contributionDay &&
      other.contributionAmount == contributionAmount;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(targets.entries.map((e) => '${e.key}:${e.value}')),
    driftThreshold,
    notify,
    frequency,
    contributionDay,
    contributionAmount,
  );

  static bool _sameTargets(Map<String, double> a, Map<String, double> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
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

  /// Lo que pesaría cada ticker (en %) después de sumar [split] a [values].
  static Map<String, double> weightsAfter({
    required Map<String, double> values,
    required Map<String, double> split,
  }) {
    final after = <String, double>{
      for (final e in values.entries)
        if (e.value > 0) e.key: e.value,
    };
    for (final e in split.entries) {
      after[e.key] = (after[e.key] ?? 0) + math.max(0, e.value);
    }
    final total = after.values.fold(0.0, (a, b) => a + b);
    if (!(total > 0)) return const {};
    return {for (final e in after.entries) e.key: e.value / total * 100};
  }

  /// Partes iguales entre [tickers], en enteros que suman 100.
  static Map<String, int> equalSplit(List<String> tickers) =>
      _largestRemainder({for (final t in tickers) t: 1});

  /// El reparto con el que arranca el paso "¿cuánto de cada una?": lo que
  /// ya tiene, con sus pesos de hoy (entre lo elegido); lo nuevo, en 0. Si
  /// no tiene nada de lo elegido, partes iguales.
  static Map<String, int> initialSplit({
    required List<String> tickers,
    required Map<String, double> values,
  }) {
    if (tickers.isEmpty) return const {};
    final held = {
      for (final t in tickers)
        if ((values[t] ?? 0) > 0) t: values[t]!,
    };
    if (held.isEmpty) return equalSplit(tickers);
    final split = _largestRemainder(held);
    return {for (final t in tickers) t: split[t] ?? 0};
  }

  /// Mueve [ticker] a [value] y reparte la diferencia entre los demás que
  /// no están en [locked], en proporción a lo que ya tenían (o en partes
  /// iguales si estaban todos en 0), para que el total siga en 100. El
  /// valor se limita a lo que dejan libre los fijos; si no hay a quién
  /// pasarle la diferencia, no se mueve.
  static Map<String, int> rebalance({
    required Map<String, int> targets,
    required String ticker,
    required int value,
    Set<String> locked = const {},
  }) {
    if (!targets.containsKey(ticker)) return targets;
    final others = [
      for (final t in targets.keys)
        if (t != ticker) t,
    ];
    final free = [
      for (final t in others)
        if (!locked.contains(t)) t,
    ];
    final fixedSum = others
        .where(locked.contains)
        .fold(0, (a, t) => a + targets[t]!);
    if (free.isEmpty) {
      return {...targets, ticker: math.max(0, 100 - fixedSum)};
    }
    final v = value.clamp(0, math.max(0, 100 - fixedSum)).toInt();
    final left = 100 - fixedSum - v;
    final freeSum = free.fold(0, (a, t) => a + targets[t]!);
    final shares =
        freeSum > 0
            ? _largestRemainder({
              for (final t in free) t: targets[t]!.toDouble(),
            }, total: left)
            : _largestRemainder({for (final t in free) t: 1}, total: left);
    return {
      for (final t in targets.keys)
        t:
            t == ticker
                ? v
                : locked.contains(t)
                ? targets[t]!
                : shares[t] ?? 0,
    };
  }

  /// Saca [ticker] y le pasa lo suyo a los demás (en proporción).
  static Map<String, int> remove(Map<String, int> targets, String ticker) {
    final rest = {...targets}..remove(ticker);
    if (rest.isEmpty) return const {};
    final sum = rest.values.fold(0, (a, b) => a + b);
    return sum > 0
        ? _largestRemainder({
          for (final e in rest.entries) e.key: e.value.toDouble(),
        })
        : equalSplit(rest.keys.toList());
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

/// Reparte [total] (100 por defecto) en enteros proporcionales a
/// [weights] (método del mayor resto). Los pesos ≤ 0 quedan en 0.
Map<String, int> _largestRemainder(
  Map<String, num> weights, {
  int total = 100,
}) {
  final sum = weights.values.where((w) => w > 0).fold(0.0, (a, b) => a + b);
  if (!(sum > 0) || total <= 0) return {for (final k in weights.keys) k: 0};
  final exact = {
    for (final e in weights.entries)
      e.key: e.value > 0 ? e.value / sum * total : 0.0,
  };
  final floors = {for (final e in exact.entries) e.key: e.value.floor()};
  var left = total - floors.values.fold(0, (a, b) => a + b);
  final byRemainder =
      exact.keys.where((k) => weights[k]! > 0).toList()..sort((a, b) {
        final c = (exact[b]! - floors[b]!).compareTo(exact[a]! - floors[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
  for (final k in byRemainder) {
    if (left <= 0) break;
    floors[k] = floors[k]! + 1;
    left--;
  }
  return floors;
}

double _round(double v, int decimals) {
  final f = math.pow(10, decimals);
  return (v * f).roundToDouble() / f;
}
