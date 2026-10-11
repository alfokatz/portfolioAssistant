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
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// Qué responde la card arriba de todo; el resto del plan queda en "Ver
/// plan completo". Lo elige el modelo según la pregunta.
enum SavingsPlanFocus {
  /// "Quiero cobrar 3000 por mes": cómo cobrarías y cuánto capital hace
  /// falta por cada camino.
  income('income'),

  /// "¿Cuánto tengo que ahorrar?": el ahorro mensual por escenario.
  savings('savings'),

  /// "¿Cómo va a crecer?" / "¿y si aporto 500?": la curva y el slider.
  growth('growth'),

  /// "¿Cómo va mi meta?": cuánto llevás.
  progress('progress');

  const SavingsPlanFocus(this.key);
  final String key;

  static SavingsPlanFocus? fromKey(Object? key) =>
      values.where((v) => v.key == key).firstOrNull;
}

/// La card del plan de ahorro (metas y jubilación).
///
/// El modelo solo pasa `planId` (y el foco): el plan sale del resultado de
/// `get_goal_projection` ([QaEvidenceScope]) y se recalcula acá con
/// [SavingsPlan.build] — así ningún número de la card lo escribe el modelo,
/// y el slider de aporte puede mover la curva sin otra consulta.
abstract final class SavingsPlanWidgets {
  static Widget qaSavingsPlan(CatalogItemContext ctx) {
    final json = ctx.data as JsonMap;
    final id = '${json['planId'] ?? ''}';
    final focus = SavingsPlanFocus.fromKey(json['focus']);
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
                      focus: focus,
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
  });

  final SavingsPlan plan;
  final String label;
  final DateTime targetDate;
  final String riskSource;
  final bool shortHorizon;
  final bool capitalStated;

  /// Todo número que la card muestra o que sale del cálculo: lo único que
  /// Porty puede citar en el texto que la acompaña. Con sus versiones en
  /// miles y millones ("900 mil", "1,03 millones").
  Iterable<double> get backingNumbers sync* {
    final p = plan;
    final income = p.income;
    final raw = <double>[
      p.inputs.targetAmount,
      p.inputs.currentAmount,
      if (p.inputs.monthlyContribution != null) p.inputs.monthlyContribution!,
      ...p.requiredMonthly.values,
      p.requiredMonthlyNoReturn,
      ...p.projected.values,
      p.contributed,
      p.growth,
      p.nominalTarget,
      for (final s in p.sensitivities) s.requiredMonthly,
      if (income != null) ...[
        if (income.desiredMonthly != null) income.desiredMonthly!,
        income.dividendsCapital,
        income.withdrawalCapital,
        income.dividendsMonthly,
        income.withdrawalMonthly,
        if (income.withdrawalYears != null) income.withdrawalYears!.toDouble(),
      ],
    ];
    for (final v in raw) {
      yield v;
      yield v / 1e3;
      yield v / 1e6;
    }
    // Porcentajes y plazos.
    for (final r in p.returns.values) {
      yield r * 100;
    }
    for (final w in p.allocation.values) {
      yield w * 100;
    }
    yield p.inputs.effectiveDividendYield * 100;
    yield PlanAssumptions.safeWithdrawalRate * 100;
    yield PlanAssumptions.inflation * 100;
    yield p.inputs.months.toDouble();
    yield p.inputs.months / 12;
    yield targetDate.year.toDouble();
  }

  /// Tools cuyo resultado trae un plan (la compra mensual trae el plan
  /// recalculado con el rendimiento real).
  static const toolNames = {
    GetGoalProjectionTool.toolName,
    GetMonthlyBuyPlanTool.toolName,
  };

  /// El plan [planId] entre [calls], o `null`.
  static SavingsPlanCardData? from(List<ToolCallRecord> calls, String planId) {
    if (planId.isEmpty) return null;
    for (final call in calls.reversed) {
      if (!SavingsPlanCardData.toolNames.contains(call.name)) continue;
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
    return SavingsPlanCardData(
      plan: SavingsPlan.build(inputs),
      label: '${goal['label'] ?? ''}'.trim(),
      targetDate: date,
      riskSource:
          '${result['risk_source'] ?? GoalProjectionBuilder.riskDefault}',
      shortHorizon: result['risk_adjusted_for_short_horizon'] == true,
      capitalStated: result['starting_capital_source'] == 'stated',
    );
  }
}

