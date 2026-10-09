import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_savings_plan_chart.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// La card del plan de ahorro (metas y jubilación).
///
/// El modelo solo pasa `planId`: el plan sale del resultado de
/// `get_goal_projection` ([QaEvidenceScope]) y se recalcula acá con
/// [SavingsPlan.build] — así ningún número de la card lo escribe el modelo,
/// y el slider de aporte puede mover la curva sin otra consulta.
abstract final class SavingsPlanWidgets {
  static Widget qaSavingsPlan(CatalogItemContext ctx) {
    final id = '${(ctx.data as JsonMap)['planId'] ?? ''}';
    return Builder(
      builder:
          (context) => ValueListenableBuilder(
            valueListenable: QaEvidenceScope.listenableOf(
              context,
              ctx.surfaceId,
            ),
            builder: (context, evidence, _) {
              final data = SavingsPlanCardData.from(evidence.calls, id);
              if (data == null) return const SizedBox.shrink();
              return QaCardShell.staged(
                key: ValueKey(id),
                staged:
                    (context, active, onFinished) => QaSavingsPlanCard(
                      data: data,
                      active: active,
                      onFinished: onFinished,
                    ),
              );
            },
          ),
    );
  }
}

/// Lo que la card necesita del resultado de la tool.
class SavingsPlanCardData {
  const SavingsPlanCardData({
    required this.plan,
    required this.label,
    required this.targetDate,
    required this.riskSource,
    required this.shortHorizon,
    required this.capitalStated,
    this.desiredMonthlyIncome,
  });

  final SavingsPlan plan;
  final String label;
  final DateTime targetDate;
  final String riskSource;
  final bool shortHorizon;
  final bool capitalStated;
  final double? desiredMonthlyIncome;

  /// Los montos que muestra la card (para que la intro no los repita).
  Iterable<double> get backingNumbers sync* {
    final p = plan;
    yield p.inputs.targetAmount;
    yield p.inputs.currentAmount;
    yield* p.requiredMonthly.values;
    yield p.requiredMonthlyNoReturn;
    yield* p.projected.values;
    yield p.contributed;
    yield p.growth;
    yield p.nominalTarget;
    for (final s in p.sensitivities) {
      yield s.requiredMonthly;
    }
    if (p.retirement != null) yield p.retirement!.monthlyIncome;
    if (desiredMonthlyIncome != null) yield desiredMonthlyIncome!;
  }

  /// El plan [planId] entre las tool calls a la vista, o `null`.
  static SavingsPlanCardData? from(List<ToolCallRecord> calls, String planId) {
    if (planId.isEmpty) return null;
    for (final call in calls.reversed) {
      if (call.name != GetGoalProjectionTool.toolName) continue;
      if (call.status != 'ok') continue;
      if (call.result[GoalProjectionBuilder.planIdKey] != planId) continue;
      return fromToolResult(call.result);
    }
    return null;
  }

  static SavingsPlanCardData? fromToolResult(Map<String, Object?> result) {
    final plan = result['plan'];
    final inputs = SavingsPlanInputs.fromJson(
      plan is Map ? plan['inputs'] : null,
    );
    final goal = result['active_goal'];
    if (inputs == null || goal is! Map) return null;
    final date = DateTime.tryParse('${goal['target_date']}');
    if (date == null) return null;
    final income = result['target_from_income'];
    final desired = income is Map ? income['desired_monthly_income'] : null;
    return SavingsPlanCardData(
      plan: SavingsPlan.build(inputs),
      label: '${goal['label'] ?? ''}'.trim(),
      targetDate: date,
      riskSource:
          '${result['risk_source'] ?? GoalProjectionBuilder.riskDefault}',
      shortHorizon: result['risk_adjusted_for_short_horizon'] == true,
      capitalStated: result['starting_capital_source'] == 'stated',
      desiredMonthlyIncome: desired is num ? desired.toDouble() : null,
    );
  }
}

class QaSavingsPlanCard extends StatefulWidget {
  const QaSavingsPlanCard({
    super.key,
    required this.data,
    this.active = true,
    this.onFinished,
  });

  final SavingsPlanCardData data;
  final bool active;
  final VoidCallback? onFinished;

