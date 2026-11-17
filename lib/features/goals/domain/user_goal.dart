import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';

/// De qué se trata la meta.
enum GoalType {
  purchase('purchase'),
  retirement('retirement'),
  other('other');

  const GoalType(this.storageValue);
  final String storageValue;

  static GoalType fromStorage(Object? value) =>
      values.where((v) => v.storageValue == value).firstOrNull ?? other;
}

enum GoalStatus {
  active('active'),
  achieved('achieved'),
  archived('archived');

  const GoalStatus(this.storageValue);
  final String storageValue;

  static GoalStatus fromStorage(Object? value) =>
      values.where((v) => v.storageValue == value).firstOrNull ?? active;
}

/// Un instrumento de la compra mensual guardada con la meta.
class GoalBuyPlanEntry {
  const GoalBuyPlanEntry({
    required this.ticker,
    required this.assetClassLabel,
    required this.pct,
    required this.monthlyAmount,
    this.name,
    this.kind,
  });

  final String ticker;
  final String? name;
  final String? kind;
  final String assetClassLabel;
  final int pct;
  final int monthlyAmount;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    if (name != null) 'name': name,
    if (kind != null) 'kind': kind,
    'asset_class_label': assetClassLabel,
    'pct': pct,
    'monthly_amount': monthlyAmount,
  };

  static GoalBuyPlanEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final ticker = json['ticker'];
    final pct = json['pct'];
    final amount = json['monthly_amount'];
    if (ticker is! String || pct is! num || amount is! num) return null;
    // Una inversión con 0% no es parte del plan (pasaba con una acción en
    // un plan de corto plazo, que no lleva acciones: "VOO · 0 $/mes").
    if (pct <= 0 && amount <= 0) return null;
    return GoalBuyPlanEntry(
      ticker: ticker,
      name: json['name'] as String?,
      kind: json['kind'] as String?,
      assetClassLabel: '${json['asset_class_label'] ?? ''}',
      pct: pct.round(),
      monthlyAmount: amount.round(),
    );
  }
}

/// El plan tal como se guardó: los datos con los que la app lo recalcula
/// (mismo código que la card del chat) y la compra mensual, si la armó.
class GoalPlanSnapshot {
  const GoalPlanSnapshot({required this.inputs, this.buyPlan = const []});

  final SavingsPlanInputs inputs;
  final List<GoalBuyPlanEntry> buyPlan;

  SavingsPlan get plan => SavingsPlan.build(inputs);

  Map<String, Object?> toJson() => {
    'inputs': inputs.toJson(),
    if (buyPlan.isNotEmpty) 'buy_plan': [for (final e in buyPlan) e.toJson()],
  };

  static GoalPlanSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final inputs = SavingsPlanInputs.fromJson(json['inputs']);
    if (inputs == null) return null;
    final raw = json['buy_plan'];
    return GoalPlanSnapshot(
      inputs: inputs,
      buyPlan:
          [
            for (final e in raw is List ? raw : const [])
              GoalBuyPlanEntry.fromJson(e),
          ].whereType<GoalBuyPlanEntry>().toList(),
    );
  }
}

/// Una meta guardada en la pestaña Metas.
class UserGoal {
  const UserGoal({
    required this.id,
    required this.label,
    required this.type,
    required this.targetAmount,
    required this.targetDate,
    required this.snapshot,
    required this.status,
    required this.createdAt,
    this.linkedTickers = const {},
    this.externalSavings = 0,
    this.planKey,
    this.currency = DisplayCurrency.usd,
    this.fxRate,
  });

  /// Tope de metas activas (lo hace cumplir un trigger).
  static const maxActive = 20;

  final String id;
  final String label;
  final GoalType type;
  final double targetAmount;
  final DateTime targetDate;
  final GoalPlanSnapshot snapshot;
  final GoalStatus status;
  final DateTime createdAt;

  /// El `plan_id` del chat con el que se guardó.
  final String? planKey;

  /// Las inversiones de la cartera que cuentan para esta meta (en
  /// mayúsculas). Su valor de mercado se suma solo.
  final Set<String> linkedTickers;

  /// Lo que tiene para la meta fuera de la app (banco, efectivo).
  final double externalSavings;

  /// En qué moneda están los montos de la meta: el objetivo, el aporte del
  /// plan, lo de afuera. Las metas viejas, en dólares.
  final DisplayCurrency currency;

  /// Tipo de cambio de hoy (unidades de [currency] por dólar) para valuar
  /// sus inversiones asignadas, que se cotizan en dólares. Lo pone el
  /// provider de metas al cargarlas ([withFx]); en dólares no hace falta.
  final double? fxRate;

  /// La moneda no es dólar y todavía no hay tipo de cambio: sus inversiones
  /// no se pueden valuar ahora (no cuentan; la pantalla lo avisa y el plan
  /// no se rehace con ese número).
  bool get fxMissing => !currency.isUsd && (fxRate == null || fxRate! <= 0);

  /// Por cuánto se multiplica un valor en dólares para llevarlo a [currency].
  double get _toGoalCurrency => currency.isUsd ? 1 : (fxMissing ? 0 : fxRate!);

  /// La misma meta con el tipo de cambio de hoy para su moneda.
  UserGoal withFx(double? rate) => withCurrency(currency, rate);

  /// La misma meta en otra moneda (los montos quedan como están escritos),
  /// con el tipo de cambio de hoy de esa moneda.
  UserGoal withCurrency(DisplayCurrency to, double? rate) => UserGoal(
    id: id,
    label: label,
    type: type,
    targetAmount: targetAmount,
    targetDate: targetDate,
    snapshot: snapshot,
    status: status,
    createdAt: createdAt,
    linkedTickers: linkedTickers,
    externalSavings: externalSavings,
    planKey: planKey,
    currency: to,
    fxRate: rate,
  );