enum _Block { savings, income, growth, progress, allocation, whatIf }

class QaSavingsPlanCard extends StatefulWidget {
  const QaSavingsPlanCard({
    super.key,
    required this.data,
    this.focus,
    this.active = true,
    this.onFinished,
  });

  final SavingsPlanCardData data;

  /// `null` = ingreso si el usuario pidió uno; si no, ahorro.
  final SavingsPlanFocus? focus;
  final bool active;
  final VoidCallback? onFinished;

  @override
  State<QaSavingsPlanCard> createState() => _QaSavingsPlanCardState();
}

class _QaSavingsPlanCardState extends State<QaSavingsPlanCard> {
  /// Aporte elegido con el slider; `null` = el del plan.
  double? _monthly;
  bool _expanded = false;
  bool _finishReported = false;

  SavingsPlan get _plan => widget.data.plan;
  SavingsPlanInputs get _inputs => _plan.inputs;
  IncomePlan? get _income => _plan.income;

  SavingsPlanFocus get _focus {
    final focus =
        widget.focus ??
        (_inputs.desiredMonthlyIncome != null
            ? SavingsPlanFocus.income
            : SavingsPlanFocus.savings);
    // Sin fase de ingreso no hay "cómo cobrarías" que mostrar.
    if (focus == SavingsPlanFocus.income && _income == null) {
      return SavingsPlanFocus.savings;
    }
    return focus;
  }

  /// Lo que va arriba (responde la pregunta) y lo que queda en "Ver plan
  /// completo".
  (List<_Block>, List<_Block>) get _layout {
    final hasIncome = _income != null;
    final hasWhatIf = _plan.sensitivities.isNotEmpty;
    List<_Block> rest(Iterable<_Block> shown) => [
      for (final b in [
        _Block.growth,
        _Block.allocation,
        if (hasIncome) _Block.income,
        if (hasWhatIf) _Block.whatIf,
      ])
        if (!shown.contains(b)) b,
    ];
    final top = switch (_focus) {
      SavingsPlanFocus.income => [_Block.income, _Block.savings],
      SavingsPlanFocus.savings => [_Block.savings],
      SavingsPlanFocus.growth => [_Block.growth, _Block.savings],
      SavingsPlanFocus.progress => [_Block.progress, _Block.savings],
    };
    return (top, rest(top));
  }

  /// El chart es lo que cierra el reveal de la card; si quedó colapsado,
  /// la card avisa que terminó igual (si no, las siguientes no entran).
  void _reportFinished() {
    if (_finishReported) return;
    _finishReported = true;
    widget.onFinished?.call();
  }