  @override
  State<QaSavingsPlanCard> createState() => _QaSavingsPlanCardState();
}

class _QaSavingsPlanCardState extends State<QaSavingsPlanCard> {
  /// Aporte elegido con el slider; `null` = el del plan.
  double? _monthly;

  SavingsPlan get _plan => widget.data.plan;
  SavingsPlanInputs get _inputs => _plan.inputs;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final plan = _plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaCardTitle(
          title: data.label.isEmpty ? 'Tu plan' : data.label,
          subtitle:
              '${QaFormat.money(_inputs.targetAmount)} en '
              '${_horizon(_inputs.months)}',
          icon:
              _inputs.isRetirement
                  ? Icons.beach_access_outlined
                  : Icons.flag_outlined,
          trailing: QaTag(_riskName(_inputs.risk), color: QaColors.accentBlue),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        _hero(plan),
        QaSection(title: 'Cómo crece', child: _growth(plan)),
        QaSection(
          title: 'Cartera sugerida',
          trailing: Text(
            '≈${_pct(plan.returns[PlanScenario.base]!)} anual real',
            style: QaText.caption,
          ),
          child: _allocation(plan),
        ),
        if (plan.retirement != null)
          QaSection(
            title: 'Al jubilarte',
            child: _retirement(plan.retirement!),
          ),
        if (plan.sensitivities.isNotEmpty)
          QaSection(title: '¿Y si cambiás el plazo?', child: _whatIf(plan)),
        QaSection(child: Text(_assumptions(plan), style: QaText.caption)),
        QaFollowUpBar(items: _followUps()),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Secciones
  // ---------------------------------------------------------------------

  Widget _hero(SavingsPlan plan) {
    final stated = _inputs.monthlyContribution;
    if (plan.alreadyReached) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QaSectionLabel(
            'Tu meta',
            trailing: QaTag(
              'Ya alcanzada',
              color: QaColors.profit,
              icon: Icons.check_rounded,
            ),
          ),
          const SizedBox(height: 8),
          Text(QaFormat.money(_inputs.currentAmount), style: QaText.display),
          const SizedBox(height: 2),
          Text(
            'Con lo que ya tenés invertido llegás sin aportar más.',
            style: QaText.label,
          ),
        ],
      );
    }

    final required = plan.requiredMonthly;
    final subtitle =
        [
          if (stated != null) 'Hoy aportás ${QaFormat.money(stated)}/mes',
          if (plan.requiredMonthlyNoReturn > required[PlanScenario.base]! + 1)
            'sin invertir serían '
                '${QaFormat.money(plan.requiredMonthlyNoReturn)}/mes',
        ].join(' · ').capitalized();
    final tag =
        stated == null
            ? null
            : plan.onTrack
            ? QaTag('Llegás', color: QaColors.profit, icon: Icons.check_rounded)
            : QaTag(
              'Falta ritmo',
              color: QaColors.loss,
              icon: Icons.trending_down_rounded,
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel('Ahorro mensual sugerido', trailing: tag),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              QaFormat.money(required[PlanScenario.base]!),
              style: QaText.display,
            ),
            const SizedBox(width: 4),
            Text('/ mes', style: QaText.label),
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: QaText.label),
        ],
        const SizedBox(height: QaSpace.gap),
        QaInset(
          child: QaStatGrid(
            columns: 3,
            stats: [
              QaStat(
                label: 'Mercado flojo',
                value: QaFormat.money(required[PlanScenario.pessimistic]!),
              ),
              QaStat(
                label: 'Esperado',
                value: QaFormat.money(required[PlanScenario.base]!),
              ),
              QaStat(
                label: 'Mercado bueno',
                value: QaFormat.money(required[PlanScenario.optimistic]!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _growth(SavingsPlan plan) {
    final monthly = _monthly ?? plan.monthlyUsed;
    final curve = plan.curve(monthly: monthly);
    final end = curve.last;
    final base = end.base;
    final growth = math.max(0.0, base - end.contributed);
    final reaches = base >= _inputs.targetAmount - 0.5;
    final max = _sliderMax(plan);
    final step = _niceStep(max / 40);
    // Las dos cifras de la leyenda con el mismo formato ("$204K" junto a
    // "$97,405" se lee mal).
    final compact = end.contributed >= 100000 || growth >= 100000;
    String legend(double v) =>
        compact ? QaFormat.moneyCompact(v) : QaFormat.money(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(QaFormat.money(base), style: QaText.displaySm),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'en ${widget.data.targetDate.year}',
                style: QaText.label,
              ),
            ),
            QaTag(
              reaches
                  ? 'Llegás'
                  : 'Faltan ${QaFormat.money(_inputs.targetAmount - base)}',
              color: reaches ? QaColors.profit : QaColors.loss,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Entre ${QaFormat.money(end.values[PlanScenario.pessimistic]!)} y '
          '${QaFormat.money(end.values[PlanScenario.optimistic]!)} según '
          'cómo venga el mercado',
          style: QaText.caption,
        ),
        const SizedBox(height: QaSpace.gap),
        QaSavingsPlanChart(
          points: curve,
          targetAmount: _inputs.targetAmount,
          startLabel: 'Hoy',
          endLabel: '${widget.data.targetDate.year}',
          active: widget.active,
          onFinished: widget.onFinished,
        ),
        const SizedBox(height: QaSpace.gap),
        Row(
          children: [
            Expanded(
              child: _Legend(
                color: QaColors.textSecondary.withValues(alpha: 0.5),
                label: 'Lo que ponés',
                value: legend(end.contributed),
              ),
            ),
            Expanded(
              child: _Legend(
                color: QaColors.accentBlue,
                label: 'Intereses',
                value: legend(growth),
              ),
            ),
          ],
        ),
        const SizedBox(height: QaSpace.gap),
        QaInset(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Probá otro aporte', style: QaText.label),
                  ),
                  Text('${QaFormat.money(monthly)}/mes', style: QaText.value),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: QaColors.accentBlue,
                  inactiveTrackColor: QaPalette.track,
                  thumbColor: QaColors.accentBlue,
                  overlayColor: QaPalette.accentTint,
                  trackHeight: 3,
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  value: monthly.clamp(0, max).toDouble(),
                  max: max,
                  divisions: math.max(1, (max / step).round()),
                  semanticFormatterCallback:
                      (v) => '${QaFormat.money(v)} por mes',
                  onChanged: (v) => setState(() => _monthly = v),
                ),
              ),
              if (_monthly != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _monthly = null),
                    child: Text(
                      'Volver al plan',
                      style: QaText.label.copyWith(color: QaColors.accentBlue),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _allocation(SavingsPlan plan) {
    final entries = plan.allocation.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaSegmentedBar(
          segments: [
            for (var i = 0; i < entries.length; i++)
              QaSegment(value: entries[i].value, color: QaPalette.series(i)),
          ],
        ),
        const SizedBox(height: QaSpace.gap),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: QaPalette.series(i),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(entries[i].key.label, style: QaText.body)),
              Text('${(entries[i].value * 100).round()}%', style: QaText.value),
            ],
          ),
        ],
        const SizedBox(height: QaSpace.gap),
        Text(_riskNote(), style: QaText.caption),
      ],
    );
  }

  Widget _retirement(RetirementPhase phase) {
    final desired = widget.data.desiredMonthlyIncome;
    final years = phase.yearsLasting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              QaFormat.money(desired ?? phase.monthlyIncome),
              style: QaText.displaySm,
            ),
            const SizedBox(width: 4),
            Text('/ mes', style: QaText.label),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'de ingreso, retirando el 4% del capital por año',
          style: QaText.label,
        ),
        const SizedBox(height: 4),
        Text(
          years == null
              ? 'Con una cartera conservadora, el capital no se agotaría.'
              : 'Con una cartera conservadora te alcanzaría para unos '
                  '${QaFormat.plural(years, 'año', 'años')}.',
          style: QaText.caption,
        ),
      ],
    );
  }

  Widget _whatIf(SavingsPlan plan) {
    final retirement = _inputs.isRetirement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < plan.sensitivities.length; i++) ...[
          if (i > 0) const SizedBox(height: QaSpace.rowGap),
          Row(
            children: [
              Expanded(
                child: Text(
                  _whatIfLabel(plan.sensitivities[i], retirement),
                  style: QaText.body,
                ),
              ),
              Text(
                '${QaFormat.money(plan.sensitivities[i].requiredMonthly)}/mes',
                style: QaText.value,
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Textos
  // ---------------------------------------------------------------------

  String _whatIfLabel(PlanSensitivity s, bool retirement) {
    final years = (s.monthsDelta.abs() / 12).round();
    final sooner = s.monthsDelta < 0;
    if (retirement) {
      return sooner
          ? 'Te jubilás $years años antes'
          : 'Te jubilás $years años después';
    }
    return sooner ? 'Lo adelantás $years años' : 'Lo postergás $years años';
  }

  String _riskNote() {
    final name = _riskName(_inputs.risk).toLowerCase();
    if (widget.data.shortHorizon) {
      return 'Con menos de 3 años, las acciones pueden caer y no recuperarse '
          'a tiempo: por eso el plan va conservador.';
    }
    return switch (widget.data.riskSource) {
      GoalProjectionBuilder.riskStated => 'Cartera $name, como pediste.',
      GoalProjectionBuilder.riskProfile =>
        'Cartera $name, según tu perfil de inversor.',
      _ =>
        'Cartera $name por defecto: completá tu perfil de inversor para '
            'ajustarla a vos.',
    };
  }

  String _assumptions(SavingsPlan plan) {
    final r = plan.returns;
    final capital =
        widget.data.capitalStated
            ? 'Partís de ${QaFormat.money(_inputs.currentAmount)}.'
            : _inputs.currentAmount > 0
            ? 'Partís del valor de tu portfolio '
                '(${QaFormat.money(_inputs.currentAmount)}).'
            : 'Partís de cero.';
    return '$capital Rendimiento real (después de inflación) de '
        '${_pct(r[PlanScenario.pessimistic]!)}, '
        '${_pct(r[PlanScenario.base]!)} y '
        '${_pct(r[PlanScenario.optimistic]!)} anual según el escenario; '
        'aportes que suben con la inflación. Con inflación del '
        '${_pct(PlanAssumptions.inflation)}, la meta equivale a '
        '${QaFormat.money(plan.nominalTarget)} de ${widget.data.targetDate.year}. '
        'Es una simulación, no una garantía.';
  }

  List<QaFollowUp> _followUps() => [
    for (final risk in RiskTolerance.values)
      if (risk != _inputs.risk && !widget.data.shortHorizon)
        QaFollowUp(
          _riskName(risk),
          'Rehacé el plan con una cartera ${_riskName(risk).toLowerCase()}',
          icon: Icons.tune_rounded,
        ),
    const QaFollowUp(
      'Qué ETFs usar',
      '¿Qué ETFs podría usar para esta cartera?',
      icon: Icons.pie_chart_outline_rounded,
    ),
    const QaFollowUp(
      'Guardar meta',
      'Guardá esta meta',
      icon: Icons.bookmark_border_rounded,
    ),
  ];

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Hasta el doble de lo necesario en un mercado flojo: suficiente para
  /// ver qué pasa aportando de más sin que el slider sea inmanejable.
  static double _sliderMax(SavingsPlan plan) {
    final reference = [
      plan.requiredMonthly[PlanScenario.pessimistic]! * 1.5,
      plan.monthlyUsed * 2,
      100.0,
    ].reduce(math.max);
    final step = _niceStep(reference / 40);
    return (reference / step).ceil() * step;
  }

  static double _niceStep(double raw) {
    for (final s in const [5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0]) {
      if (raw <= s) return s;
    }
    return 1000;
  }

  static String _riskName(RiskTolerance risk) => switch (risk) {
    RiskTolerance.conservative => 'Conservadora',
    RiskTolerance.moderate => 'Moderada',
    RiskTolerance.aggressive => 'Agresiva',
  };

  static String _pct(double v) =>
      '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

  /// "20 años", "3 años y 4 meses", "7 meses".
  static String _horizon(int months) {
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return QaFormat.plural(rest, 'mes', 'meses');
    final y = QaFormat.plural(years, 'año', 'años');
    if (rest == 0) return y;
    return '$y y ${QaFormat.plural(rest, 'mes', 'meses')}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label ', style: QaText.label),
                TextSpan(text: value, style: QaText.valueSm),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

extension on String {
  String capitalized() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
