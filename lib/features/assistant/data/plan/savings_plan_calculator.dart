import 'dart:math' as math;

import 'package:portfolio_assistant/domain/entities/investor_profile.dart';

/// Escenario de rendimiento de un plan de ahorro.
enum PlanScenario {
  pessimistic('pessimistic'),
  base('base'),
  optimistic('optimistic');

  const PlanScenario(this.key);
  final String key;
}

/// Clase de activo de la cartera sugerida, con su rendimiento REAL anual
/// (después de inflación) por escenario.
enum PlanAssetClass {
  equities('equities', 'Acciones globales', {
    PlanScenario.pessimistic: 0.02,
    PlanScenario.base: 0.05,
    PlanScenario.optimistic: 0.07,
  }),
  bonds('bonds', 'Bonos', {
    PlanScenario.pessimistic: 0.0,
    PlanScenario.base: 0.015,
    PlanScenario.optimistic: 0.025,
  }),
  cash('cash', 'Liquidez', {
    PlanScenario.pessimistic: 0.0,
    PlanScenario.base: 0.005,
    PlanScenario.optimistic: 0.01,
  });

  const PlanAssetClass(this.key, this.label, this.realReturn);
  final String key;
  final String label;
  final Map<PlanScenario, double> realReturn;
}

/// Los supuestos del plan, en un solo lugar.
///
/// Rendimientos reales de largo plazo, deliberadamente prudentes: el
/// escenario base de acciones (5%) queda por debajo del histórico de EE. UU.
/// (~6,5–7% real) y cerca de lo que publican las gestoras para la próxima
/// década; el optimista es el histórico y el pesimista, una década floja.
/// Son supuestos de clase de activo, no de tickers: qué instrumentos usar lo
/// elige Porty con datos, nunca de una lista fija.
abstract final class PlanAssumptions {
  /// Inflación anual en USD: solo para traducir la meta en dólares de hoy a
  /// dólares de la fecha (todo el cálculo es en términos reales).
  static const inflation = 0.025;

  /// Retiro anual sostenible sobre el capital (la "regla del 4%").
  static const safeWithdrawalRate = 0.04;

  /// Rendimiento por dividendos de una cartera de acciones/ETFs de
  /// dividendos amplia (antes de impuestos). Los dividendos suelen crecer
  /// con la inflación, así que se usa como rendimiento real. Supuesto fijo
  /// para que el plan siempre salga; los ejemplos con su rendimiento actual
  /// los trae Porty con datos.
  static const dividendYield = 0.035;

  /// Con menos que esto, la parte en acciones puede caer y no recuperarse a
  /// tiempo: el plan pasa a conservador.
  static const shortHorizonMonths = 36;

  /// Cuánto se adelanta/posterga la meta en "¿Qué pasa si…?".
  static const sensitivityMonths = 60;

  /// Cartera de una compra a menos de [shortHorizonMonths]: la plata se
  /// necesita en meses, así que va casi toda a liquidez (cuentas
  /// remuneradas, fondos de money market, letras del Tesoro) y el resto a
  /// bonos cortos. Nada en acciones, sea cual sea el perfil.
  static const shortTermAllocation = {
    PlanAssetClass.cash: 0.70,
    PlanAssetClass.bonds: 0.30,
  };

  static Map<PlanAssetClass, double> allocationFor(
    RiskTolerance risk, {
    bool shortTerm = false,
  }) =>
      shortTerm
          ? shortTermAllocation
          : switch (risk) {
        RiskTolerance.conservative => const {
          PlanAssetClass.equities: 0.30,
          PlanAssetClass.bonds: 0.60,
          PlanAssetClass.cash: 0.10,
        },
        RiskTolerance.moderate => const {
          PlanAssetClass.equities: 0.60,
          PlanAssetClass.bonds: 0.35,
          PlanAssetClass.cash: 0.05,
        },
        RiskTolerance.aggressive => const {
          PlanAssetClass.equities: 0.85,
          PlanAssetClass.bonds: 0.15,
        },
      };

  /// Rendimiento real anual de la cartera de [risk] en [scenario].
  static double realReturn(
    RiskTolerance risk,
    PlanScenario scenario, {
    bool shortTerm = false,
  }) {
    var total = 0.0;
    allocationFor(risk, shortTerm: shortTerm).forEach((asset, weight) {
      total += weight * asset.realReturn[scenario]!;
    });
    return total;
  }
}

/// Cómo se cobra un ingreso mensual con el capital juntado.
enum IncomeStrategy {
  /// Vivir de los dividendos: el capital no se toca.
  dividends('dividends'),

