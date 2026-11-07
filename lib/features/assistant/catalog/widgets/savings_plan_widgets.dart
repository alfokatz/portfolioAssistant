import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_goal_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/savings_plan_edit_sheet.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_savings_plan_chart.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/view/goal_icon.dart';
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
                      planId: id,
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
    this.draft,
    this.result = const {},
  });

  /// El resultado de la tool del que sale (para recalcularlo si el usuario
  /// lo edita).
  final Map<String, Object?> result;

  /// El usuario cambió el plan en la card.
  bool get edited => result['edited_by_user'] == true;

  /// La meta con este plan, para "Guardar en Metas".
  final GoalDraft? draft;

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
      for (final i in p.instruments) i.monthly,
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
      draft: GoalDraft.fromToolResult(result),
      result: result,
    );
  }
}

enum _Block { savings, instruments, income, growth, progress, allocation, whatIf }

class QaSavingsPlanCard extends StatefulWidget {
  const QaSavingsPlanCard({
    super.key,
    required this.data,
    this.planId,
    this.focus,
    this.active = true,
    this.onFinished,
  });

  /// El plan que calculó Porty (las ediciones del usuario parten de acá).
  final SavingsPlanCardData data;

  /// Su `plan_id`: con él la card guarda y recupera lo que editó el usuario.
  final String? planId;

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

  /// Lo que editó el usuario (ver [QaGoalScope.editedPlan]); `null` = el
  /// plan de Porty.
  SavingsPlanCardData? _edit;
  bool _editLoaded = false;