  /// El valor de cada inversión asignada que el usuario tiene hoy, en la
  /// moneda de la meta ([holdings] = valor de mercado por ticker de su
  /// cartera, en dólares). Sin tipo de cambio ([fxMissing]), vacío.
  Map<String, double> linkedValues(Map<String, double> holdings) {
    final rate = _toGoalCurrency;
    if (rate <= 0) return const {};
    return {
      for (final t in linkedTickers)
        if ((holdings[t] ?? 0) > 0) t: holdings[t]! * rate,
    };
  }

  /// Lo que lleva juntado: sus inversiones asignadas + lo de afuera.
  double savedWith(Map<String, double> holdings) =>
      linkedValues(holdings).values.fold(externalSavings, (a, b) => a + b);

  static UserGoal? fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String?;
    final label = (row['label'] as String?)?.trim();
    final target = row['target_amount'];
    final date = DateTime.tryParse('${row['target_date']}');
    final created = DateTime.tryParse('${row['created_at']}');
    final snapshot = GoalPlanSnapshot.fromJson(row['plan']);
    if (id == null ||
        label == null ||
        target is! num ||
        date == null ||
        created == null ||
        snapshot == null) {
      return null;
    }
    final linked = row['linked_tickers'];
    final external = row['external_savings'];
    return UserGoal(
      id: id,
      label: label,
      type: GoalType.fromStorage(row['goal_type']),
      targetAmount: target.toDouble(),
      targetDate: date,
      snapshot: snapshot,
      status: GoalStatus.fromStorage(row['status']),
      createdAt: created,
      linkedTickers: {
        for (final t in linked is List ? linked : const [])
          if (t is String && t.isNotEmpty) t.toUpperCase(),
      },
      externalSavings: external is num ? external.toDouble() : 0,
      planKey: row['plan_key'] as String?,
      // Sin la columna (base sin migrar) o desconocida: dólares.
      currency: DisplayCurrency.fromCode(row['currency'] as String?),
    );
  }
}

/// Lo necesario para guardar una meta nueva (desde la card del chat o la
/// tool `save_goal`).
class GoalDraft {
  const GoalDraft({
    required this.label,
    required this.type,
    required this.targetAmount,
    required this.targetDate,
    required this.snapshot,
    this.planKey,
    this.currency = DisplayCurrency.usd,
  });

  final String label;
  final GoalType type;
  final double targetAmount;
  final DateTime targetDate;
  final GoalPlanSnapshot snapshot;

  /// La moneda de los montos (los planes del chat, en dólares).
  final DisplayCurrency currency;

  /// El `plan_id` del chat: guardar dos veces el mismo plan no duplica.
  final String? planKey;

  /// El mismo plan con el aporte que eligió el usuario en la card ("Probá
  /// otro aporte"): eso es lo que se guarda al confirmar, con la compra
  /// mensual repartida igual. Un aporte de 0 no cambia nada.
  GoalDraft withMonthlyContribution(double monthly) {
    if (monthly <= 0) return this;
    final inputs = snapshot.inputs.copyWith(monthlyContribution: monthly);
    return GoalDraft(
      label: label,
      type: type,
      targetAmount: targetAmount,
      targetDate: targetDate,
      snapshot: GoalPlanSnapshot(
        inputs: inputs,
        buyPlan: [
          for (final e in snapshot.buyPlan)
            GoalBuyPlanEntry(
              ticker: e.ticker,
              name: e.name,
              kind: e.kind,
              assetClassLabel: e.assetClassLabel,
              pct: e.pct,
              monthlyAmount: (monthly * e.pct / 100).round(),
            ),
        ],
      ),
      planKey: GoalProjectionBuilder.planIdFor(inputs),
      currency: currency,
    );
  }

  /// Desde el resultado de `get_goal_projection` o `get_monthly_buy_plan`
  /// (este trae además la compra mensual). `null` si no es un plan completo.
  static GoalDraft? fromToolResult(Map<String, Object?> result) {
    final plan = result['plan'];
    final inputs = SavingsPlanInputs.fromJson(
      plan is Map ? plan['inputs'] : null,
    );
    final goal = result['active_goal'];
    if (inputs == null || goal is! Map) return null;
    final date = DateTime.tryParse('${goal['target_date']}');
    if (date == null) return null;
    final label = '${goal['label'] ?? ''}'.trim();
    // La compra mensual que armó Porty, o los instrumentos de ejemplo del
    // plan: la meta siempre se guarda diciendo en qué invertir.
    final buyItems = result['items'];
    final suggested = plan is Map ? plan['suggested_instruments'] : null;
    final items =
        buyItems is List && buyItems.isNotEmpty ? buyItems : suggested;
    final planId = result[GoalProjectionBuilder.planIdKey];
    return GoalDraft(
      label: label.isEmpty ? 'Mi meta' : label,
      type:
          result['goal_type'] == GoalProjectionBuilder.goalPurchase ||
                  inputs.shortTerm
              ? GoalType.purchase
              : inputs.isRetirement || inputs.desiredMonthlyIncome != null
              ? GoalType.retirement
              : GoalType.other,
      targetAmount: inputs.targetAmount,
      targetDate: date,
      snapshot: GoalPlanSnapshot(
        inputs: inputs,
        buyPlan:
            [
              for (final i in items is List ? items : const [])
                GoalBuyPlanEntry.fromJson(i),
            ].whereType<GoalBuyPlanEntry>().toList(),
      ),
      planKey: planId is String ? planId : null,
    );
  }
}