  /// Retirar el 4% por año: hace falta menos capital, pero se consume.
  withdrawal('withdrawal');

  const IncomeStrategy(this.key);
  final String key;

  static IncomeStrategy? fromKey(String? key) =>
      values.where((v) => v.key == key).firstOrNull;
}

/// Los datos de los que sale un plan. Es lo que viaja en el resultado de la
/// tool: la card lo vuelve a calcular con [SavingsPlan.build] (mismo código,
/// mismos números) en vez de copiar una serie larga del modelo.
class SavingsPlanInputs {
  const SavingsPlanInputs({
    required this.targetAmount,
    required this.months,
    required this.currentAmount,
    required this.risk,
    required this.startDate,
    this.monthlyContribution,
    this.isRetirement = false,
    this.desiredMonthlyIncome,
    this.incomeStrategy = IncomeStrategy.dividends,
    this.dividendYield,
    this.shortTerm = false,
  });

  /// En dólares de hoy.
  final double targetAmount;
  final int months;
  final double currentAmount;

  /// El riesgo con el que se arma la cartera (ya ajustado por plazo).
  final RiskTolerance risk;
  final DateTime startDate;

  /// El aporte que el usuario dijo que puede hacer; `null` = el plan usa el
  /// necesario del escenario base.
  final double? monthlyContribution;
  final bool isRetirement;

  /// El ingreso que pidió el usuario ("cobrar 3000 por mes"), si lo pidió:
  /// la meta es el capital que lo genera con [incomeStrategy].
  final double? desiredMonthlyIncome;
  final IncomeStrategy incomeStrategy;

  /// Rendimiento por dividendos real de la compra mensual (fracción); `null`
  /// = el supuesto [PlanAssumptions.dividendYield].
  final double? dividendYield;

  /// Compra a corto plazo (ver [PlanAssumptions.shortTermAllocation]).
  final bool shortTerm;

  double get effectiveDividendYield =>
      dividendYield ?? PlanAssumptions.dividendYield;

  SavingsPlanInputs copyWith({double? targetAmount, double? dividendYield}) =>
      SavingsPlanInputs(
        targetAmount: targetAmount ?? this.targetAmount,
        months: months,
        currentAmount: currentAmount,
        risk: risk,
        startDate: startDate,
        monthlyContribution: monthlyContribution,
        isRetirement: isRetirement,
        desiredMonthlyIncome: desiredMonthlyIncome,
        incomeStrategy: incomeStrategy,
        dividendYield: dividendYield ?? this.dividendYield,
        shortTerm: shortTerm,
      );

  Map<String, Object?> toJson() => {
    'target_amount': targetAmount,
    'months': months,
    'current_amount': currentAmount,
    'risk': risk.storageValue,
    'start_date': _date(startDate),
    'monthly_contribution': monthlyContribution,
    'is_retirement': isRetirement,
    'desired_monthly_income': desiredMonthlyIncome,
    'income_strategy': incomeStrategy.key,
    if (dividendYield != null) 'dividend_yield': dividendYield,
    if (shortTerm) 'short_term': true,
  };