  SavingsPlanCardData get _data => _edit ?? widget.data;
  SavingsPlan get _plan => _data.plan;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_editLoaded) return;
    _editLoaded = true;
    final id = widget.planId;
    final edited =
        id == null ? null : QaGoalScope.maybeOf(context)?.editedPlan?.call(id);
    if (edited != null) _edit = SavingsPlanCardData.fromToolResult(edited);
  }

  bool get _canEdit =>
      widget.planId != null &&
      QaGoalScope.maybeOf(context)?.onPlanEdited != null;

  Future<void> _editPlan() async {
    final current = _data;
    final change = await SavingsPlanEditSheet.show(
      context,
      label: current.label,
      inputs: current.plan.inputs,
      targetDate: current.targetDate,
    );
    if (change == null || !mounted) return;
    final original = widget.data.plan.inputs;
    final edited = GoalProjectionBuilder.edit(
      widget.data.result,
      label: change.label,
      targetAmount: change.targetAmount,
      targetDate: change.targetDate,
      currentAmount:
          change.currentAmount != original.currentAmount
              ? change.currentAmount
              : null,
      risk: change.risk != original.risk ? change.risk : null,
    );
    final data = edited == null ? null : SavingsPlanCardData.fromToolResult(edited);
    if (data == null) return;
    QaGoalScope.maybeOf(context)?.onPlanEdited?.call(widget.planId!, edited);
    setState(() {
      _edit = data;
      _monthly = null;
    });
  }

  void _undoEdit() {
    QaGoalScope.maybeOf(context)?.onPlanEdited?.call(widget.planId!, null);
    setState(() {
      _edit = null;
      _monthly = null;
    });
  }
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
        _Block.instruments,
        _Block.growth,
        _Block.allocation,
        if (hasIncome) _Block.income,
        if (hasWhatIf) _Block.whatIf,
      ])
        if (!shown.contains(b)) b,
    ];
    final top = switch (_focus) {
      SavingsPlanFocus.income => [_Block.income, _Block.savings],
      // "¿Cuánto ahorro?" se contesta con el monto Y en qué ponerlo.
      SavingsPlanFocus.savings => [_Block.savings, _Block.instruments],
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
    final data = _data;
    final retirementLike =
        _inputs.isRetirement || _inputs.desiredMonthlyIncome != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaCardTitle(
          title: data.label.isEmpty ? 'qa_sp_your_plan'.tr() : data.label,
          subtitle:
              'qa_sp_subtitle'.tr(
                namedArgs: {
                  'amount': QaFormat.money(_inputs.targetAmount),
                  'horizon': _horizon(_inputs.months),
                },
              ),
          // El de lo que es (un viaje, un auto…), igual que en Metas.
          icon: GoalIcon.of(
            data.label,
            retirementLike ? GoalType.retirement : GoalType.other,
          ),
          trailing: QaTag(
            _inputs.shortTerm
                ? 'qa_sp_short_term'.tr()
                : _riskName(_inputs.risk),
            color: QaColors.onChip,
          ),
        ),
        if (data.edited) _editedNote(),
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
        if (_canEdit)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: _editPlan,
              icon: Icon(
                Icons.tune_rounded,
                size: 18,
                color: QaColors.accentBlue,
              ),
              label: Text(
                'qa_sp_edit'.tr(),
                style: QaText.label.copyWith(
                  color: QaColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: QaColors.border),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        // Se guarda el aporte que el usuario eligió en el slider, si lo movió.
        if (data.draft != null)
          QaSaveGoalButton(
            draft:
                _monthly == null
                    ? data.draft!
                    : data.draft!.withMonthlyContribution(_monthly!),
          ),
        QaFollowUpBar(items: _followUps(), limit: 4),
      ],
    );
  }

  /// "Editaste este plan · Deshacer cambios".
  Widget _editedNote() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Icon(Icons.edit_note_rounded, size: 18, color: QaColors.accentBlue),
        const SizedBox(width: 6),
        Expanded(child: Text('qa_sp_edited_note'.tr(), style: QaText.caption)),
        if (_canEdit)
          TextButton(
            onPressed: _undoEdit,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              'qa_sp_undo_edit'.tr(),
              style: QaText.caption.copyWith(
                color: QaColors.accentBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _section(_Block block, {bool first = false}) {
    final (title, child) = switch (block) {
      _Block.savings => (
        null,
        _savings(full: _focus == SavingsPlanFocus.savings),
      ),
      _Block.income => ('qa_sp_block_income'.tr(), _incomeBlock(_income!)),
      _Block.growth => ('qa_sp_block_growth'.tr(), _growth(_plan)),
      _Block.progress => (null, _progress()),
      _Block.instruments => (
        'qa_sp_block_instruments'.tr(),
        _instruments(_plan),
      ),
      _Block.allocation => ('qa_sp_block_allocation'.tr(), _allocation(_plan)),
      _Block.whatIf => ('qa_sp_block_what_if'.tr(), _whatIf(_plan)),
    };
    return QaSection(
      first: first,
      title: title,
      trailing:
          block == _Block.allocation
              ? Text(
                'qa_sp_annual_real'.tr(
                  namedArgs: {'pct': _pct(_plan.returns[PlanScenario.base]!)},
                ),
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
            'qa_sp_your_goal'.tr(),
            trailing: QaTag(
              'qa_sp_reached'.tr(),
              color: QaColors.profit,
              icon: Icons.check_rounded,
            ),
          ),
          const SizedBox(height: 8),
          Text(QaFormat.money(_inputs.currentAmount), style: QaText.display),
          const SizedBox(height: 2),
          Text(
            'qa_sp_reached_note'.tr(),
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
            ? QaTag(
              'qa_sp_tag_on_track'.tr(),
              color: QaColors.profit,
              icon: Icons.check_rounded,
            )
            : QaTag(
              'qa_sp_tag_behind'.tr(),
              color: QaColors.loss,
              icon: Icons.trending_down_rounded,
            );
    final subtitle =
        [
          if (stated != null)
            'qa_sp_you_contribute'.tr(
              namedArgs: {'amount': QaFormat.money(stated)},
            ),
          if (plan.requiredMonthlyNoReturn > required[PlanScenario.base]! + 1)
            'qa_sp_without_investing'.tr(
              namedArgs: {'amount': QaFormat.money(plan.requiredMonthlyNoReturn)},
            ),
        ].join(' · ').capitalized();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSectionLabel(
          _focus == SavingsPlanFocus.income
              ? 'qa_sp_to_save_it'.tr()
              : 'qa_sp_suggested_monthly'.tr(),
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
            Text('qa_sp_per_month'.tr(), style: QaText.label),
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
                  label: 'qa_sp_weak_market'.tr(),
                  value: QaFormat.money(required[PlanScenario.pessimistic]!),
                ),
                QaStat(
                  label: 'qa_sp_expected'.tr(),
                  value: QaFormat.money(required[PlanScenario.base]!),
                ),
                QaStat(
                  label: 'qa_sp_good_market'.tr(),
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
        years == null
            ? 'qa_sp_never_runs_out'.tr()
            : 'qa_sp_runs_out_in'.tr(namedArgs: {'years': '$years'});
    // Con ingreso pedido, cada camino dice cuánto capital necesita; sin
    // él, cuánto ingreso da la meta.
    final dividends = _IncomeOption(
      title: 'qa_sp_from_dividends'.tr(),
      value:
          desired != null
              ? QaFormat.money(income.dividendsCapital)
              : 'qa_per_month'.tr(
                namedArgs: {'amount': QaFormat.money(income.dividendsMonthly)},
              ),
      note: 'qa_sp_dont_touch_capital'.tr(),
      selected: desired != null && income.strategy == IncomeStrategy.dividends,
    );
    final withdrawal = _IncomeOption(
      title: 'qa_sp_withdraw_4'.tr(),
      value:
          desired != null
              ? QaFormat.money(income.withdrawalCapital)
              : 'qa_per_month'.tr(
                namedArgs: {'amount': QaFormat.money(income.withdrawalMonthly)},
              ),
      note: withdrawalNote,
      selected: desired != null && income.strategy == IncomeStrategy.withdrawal,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          desired != null
              ? 'qa_sp_to_collect_need'.tr(
                namedArgs: {'amount': QaFormat.money(desired)},
              )
              : 'qa_sp_could_collect'.tr(
                namedArgs: {'amount': QaFormat.money(_inputs.targetAmount)},
              ),
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
          'qa_sp_income_explain'.tr(
            namedArgs: {'pct': _pct(_inputs.effectiveDividendYield)},
          ),
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
              QaSectionLabel('qa_sp_today_you_have'.tr()),
              const SizedBox(height: 6),
              Text(QaFormat.money(current), style: QaText.display),
              const SizedBox(height: 2),
              Text(
                'qa_sp_you_are_missing'.tr(
                  namedArgs: {
                    'amount': QaFormat.money(math.max(0, target - current)),
                    'horizon': _horizon(_inputs.months),
                  },
                ),
                style: QaText.label,
              ),
            ],
          ),
        ),
        const SizedBox(width: QaSpace.gap),
        Semantics(
          label: 'qa_sp_progress_semantics'.tr(namedArgs: {'pct': pctLabel}),
          child: QaRing(
            value: progress,
            size: 76,
            stroke: 7,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pctLabel, style: QaText.value),
                Text(
                  'qa_sp_achieved'.tr(),
                  style: QaText.caption.copyWith(fontSize: 10),
                ),
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
                'qa_sp_in_year'.tr(
                  namedArgs: {'year': '${_data.targetDate.year}'},
                ),
                style: QaText.label,
              ),
            ),
            QaTag(
              reaches
                  ? 'qa_sp_tag_on_track'.tr()
                  : 'qa_sp_missing_amount'.tr(
                    namedArgs: {
                      'amount': QaFormat.money(_inputs.targetAmount - base),
                    },
                  ),
              color: reaches ? QaColors.profit : QaColors.loss,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'qa_sp_between'.tr(
            namedArgs: {
              'low': QaFormat.money(end.values[PlanScenario.pessimistic]!),
              'high': QaFormat.money(end.values[PlanScenario.optimistic]!),
            },
          ),
          style: QaText.caption,
        ),
        const SizedBox(height: QaSpace.gap),
        QaSavingsPlanChart(
          points: curve,
          targetAmount: _inputs.targetAmount,
          startLabel: 'qa_sp_chart_today'.tr(),
          endLabel: '${_data.targetDate.year}',
          active: widget.active,
          onFinished: _reportFinished,
        ),
        const SizedBox(height: QaSpace.gap),
        Row(
          children: [
            Expanded(
              child: _Legend(
                color: QaColors.textSecondary.withValues(alpha: 0.5),
                label: 'qa_sp_you_put_in'.tr(),
                value: legend(end.contributed),
              ),
            ),
            Expanded(
              child: _Legend(
                color: QaColors.accentBlue,
                label: 'qa_sp_interest'.tr(),
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
                    child: Text('qa_sp_try_other'.tr(), style: QaText.label),
                  ),
                  Text(
                    'qa_per_month'.tr(
                      namedArgs: {'amount': QaFormat.money(monthly)},
                    ),
                    style: QaText.value,
                  ),
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
                      (v) => 'qa_sp_slider_semantics'.tr(
                        namedArgs: {'amount': QaFormat.money(v)},
                      ),
                  onChanged: (v) => setState(() => _monthly = v),
                ),
              ),
              if (_monthly != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _monthly = null),
                    child: Text(
                      'qa_sp_back_to_plan'.tr(),
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

  /// Qué comprar cada mes: un ETF por clase de activo de la cartera, con su
  /// parte del aporte (el del slider, si lo movió).
  Widget _instruments(SavingsPlan plan) {
    final monthly = _monthly ?? plan.monthlyUsed;
    final items = plan.instruments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: QaSpace.rowGap),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].instrument.ticker, style: QaText.value),
                    Text(
                      items[i].instrument.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QaText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'qa_per_month'.tr(
                      namedArgs: {
                        'amount': QaFormat.money(monthly * items[i].weight),
                      },
                    ),
                    style: QaText.value,
                  ),
                  Text(
                    '${(items[i].weight * 100).round()}% · '
                    '${items[i].instrument.assetClass.label}',
                    style: QaText.caption,
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: QaSpace.gap),
        Text(
          'qa_sp_etf_examples'.tr(),
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
                'qa_per_month'.tr(
                  namedArgs: {
                    'amount': QaFormat.money(plan.sensitivities[i].requiredMonthly),
                  },
                ),
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
          ? 'qa_sp_retire_sooner'.tr(namedArgs: {'years': '$years'})
          : 'qa_sp_retire_later'.tr(namedArgs: {'years': '$years'});
    }
    return sooner
        ? 'qa_sp_goal_sooner'.tr(namedArgs: {'years': '$years'})
        : 'qa_sp_goal_later'.tr(namedArgs: {'years': '$years'});
  }

  String _riskNote() {
    final name = _riskName(_inputs.risk).toLowerCase();
    if (_inputs.shortTerm) {
      return 'qa_sp_risk_short_term'.tr();
    }
    if (_data.shortHorizon) {
      return 'qa_sp_risk_short_horizon'.tr();
    }
    return switch (_data.riskSource) {
      GoalProjectionBuilder.riskStated => 'qa_sp_risk_stated'.tr(
        namedArgs: {'name': name},
      ),
      GoalProjectionBuilder.riskProfile => 'qa_sp_risk_profile'.tr(
        namedArgs: {'name': name},
      ),
      _ => 'qa_sp_risk_default'.tr(namedArgs: {'name': name}),
    };
  }

  String _assumptions(SavingsPlan plan) {
    final r = plan.returns;
    final capital =
        _data.capitalStated
            ? 'qa_sp_start_stated'.tr(
              namedArgs: {'amount': QaFormat.money(_inputs.currentAmount)},
            )
            : _inputs.currentAmount > 0
            ? 'qa_sp_start_portfolio'.tr(
              namedArgs: {'amount': QaFormat.money(_inputs.currentAmount)},
            )
            : 'qa_sp_start_zero'.tr();
    return 'qa_sp_assumptions'.tr(
      namedArgs: {
        'capital': capital,
        'low': _pct(r[PlanScenario.pessimistic]!),
        'base': _pct(r[PlanScenario.base]!),
        'high': _pct(r[PlanScenario.optimistic]!),
        'inflation': _pct(PlanAssumptions.inflation),
        'nominal': QaFormat.money(plan.nominalTarget),
        'year': '${_data.targetDate.year}',
      },
    );
  }

  List<QaFollowUp> _followUps() {
    final income = _income;
    final desired = income?.desiredMonthly != null;
    return [
      QaFollowUp(
        'qa_fu_build_buy'.tr(),
        'qa_fu_build_buy_q'.tr(),
        icon: Icons.shopping_basket_outlined,
      ),
      if (desired)
        income!.strategy == IncomeStrategy.dividends
            ? QaFollowUp(
              'qa_fu_use_withdraw4'.tr(),
              'qa_fu_use_withdraw4_q'.tr(),
              icon: Icons.swap_horiz_rounded,
            )
            : QaFollowUp(
              'qa_fu_use_dividends'.tr(),
              'qa_fu_use_dividends_q'.tr(),
              icon: Icons.swap_horiz_rounded,
            ),
      income != null
          ? QaFollowUp(
            'qa_fu_dividend_etfs'.tr(),
            'qa_fu_dividend_etfs_q'.tr(),
            icon: Icons.pie_chart_outline_rounded,
          )
          : QaFollowUp(
            'qa_fu_which_etfs'.tr(),
            'qa_fu_which_etfs_q'.tr(),
            icon: Icons.pie_chart_outline_rounded,
          ),
      for (final risk in RiskTolerance.values)
        if (risk != _inputs.risk &&
            !_data.shortHorizon &&
            !_inputs.shortTerm)
          QaFollowUp(
            _riskName(risk),
            'qa_fu_redo_risk_q'.tr(
              namedArgs: {'risk': _riskName(risk).toLowerCase()},
            ),
            icon: Icons.tune_rounded,
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
    RiskTolerance.conservative => 'qa_risk_conservative'.tr(),
    RiskTolerance.moderate => 'qa_risk_moderate'.tr(),
    RiskTolerance.aggressive => 'qa_risk_aggressive'.tr(),
  };

  static String _pct(double v) => '${QaFormat.decimal(v * 100)}%';

  /// "20 años", "3 años y 4 meses", "7 meses".
  static String _horizon(int months) {
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return QaFormat.units(rest, 'qa_unit_months');
    final y = QaFormat.units(years, 'qa_unit_years');
    if (rest == 0) return y;
    return 'qa_horizon_years_months'.tr(
      namedArgs: {'years': y, 'months': QaFormat.units(rest, 'qa_unit_months')},
    );
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
              'qa_sp_your_plan'.tr(),
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
                expanded ? 'qa_see_less'.tr() : 'qa_sp_see_full'.tr(),
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