  @override
  Widget build(BuildContext context) {
    final (top, rest) = _layout;
    if (widget.active && !top.contains(_Block.growth)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportFinished());
    }
    final data = widget.data;
    final retirementLike =
        _inputs.isRetirement || _inputs.desiredMonthlyIncome != null;

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
              retirementLike
                  ? Icons.beach_access_outlined
                  : Icons.flag_outlined,
          trailing: QaTag(
            _inputs.shortTerm ? 'Corto plazo' : _riskName(_inputs.risk),
            color: QaColors.accentBlue,
          ),
        ),
        for (var i = 0; i < top.length; i++) _section(top[i], first: i == 0),
        if (rest.isNotEmpty) ...[
          MotionAwareSize(
            duration: const Duration(milliseconds: 280),
            child:
                _expanded
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final b in rest) _section(b)],
                    )
                    : const SizedBox(width: double.infinity),
          ),
          SizedBox(height: _expanded ? QaSpace.gap : 4),
          _ExpandToggle(
            expanded: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ],
        QaSection(child: Text(_assumptions(_plan), style: QaText.caption)),
        QaFollowUpBar(items: _followUps(), limit: 4),
      ],
    );
  }

  Widget _section(_Block block, {bool first = false}) {
    final (title, child) = switch (block) {
      _Block.savings => (
        null,
        _savings(full: _focus == SavingsPlanFocus.savings),
      ),
      _Block.income => ('Cómo cobrarías', _incomeBlock(_income!)),
      _Block.growth => ('Cómo crece', _growth(_plan)),
      _Block.progress => (null, _progress()),
      _Block.allocation => ('Cartera sugerida', _allocation(_plan)),
      _Block.whatIf => ('¿Y si cambiás el plazo?', _whatIf(_plan)),
    };
    return QaSection(
      first: first,
      title: title,
      trailing:
          block == _Block.allocation
              ? Text(
                '≈${_pct(_plan.returns[PlanScenario.base]!)} anual real',
                style: QaText.caption,
              )
              : null,
      child: child,
    );
  }

  // ---------------------------------------------------------------------
  // Bloques
  // ---------------------------------------------------------------------

  Widget _savings({required bool full}) {
    final plan = _plan;
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
    final subtitle =
        [
          if (stated != null) 'Hoy aportás ${QaFormat.money(stated)}/mes',
          if (plan.requiredMonthlyNoReturn > required[PlanScenario.base]! + 1)
            'sin invertir serían '
                '${QaFormat.money(plan.requiredMonthlyNoReturn)}/mes',
        ].join(' · ').capitalized();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel(
          _focus == SavingsPlanFocus.income
              ? 'Para juntarlo, ahorrá'
              : 'Ahorro mensual sugerido',
          trailing: tag,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              QaFormat.money(required[PlanScenario.base]!),
              style: full ? QaText.display : QaText.displaySm,
            ),
            const SizedBox(width: 4),
            Text('/ mes', style: QaText.label),
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: QaText.label),
        ],
        if (full) ...[
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
      ],
    );
  }

  Widget _incomeBlock(IncomePlan income) {
    final desired = income.desiredMonthly;
    final years = income.withdrawalYears;
    final withdrawalNote =
        years == null ? 'No se agota' : 'Se consume en ~$years años';
    // Con ingreso pedido, cada camino dice cuánto capital necesita; sin
    // él, cuánto ingreso da la meta.
    final dividends = _IncomeOption(
      title: 'De dividendos',
      value:
          desired != null
              ? QaFormat.money(income.dividendsCapital)
              : '${QaFormat.money(income.dividendsMonthly)}/mes',
      note: 'No tocás el capital',
      selected: desired != null && income.strategy == IncomeStrategy.dividends,
    );
    final withdrawal = _IncomeOption(
      title: 'Retirando el 4%',
      value:
          desired != null
              ? QaFormat.money(income.withdrawalCapital)
              : '${QaFormat.money(income.withdrawalMonthly)}/mes',
      note: withdrawalNote,
      selected: desired != null && income.strategy == IncomeStrategy.withdrawal,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          desired != null
              ? 'Para cobrar ${QaFormat.money(desired)}/mes necesitás juntar:'
              : 'Con ${QaFormat.money(_inputs.targetAmount)} podrías cobrar:',
          style: QaText.body,
        ),
        const SizedBox(height: QaSpace.gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: dividends),
              const SizedBox(width: 8),
              Expanded(child: withdrawal),
            ],
          ),
        ),
        const SizedBox(height: QaSpace.gap),
        Text(
          'Dividendos: al jubilarte pasás el capital a acciones o ETFs que '
          'pagan dividendos (~${_pct(_inputs.effectiveDividendYield)} anual) '
          'y vivís de lo que pagan. Retiro del 4%: vendés de a poco una '
          'cartera conservadora; necesitás menos, pero se va gastando.',
          style: QaText.caption,
        ),
      ],
    );
  }

  Widget _progress() {
    final current = _inputs.currentAmount;
    final target = _inputs.targetAmount;
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final pct = progress * 100;
    final pctLabel = pct > 0 && pct < 1 ? '<1%' : '${pct.floor()}%';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const QaSectionLabel('Hoy tenés'),
              const SizedBox(height: 6),
              Text(QaFormat.money(current), style: QaText.display),
              const SizedBox(height: 2),
              Text(
                'Te faltan ${QaFormat.money(math.max(0, target - current))} '
                '· ${_horizon(_inputs.months)}',
                style: QaText.label,
              ),
            ],
          ),
        ),
        const SizedBox(width: QaSpace.gap),
        Semantics(
          label: 'Progreso $pctLabel',
          child: QaRing(
            value: progress,
            size: 76,
            stroke: 7,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pctLabel, style: QaText.value),
                Text('logrado', style: QaText.caption.copyWith(fontSize: 10)),
              ],
            ),
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
          onFinished: _reportFinished,
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
    if (_inputs.shortTerm) {
      return 'Es plata que vas a usar en menos de 3 años: el plan la deja en '
          'liquidez (cuentas remuneradas, money market, letras) y bonos '
          'cortos, sin acciones, para que no dependa de cómo esté el mercado '
          'cuando la necesites.';
    }
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
    return '$capital Montos en dólares de hoy. Rendimiento real (después de '
        'inflación) de ${_pct(r[PlanScenario.pessimistic]!)}, '
        '${_pct(r[PlanScenario.base]!)} y '
        '${_pct(r[PlanScenario.optimistic]!)} anual según el escenario; '
        'aportes que suben con la inflación. Con inflación del '
        '${_pct(PlanAssumptions.inflation)}, la meta equivale a '
        '${QaFormat.money(plan.nominalTarget)} de ${widget.data.targetDate.year}. '
        'Es una simulación, no una garantía.';
  }

  List<QaFollowUp> _followUps() {
    final income = _income;
    final desired = income?.desiredMonthly != null;
    return [
      const QaFollowUp(
        'Armar mi compra mensual',
        'Armá mi compra mensual para este plan',
        icon: Icons.shopping_basket_outlined,
      ),
      if (desired)
        income!.strategy == IncomeStrategy.dividends
            ? const QaFollowUp(
              'Usar retiro del 4%',
              'Rehacé el plan para cobrar retirando el 4% por año',
              icon: Icons.swap_horiz_rounded,
            )
            : const QaFollowUp(
              'Usar dividendos',
              'Rehacé el plan para vivir de dividendos',
              icon: Icons.swap_horiz_rounded,
            ),
      income != null
          ? const QaFollowUp(
            'ETFs de dividendos',
            '¿Qué ETFs de dividendos podría usar?',
            icon: Icons.pie_chart_outline_rounded,
          )
          : const QaFollowUp(
            'Qué ETFs usar',
            '¿Qué ETFs podría usar para esta cartera?',
            icon: Icons.pie_chart_outline_rounded,
          ),
      for (final risk in RiskTolerance.values)
        if (risk != _inputs.risk &&
            !widget.data.shortHorizon &&
            !_inputs.shortTerm)
          QaFollowUp(
            _riskName(risk),
            'Rehacé el plan con una cartera ${_riskName(risk).toLowerCase()}',
            icon: Icons.tune_rounded,
          ),
      const QaFollowUp(
        'Guardar meta',
        'Guardá esta meta',
        icon: Icons.bookmark_border_rounded,
      ),
    ];
  }

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

/// Uno de los dos caminos para cobrar el ingreso.
class _IncomeOption extends StatelessWidget {
  const _IncomeOption({
    required this.title,
    required this.value,
    required this.note,
    required this.selected,
  });

  final String title;
  final String value;
  final String note;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? QaPalette.accentTint : QaPalette.inset,
        borderRadius: BorderRadius.circular(QaSpace.insetRadius),
        border: Border.all(
          color: selected ? QaColors.accentBlue : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: QaText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: QaColors.accentBlue,
                ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: QaText.displaySm),
          ),
          const SizedBox(height: 2),
          Text(note, style: QaText.caption),
          if (selected) ...[
            const SizedBox(height: 4),
            Text(
              'Tu plan',
              style: QaText.caption.copyWith(color: QaColors.accentBlue),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(QaSpace.chipRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                expanded ? 'Ver menos' : 'Ver plan completo',
                style: QaText.label.copyWith(color: QaColors.accentBlue),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: QaColors.accentBlue,
              ),
            ],
          ),
        ),
      ),
    );
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