  static SavingsPlanInputs? fromJson(Object? json) {
    if (json is! Map) return null;
    final target = json['target_amount'];
    final months = json['months'];
    final current = json['current_amount'];
    final risk = RiskTolerance.fromStorage(json['risk'] as String?);
    final start = DateTime.tryParse('${json['start_date']}');
    if (target is! num || months is! num || risk == null || start == null) {
      return null;
    }
    final monthly = json['monthly_contribution'];
    final income = json['desired_monthly_income'];
    final yieldOverride = json['dividend_yield'];
    return SavingsPlanInputs(
      targetAmount: target.toDouble(),
      months: months.toInt(),
      currentAmount: current is num ? current.toDouble() : 0,
      risk: risk,
      startDate: start,
      monthlyContribution: monthly is num ? monthly.toDouble() : null,
      isRetirement: json['is_retirement'] == true,
      desiredMonthlyIncome: income is num ? income.toDouble() : null,
      incomeStrategy:
          IncomeStrategy.fromKey(json['income_strategy'] as String?) ??
          IncomeStrategy.dividends,
      dividendYield: yieldOverride is num ? yieldOverride.toDouble() : null,
      shortTerm: json['short_term'] == true,
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Un punto de la curva del plan (uno por año, más el final exacto).
class PlanCurvePoint {
  const PlanCurvePoint({
    required this.month,
    required this.contributed,
    required this.values,
  });

  final int month;

  /// Capital inicial + aportes acumulados (sin intereses).
  final double contributed;
  final Map<PlanScenario, double> values;

  double get base => values[PlanScenario.base]!;
}

/// La fase de retiro: los dos caminos para cobrar un ingreso mensual.
///
/// Con ingreso pedido ([desiredMonthly]): cuánto capital necesita cada
/// camino. Sin él: cuánto ingreso da la meta por cada camino.
class IncomePlan {
  const IncomePlan({
    required this.strategy,
    required this.dividendsCapital,
    required this.withdrawalCapital,
    required this.dividendsMonthly,
    required this.withdrawalMonthly,
    required this.withdrawalYears,
    this.desiredMonthly,
  });

  final double? desiredMonthly;

  /// El camino con el que se fijó la meta del plan.
  final IncomeStrategy strategy;

  /// Capital para cobrar el ingreso pedido (o el de la meta) por cada
  /// camino.
  final double dividendsCapital;
  final double withdrawalCapital;

  /// Ingreso mensual que da la meta por cada camino.
  final double dividendsMonthly;
  final double withdrawalMonthly;

  /// Años que dura el capital retirando el 4% con una cartera
  /// conservadora; `null` = no se agota.
  final int? withdrawalYears;

  static IncomePlan build(SavingsPlanInputs inputs) {
    final target = inputs.targetAmount;
    final desired = inputs.desiredMonthlyIncome;
    final withdrawalMonthly =
        desired ?? SavingsPlanCalculator.sustainableMonthlyIncome(target);
    final withdrawalCapital =
        desired == null
            ? target
            : SavingsPlanCalculator.capitalForIncome(desired);
    final lasting = SavingsPlanCalculator.monthsCapitalLasts(
      capital: withdrawalCapital,
      monthlyWithdrawal: withdrawalMonthly,
      annualReturn: PlanAssumptions.realReturn(
        RiskTolerance.conservative,
        PlanScenario.base,
      ),
    );
    return IncomePlan(
      desiredMonthly: desired,
      strategy: inputs.incomeStrategy,
      dividendsCapital:
          desired == null
              ? target
              : SavingsPlanCalculator.capitalForDividends(
                desired,
                inputs.effectiveDividendYield,
              ),
      withdrawalCapital: withdrawalCapital,
      dividendsMonthly:
          desired ??
          SavingsPlanCalculator.dividendMonthlyIncome(
            target,
            inputs.effectiveDividendYield,
          ),
      withdrawalMonthly: withdrawalMonthly,
      withdrawalYears: lasting == null ? null : lasting ~/ 12,
    );
  }
}

/// Un "¿qué pasa si…?": la misma meta con otro plazo.
class PlanSensitivity {
  const PlanSensitivity({
    required this.key,
    required this.monthsDelta,
    required this.requiredMonthly,
  });

  final String key;
  final int monthsDelta;
  final double requiredMonthly;
}

/// Un plan de ahorro con interés compuesto: cuánto ahorrar por mes en cada
/// escenario, a dónde se llega con el aporte elegido, la cartera sugerida y,
/// si es para el retiro, cuánto ingreso da.
///
/// Todo en términos reales (dólares de hoy): aportes que suben con la
/// inflación y rendimientos después de inflación.
class SavingsPlan {
  const SavingsPlan._({
    required this.inputs,
    required this.requiredMonthly,
    required this.requiredMonthlyNoReturn,
    required this.monthlyUsed,
    required this.projected,
    required this.contributed,
    required this.returns,
    required this.allocation,
    required this.nominalTarget,
    required this.sensitivities,
    this.income,
  });

  final SavingsPlanInputs inputs;

  /// Ahorro mensual necesario por escenario.
  final Map<PlanScenario, double> requiredMonthly;

  /// Lo que haría falta sin invertir (guardando en efectivo).
  final double requiredMonthlyNoReturn;

  /// El aporte con el que se proyecta: el del usuario o el base necesario.
  final double monthlyUsed;

  /// Monto a la fecha con [monthlyUsed], por escenario.
  final Map<PlanScenario, double> projected;

  /// Capital inicial + aportes con [monthlyUsed].
  final double contributed;

  /// Rendimiento real anual de la cartera por escenario.
  final Map<PlanScenario, double> returns;
  final Map<PlanAssetClass, double> allocation;

  /// La meta expresada en dólares de la fecha objetivo.
  final double nominalTarget;
  final List<PlanSensitivity> sensitivities;
  final IncomePlan? income;

  double get projectedBase => projected[PlanScenario.base]!;
  double get growth => math.max(0, projectedBase - contributed);
  bool get onTrack => projectedBase >= inputs.targetAmount - 0.5;
  bool get alreadyReached => inputs.currentAmount >= inputs.targetAmount;

  static SavingsPlan build(SavingsPlanInputs inputs) {
    final months = math.max(1, inputs.months);
    final returns = {
      for (final s in PlanScenario.values)
        s: PlanAssumptions.realReturn(
          inputs.risk,
          s,
          shortTerm: inputs.shortTerm,
        ),
    };
    final required = {
      for (final s in PlanScenario.values)
        s: SavingsPlanCalculator.requiredMonthly(
          target: inputs.targetAmount,
          current: inputs.currentAmount,
          months: months,
          annualReturn: returns[s]!,
        ),
    };
    final monthly = inputs.monthlyContribution ?? required[PlanScenario.base]!;
    final projected = {
      for (final s in PlanScenario.values)
        s: SavingsPlanCalculator.futureValue(
          current: inputs.currentAmount,
          monthly: monthly,
          months: months,
          annualReturn: returns[s]!,
        ),
    };

    final sensitivities = <PlanSensitivity>[
      if (months > PlanAssumptions.sensitivityMonths + 12)
        PlanSensitivity(
          key: 'sooner',
          monthsDelta: -PlanAssumptions.sensitivityMonths,
          requiredMonthly: SavingsPlanCalculator.requiredMonthly(
            target: inputs.targetAmount,
            current: inputs.currentAmount,
            months: months - PlanAssumptions.sensitivityMonths,
            annualReturn: returns[PlanScenario.base]!,
          ),
        ),
      PlanSensitivity(
        key: 'later',
        monthsDelta: PlanAssumptions.sensitivityMonths,
        requiredMonthly: SavingsPlanCalculator.requiredMonthly(
          target: inputs.targetAmount,
          current: inputs.currentAmount,
          months: months + PlanAssumptions.sensitivityMonths,
          annualReturn: returns[PlanScenario.base]!,
        ),
      ),
    ];

    final income =
        inputs.isRetirement || inputs.desiredMonthlyIncome != null
            ? IncomePlan.build(inputs)
            : null;

    return SavingsPlan._(
      inputs: inputs,
      requiredMonthly: required,
      requiredMonthlyNoReturn: SavingsPlanCalculator.requiredMonthly(
        target: inputs.targetAmount,
        current: inputs.currentAmount,
        months: months,
        annualReturn: 0,
      ),
      monthlyUsed: monthly,
      projected: projected,
      contributed: inputs.currentAmount + monthly * months,
      returns: returns,
      allocation: PlanAssumptions.allocationFor(
        inputs.risk,
        shortTerm: inputs.shortTerm,
      ),
      nominalTarget:
          inputs.targetAmount *
          math.pow(1 + PlanAssumptions.inflation, months / 12),
      sensitivities: sensitivities,
      income: income,
    );
  }

  /// La curva con un aporte [monthly] (el slider de la card): un punto por
  /// año y el final exacto.
  List<PlanCurvePoint> curve({double? monthly}) {
    final m = monthly ?? monthlyUsed;
    final months = math.max(1, inputs.months);
    final checkpoints =
        <int>{
            for (var month = 0; month < months; month += 12) month,
            months,
          }.toList()
          ..sort();
    return [
      for (final month in checkpoints)
        PlanCurvePoint(
          month: month,
          contributed: inputs.currentAmount + m * month,
          values: {
            for (final s in PlanScenario.values)
              s: SavingsPlanCalculator.futureValue(
                current: inputs.currentAmount,
                monthly: m,
                months: month,
                annualReturn: returns[s]!,
              ),
          },
        ),
    ];
  }

  /// Resumen para el modelo (redondeado: los números exactos los pone la
  /// card). Incluye [SavingsPlanInputs] para que la card lo recalcule.
  Map<String, Object?> toToolResult() {
    int r(double v) => v.round();
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    return {
      'inputs': inputs.toJson(),
      'risk_used': inputs.risk.storageValue,
      if (inputs.shortTerm) 'short_term_allocation': true,
      'expected_real_return': {
        for (final s in PlanScenario.values) s.key: pct(returns[s]!),
      },
      'required_monthly_savings': {
        for (final s in PlanScenario.values) s.key: r(requiredMonthly[s]!),
      },
      'required_monthly_without_investing': r(requiredMonthlyNoReturn),
      'monthly_contribution_used': r(monthlyUsed),
      'projected_amount_at_date': {
        for (final s in PlanScenario.values) s.key: r(projected[s]!),
      },
      'total_contributed': r(contributed),
      'total_growth': r(growth),
      // Solo con un aporte que dijo el usuario: sin él, el plan usa el
      // necesario y "llega" por definición.
      'on_track': inputs.monthlyContribution != null ? onTrack : null,
      'target_in_future_dollars': r(nominalTarget),
      'suggested_allocation': [
        for (final e in allocation.entries)
          {'asset_class': e.key.label, 'pct': (e.value * 100).round()},
      ],
      'what_if': [
        for (final s in sensitivities)
          {
            'months_delta': s.monthsDelta,
            'required_monthly_savings': r(s.requiredMonthly),
          },
      ],
      if (income != null)
        'income': {
          if (income!.desiredMonthly != null)
            'desired_monthly_income': r(income!.desiredMonthly!),
          'strategy_used_for_target': income!.strategy.key,
          'dividend_yield': pct(inputs.effectiveDividendYield),
          'dividend_yield_source':
              inputs.dividendYield != null ? 'buy_plan' : 'assumption',
          'dividends': {
            'capital_needed': r(income!.dividendsCapital),
            'monthly_income': r(income!.dividendsMonthly),
            'capital_is_preserved': true,
          },
          'withdraw_4pct': {
            'capital_needed': r(income!.withdrawalCapital),
            'monthly_income': r(income!.withdrawalMonthly),
            'years_lasting': income!.withdrawalYears,
          },
        },
    };
  }
}

/// Las fórmulas del plan (interés compuesto mensual). Funciones puras.
abstract final class SavingsPlanCalculator {
  /// Tasa mensual equivalente a [annual] (compuesta, no `annual / 12`).
  static double monthlyRate(double annual) =>
      math.pow(1 + annual, 1 / 12).toDouble() - 1;

  /// Capital después de [months] meses aportando [monthly] a fin de mes.
  static double futureValue({
    required double current,
    required double monthly,
    required int months,
    required double annualReturn,
  }) {
    if (months <= 0) return current;
    final r = monthlyRate(annualReturn);
    if (r.abs() < 1e-12) return current + monthly * months;
    final growth = math.pow(1 + r, months).toDouble();
    return current * growth + monthly * (growth - 1) / r;
  }

  /// Aporte mensual para llegar a [target] en [months] meses (0 si el
  /// capital actual ya alcanza solo).
  static double requiredMonthly({
    required double target,
    required double current,
    required int months,
    required double annualReturn,
  }) {
    final n = math.max(1, months);
    final r = monthlyRate(annualReturn);
    if (r.abs() < 1e-12) return math.max(0, (target - current) / n);
    final growth = math.pow(1 + r, n).toDouble();
    final gap = target - current * growth;
    if (gap <= 0) return 0;
    return gap * r / (growth - 1);
  }

  /// Ingreso mensual sostenible de un capital (regla del 4%).
  static double sustainableMonthlyIncome(double capital) =>
      capital * PlanAssumptions.safeWithdrawalRate / 12;

  /// Meses que dura [capital] retirando [monthlyWithdrawal]; `null` si el
  /// rendimiento cubre el retiro y no se agota nunca.
  static int? monthsCapitalLasts({
    required double capital,
    required double monthlyWithdrawal,
    required double annualReturn,
  }) {
    if (monthlyWithdrawal <= 0) return null;
    final r = monthlyRate(annualReturn);
    if (r.abs() < 1e-12) return (capital / monthlyWithdrawal).floor();
    final ratio = capital * r / monthlyWithdrawal;
    if (ratio >= 1) return null;
    return (-math.log(1 - ratio) / math.log(1 + r)).floor();
  }

  /// Ingreso mensual por dividendos de un capital.
  static double dividendMonthlyIncome(
    double capital, [
    double yield = PlanAssumptions.dividendYield,
  ]) => capital * yield / 12;

  /// Capital que hace falta para cobrar [monthlyIncome] de dividendos.
  static double capitalForDividends(
    double monthlyIncome, [
    double yield = PlanAssumptions.dividendYield,
  ]) => monthlyIncome * 12 / yield;

  /// Capital que hace falta para cobrar [monthlyIncome] con la regla del 4%.
  static double capitalForIncome(double monthlyIncome) =>
      monthlyIncome * 12 / PlanAssumptions.safeWithdrawalRate;
}
