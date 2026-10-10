/// Cuándo se cumple una alerta (columna `condition` de `price_alerts`).
enum PriceAlertCondition {
  /// El precio sube a [PriceAlert.target] o más.
  above,

  /// El precio baja a [PriceAlert.target] o menos.
  below,

  /// Sube [PriceAlert.target]% desde [PriceAlert.referencePrice].
  pctUp,

  /// Baja [PriceAlert.target]% desde [PriceAlert.referencePrice].
  pctDown;

  String get storage => switch (this) {
    above => 'above',
    below => 'below',
    pctUp => 'pct_up',
    pctDown => 'pct_down',
  };

  static PriceAlertCondition parse(Object? value) => switch (value) {
    'below' => below,
    'pct_up' => pctUp,
    'pct_down' => pctDown,
    _ => above,
  };

  bool get isPercent => this == pctUp || this == pctDown;
  bool get isUp => this == above || this == pctUp;
}

enum PriceAlertStatus {
  active,
  triggered,
  paused;

  static PriceAlertStatus parse(Object? value) => switch (value) {
    'triggered' => triggered,
    'paused' => paused,
    _ => active,
  };
}

class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.condition,
    required this.target,
    required this.status,
    required this.createdAt,
    this.referencePrice,
    this.repeatDaily = false,
    this.pausedByPlan = false,
    this.lastPrice,
    this.triggeredAt,
    this.triggeredPrice,
  });

  final String id;
  final String symbol;
  final PriceAlertCondition condition;

  /// Precio (above/below) o porcentaje (pct_up/pct_down).
  final double target;
  final double? referencePrice;
  final bool repeatDaily;
  final PriceAlertStatus status;

  /// Pausada porque el plan bajó (vuelve sola al mejorar el plan).
  final bool pausedByPlan;
  final double? lastPrice;
  final DateTime? triggeredAt;
  final double? triggeredPrice;
  final DateTime createdAt;

  /// El precio al que se cumple.
  double get thresholdPrice => switch (condition) {
    PriceAlertCondition.above || PriceAlertCondition.below => target,
    PriceAlertCondition.pctUp => (referencePrice ?? 0) * (1 + target / 100),
    PriceAlertCondition.pctDown => (referencePrice ?? 0) * (1 - target / 100),
  };

  /// ¿[price] ya cumple la condición? (para no crear una alerta cumplida).
  bool isMetBy(double price) =>
      condition.isUp ? price >= thresholdPrice : price <= thresholdPrice;

  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  factory PriceAlert.fromRow(Map<String, dynamic> row) {
    return PriceAlert(
      id: row['id'] as String,
      symbol: row['symbol'] as String,
      condition: PriceAlertCondition.parse(row['condition']),
      target: _num(row['target']) ?? 0,
      referencePrice: _num(row['reference_price']),
      repeatDaily: row['repeat'] == 'daily',
      status: PriceAlertStatus.parse(row['status']),
      pausedByPlan: row['paused_reason'] == 'plan',
      lastPrice: _num(row['last_price']),
      triggeredAt: DateTime.tryParse('${row['triggered_at'] ?? ''}'),
      triggeredPrice: _num(row['triggered_price']),
      createdAt:
          DateTime.tryParse('${row['created_at'] ?? ''}') ?? DateTime.now(),
    );
  }
}

/// Lo que hace falta para crear una alerta.
class PriceAlertDraft {
  const PriceAlertDraft({
    required this.symbol,
    required this.condition,
    required this.target,
    this.referencePrice,
    this.repeatDaily = false,
    this.source = 'app',
  });

  final String symbol;
  final PriceAlertCondition condition;
  final double target;

  /// El precio al crearla (obligatorio para las de porcentaje).
  final double? referencePrice;
  final bool repeatDaily;

  /// `app` o `porty` (creada desde el chat).
  final String source;
}

/// Por qué no se pudo crear o reactivar una alerta.
sealed class PriceAlertFailure implements Exception {
  const PriceAlertFailure();
}

/// Tope de alertas activas del plan.
class PriceAlertLimitReached extends PriceAlertFailure {
  const PriceAlertLimitReached(this.limit);

  final int? limit;
}

class PriceAlertInvalid extends PriceAlertFailure {
  const PriceAlertInvalid();
}

class PriceAlertNetworkError extends PriceAlertFailure {
  const PriceAlertNetworkError();
}
