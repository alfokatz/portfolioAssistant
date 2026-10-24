import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_shares.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_actions.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_ask_sheet.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';

/// Una meta: cuánto lleva y si va en camino (el análisis de Porty), el plan
/// que armó Porty (ahorro mensual, cartera y compra mensual) y qué cuenta
/// para la meta: sus inversiones asignadas (se suman solas, con el valor de
/// hoy) y lo que tiene fuera de la app. El usuario nunca carga aportes.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  Future<void> _editOutside(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _OutsideSavingsSheet(goalId: goalId, current: current),
    );
    if (saved == true) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'goal_outside_saved'.tr());
    }
  }

  Future<void> _editLinks(BuildContext context, UserGoal goal) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        // Que no tape toda la pantalla: la manija y el fondo quedan a la
        // vista (antes, con muchas inversiones, llegaba hasta arriba).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        builder: (_) => _LinkHoldingsSheet(goal: goal),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final goal = ref.watch(goalsProvider).byId(goalId);
    if (goal == null) {
      return Scaffold(appBar: AppBar());
    }
    final locale = Localizations.localeOf(context);
    final goals = ref.watch(goalsProvider).goals;
    // Las inversiones que comparte con otras metas, solo con su parte.
    final allHoldings = ref.watch(goalHoldingsProvider);
    final holdings = GoalShares.holdingsFor(goal, goals, allHoldings);
    final shares = goal.linkedTickers.any(
      (t) => GoalShares.othersCounting(goal, t, goals).isNotEmpty,
    );
    final progress = GoalProgress.of(goal, DateTime.now(), holdings: holdings);
    final date = DateFormat.yMMMM(
      locale.toLanguageTag(),
    ).format(goal.targetDate);

    return Scaffold(
      appBar: AppBar(
        actions: [
          PortyAskButton(
            screen: PortyScreenContext(
              PortyScreen.goalDetail,
              goalLabel: goal.label,
            ),
          ),
          IconButton(
            tooltip: 'goal_options'.tr(),
            icon: Icon(Icons.more_horiz_rounded, color: colors.textPrimary),
            onPressed:
                () => GoalActions.showMenu(
                  context,
                  ref,
                  goal,
                  onDeleted: () {
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
                ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp32,
        ),
        children: [
          Semantics(
            header: true,
            child: Text(
              goal.label,
              style: tt.displaySmall?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp4),
          Text(
            'goals_card_subtitle'.tr(
              namedArgs: {
                'amount': QaFormat.money(goal.targetAmount),
                'date': date,
              },
            ),
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp20),
          _ProgressCard(goal: goal, progress: progress),
          const SizedBox(height: AppDimens.sectionGap),
          _SectionTitle('goal_plan_title'.tr()),
          _PlanCard(
            goal: goal,
            onEdit: () => GoalActions.editPlan(context, ref, goal),
          ),
          const SizedBox(height: AppDimens.sectionGap),
          _SectionTitle('goal_counts_title'.tr()),
          _CountsCard(
            goal: goal,
            goals: goals,
            holdings: holdings,
            allHoldings: allHoldings,
            onEditOutside:
                () => _editOutside(context, ref, goal.externalSavings),
            onEditLinks: () => _editLinks(context, goal),
          ),
          const SizedBox(height: AppDimens.sp8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp4),
            child: Text(
              goal.linkedTickers.isEmpty
                  ? 'goal_counts_hint_empty'.tr()
                  : [
                    'goal_counts_hint'.tr(),
                    // Por qué le toca esa parte de una inversión compartida.
                    if (shares) 'goal_counts_shared_hint'.tr(),
                  ].join(' '),
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sectionGap),
          _AskPortyButton(goal: goal),
          const SizedBox(height: AppDimens.sp24),
        ],
      ),
    );
  }
}

/// Cómo se ve Porty según cómo viene la meta: sonrisa leve al empezar o al
/// día, sonrisa grande si va adelantada (o ya la tiene), preocupado si va
/// atrasada o venció.
PortyAvatarState goalMood(GoalProgressStatus status) => switch (status) {
  GoalProgressStatus.justStarted ||
  GoalProgressStatus.onTrack => PortyAvatarState.idle,
  GoalProgressStatus.ahead ||
  GoalProgressStatus.achieved => PortyAvatarState.answered,
  GoalProgressStatus.behind ||
  GoalProgressStatus.overdue => PortyAvatarState.concerned,
};

/// Cuánto lleva (monto, barra y porcentaje), tres datos rápidos y el
/// análisis de Porty con la cara que corresponde.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.goal, required this.progress});

  final UserGoal goal;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    final statusColor = GoalAnalysis.statusColor(progress.status, colors);
    final missing = (progress.target - progress.saved).clamp(
      0.0,
      double.infinity,
    );
    const tabular = [FontFeature.tabularFigures()];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Monto y "de X" juntos: con montos largos se achican en vez
              // de cortarse ("2.00…").
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        QaFormat.money(progress.saved),
                        style: tt.displaySmall?.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: colors.textPrimary,
                          fontFeatures: tabular,
                        ),
                      ),
                      const SizedBox(width: AppDimens.sp6),
                      Text(
                        'goal_of_target'.tr(
                          namedArgs: {
                            'target': QaFormat.money(goal.targetAmount),
                          },
                        ),
                        style: tt.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.sp8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${(progress.fraction * 100).round()}%',
                  style: tt.titleSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabular,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          GoalProgressBar(
            fraction: progress.fraction,
            color: statusColor,
            height: 10,
          ),
          const SizedBox(height: AppDimens.sp16),
          IntrinsicHeight(
            child: Row(
              children: [
                // Atrasada: lo que hace falta desde hoy, no lo del plan.
                _Stat(
                  label:
                      progress.status == GoalProgressStatus.behind
                          ? 'goal_stat_monthly_now'.tr()
                          : 'goal_stat_monthly'.tr(),
                  value: QaFormat.money(
                    progress.status == GoalProgressStatus.behind
                        ? progress.requiredMonthlyNow
                        : progress.plannedMonthly,
                  ),
                ),
                VerticalDivider(width: AppDimens.sp24, color: colors.border),
                _Stat(
                  label: 'goal_plan_months_left'.tr(),
                  value: 'goal_months'.plural(progress.monthsRemaining),
                ),
                VerticalDivider(width: AppDimens.sp24, color: colors.border),
                _Stat(
                  label: 'goal_stat_missing'.tr(),
                  value: QaFormat.money(missing),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          // El análisis de Porty, con la cara de cómo viene la meta.
          DecoratedBox(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppDimens.radiusMd + 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.sp12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: PortyAvatar(
                      size: 40,
                      state: goalMood(progress.status),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          GoalAnalysis.statusLabel(progress.status),
                          style: tt.labelLarge?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          GoalAnalysis.text(goal, progress, locale),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: tt.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una inversión del plan: qué comprar cada mes y cuánto.
typedef _PlanItem =
    ({
      String ticker,
      String? name,
      String assetClass,
      double weight,
      double monthly,
    });

/// El plan de Porty: cuánto invertir por mes, cómo se reparte (barra +
/// leyenda) y en qué, con el logo y el monto de cada inversión.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.goal, required this.onEdit});

  final UserGoal goal;
  final VoidCallback onEdit;

  List<_PlanItem> _items(SavingsPlan plan) {
    final buy = goal.snapshot.buyPlan;
    if (buy.isNotEmpty) {
      return [
        for (final e in buy)
          if (e.pct > 0 || e.monthlyAmount > 0)
            (
              ticker: e.ticker,
              name: e.name,
              assetClass: e.assetClassLabel,
              weight: e.pct / 100,
              monthly: e.monthlyAmount.toDouble(),
            ),
      ];
    }
    return [
      for (final i in plan.instruments)
        (
          ticker: i.instrument.ticker,
          name: i.instrument.name,
          assetClass: i.instrument.assetClass.label,
          weight: i.weight,
          monthly: plan.monthlyUsed * i.weight,
        ),
    ];
  }

  static String _riskName(RiskTolerance risk) => switch (risk) {
    RiskTolerance.conservative => 'goal_risk_conservative'.tr(),
    RiskTolerance.moderate => 'goal_risk_moderate'.tr(),
    RiskTolerance.aggressive => 'goal_risk_aggressive'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final plan = goal.snapshot.plan;
    final inputs = goal.snapshot.inputs;
    final allocation = [
      for (final e in plan.allocation.entries)
        if (e.value > 0) e,
    ];
    final items = _items(plan);
    bool counted(String ticker) =>
        goal.linkedTickers.contains(ticker.toUpperCase());
    // Cada inversión con el color de su parte de la cartera.
    Color colorOf(String assetClass, int fallback) {
      final i = allocation.indexWhere((e) => e.key.label == assetClass);
      return QaPalette.series(i < 0 ? allocation.length + fallback : i);
    }

    final subtitleStyle = tt.labelMedium?.copyWith(
      color: colors.textSecondary,
      fontWeight: FontWeight.w600,
    );
    const tabular = [FontFeature.tabularFigures()];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('goal_plan_invest_monthly'.tr(), style: subtitleStyle),
                    const SizedBox(height: AppDimens.sp4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          QaFormat.money(plan.monthlyUsed),
                          style: tt.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: colors.textPrimary,
                            fontFeatures: tabular,
                          ),
                        ),
                        const SizedBox(width: AppDimens.sp4),
                        Text(
                          'goal_per_month'.tr(),
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              QaTag(
                inputs.shortTerm
                    ? 'goal_plan_short_term'.tr()
                    : _riskName(inputs.risk),
                color: colors.onChip,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp20),
          Text('goal_plan_mix'.tr(), style: subtitleStyle),
          const SizedBox(height: AppDimens.sp8),
          QaSegmentedBar(
            segments: [
              for (var i = 0; i < allocation.length; i++)
                QaSegment(
                  value: allocation[i].value,
                  color: QaPalette.series(i),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          Wrap(
            spacing: AppDimens.sp16,
            runSpacing: AppDimens.sp6,
            children: [
              for (var i = 0; i < allocation.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: QaPalette.series(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp6),
                    Text(
                      allocation[i].key.label,
                      style: tt.bodySmall?.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(width: AppDimens.sp4),
                    Text(
                      '${(allocation[i].value * 100).round()}%',
                      style: tt.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (inputs.shortTerm) ...[
            const SizedBox(height: AppDimens.sp12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: AppDimens.iconSm,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppDimens.sp6),
                Expanded(
                  child: Text(
                    'goal_plan_short_term_note'.tr(),
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: AppDimens.sp16),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: AppDimens.sp16),
            Text('goal_plan_where'.tr(), style: subtitleStyle),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.sp12),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        QaTickerAvatar(ticker: items[i].ticker, size: 36),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colorOf(items[i].assetClass, i),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.surfaceCard,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].ticker,
                            style: tt.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Si el usuario la sacó de "Qué cuenta", el plan la
                          // sigue sugiriendo pero se dice que no suma.
                          if (!counted(items[i].ticker))
                            Text(
                              'goal_plan_not_counted'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          else if (items[i].name != null)
                            Text(
                              items[i].name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'goal_plan_buy_amount'.tr(
                            namedArgs: {
                              'amount': QaFormat.money(items[i].monthly),
                            },
                          ),
                          style: tt.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabular,
                          ),
                        ),
                        Text(
                          'goal_plan_share'.tr(
                            namedArgs: {
                              'pct': '${(items[i].weight * 100).round()}%',
                            },
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: AppDimens.sp16),
          Text(
            'goal_plan_note'.tr(
              namedArgs: {
                'return': QaFormat.pct(plan.returns[PlanScenario.base]! * 100),
              },
            ),
            style: tt.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(
              Icons.tune_rounded,
              size: AppDimens.iconSm + 2,
              color: colors.accentBlue,
            ),
            label: Text(
              'goal_edit_plan'.tr(),
              style: tt.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppDimens.touchTarget),
              side: BorderSide(color: colors.border),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Qué cuenta para la meta: cada inversión con su logo y lo que vale hoy
/// (las que tiene llevan al detalle de la acción), lo que tiene fuera de la
/// app y "Elegir qué cuenta".
class _CountsCard extends StatelessWidget {
  const _CountsCard({
    required this.goal,
    required this.goals,
    required this.holdings,
    required this.allHoldings,
    required this.onEditOutside,
    required this.onEditLinks,
  });

  final UserGoal goal;

  /// Todas las metas: para decir con cuáles comparte cada inversión.
  final List<UserGoal> goals;

  /// Ya repartidas: lo que le toca a esta meta de cada inversión.
  final Map<String, double> holdings;

  /// Sin repartir: lo que vale cada inversión entera.
  final Map<String, double> allHoldings;
  final VoidCallback onEditOutside;
  final VoidCallback onEditLinks;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final names = {
      for (final e in goal.snapshot.buyPlan)
        if (e.name != null) e.ticker.toUpperCase(): e.name!,
    };
    final valueStyle = tt.titleSmall?.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final divider = Divider(
      height: 1,
      indent: AppDimens.cardPadding,
      endIndent: AppDimens.cardPadding,
      color: colors.border,
    );

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final t in goal.linkedTickers.toList()..sort()) ...[
            _CountRow(
              leading: QaTickerAvatar(ticker: t, size: 36),
              title: t,
              subtitleMaxLines: 2,
              subtitle: switch (GoalShares.othersCounting(goal, t, goals)) {
                // Compartida: cuánto de lo que tiene le toca a esta meta y
                // con qué metas la comparte.
                final others when others.isNotEmpty =>
                  (allHoldings[t] ?? 0) > 0
                      ? 'goal_counts_shared'.tr(
                        namedArgs: {
                          'share': QaFormat.money(holdings[t] ?? 0),
                          'total': QaFormat.money(allHoldings[t] ?? 0),
                          'goals': others.map((g) => g.label).join(', '),
                        },
                      )
                      : 'goal_counts_shared_not_held'.tr(
                        namedArgs: {
                          'goals': others.map((g) => g.label).join(', '),
                        },
                      ),
                _ =>
                  (holdings[t] ?? 0) > 0
                      ? names[t]
                      : 'goal_counts_not_held'.tr(),
              },
              trailing: Text(
                QaFormat.money(holdings[t] ?? 0),
                style: valueStyle,
              ),
              trailingIcon:
                  (holdings[t] ?? 0) > 0 ? Icons.chevron_right_rounded : null,
              onTap:
                  (holdings[t] ?? 0) > 0
                      ? () => GotoPositionDetail(
                        ticker: t,
                      ).navigate(context: context)
                      : null,
            ),
            divider,
          ],
          _CountRow(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.chip,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_outlined,
                size: AppDimens.iconMd,
                color: colors.onChip,
              ),
            ),
            title: 'goal_outside_title'.tr(),
            subtitle: 'goal_outside_subtitle'.tr(),
            trailing: Text(
              QaFormat.money(goal.externalSavings),
              style: valueStyle,
            ),
            trailingIcon: Icons.edit_outlined,
            onTap: onEditOutside,
          ),
          divider,
          InkWell(
            onTap: onEditLinks,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.cardPadding,
                vertical: AppDimens.sp12,
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: colors.accentBlue),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Text(
                      'goal_counts_edit'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.accentBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.leading,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.subtitleMaxLines = 1,
    this.trailingIcon,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final int subtitleMaxLines;
  final Widget trailing;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.cardPadding,
        AppDimens.sp12,
        AppDimens.sp12,
        AppDimens.sp12,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          trailing,
          SizedBox(
            width: AppDimens.iconMd + AppDimens.sp8,
            child:
                trailingIcon == null
                    ? null
                    : Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        trailingIcon,
                        size:
                            trailingIcon == Icons.edit_outlined
                                ? AppDimens.iconSm + 2
                                : AppDimens.iconMd,
                        color: colors.textSecondary,
                      ),
                    ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// "Preguntarle a Porty", con Porty (no un ícono de chat).
class _AskPortyButton extends StatelessWidget {
  const _AskPortyButton({required this.goal});

  final UserGoal goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: colors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap:
            () => GotoAssistant(
              initialQuestion: 'goal_ask_porty_question'.tr(
                namedArgs: {'goal': goal.label},
              ),
              screen: PortyScreenContext(
                PortyScreen.goalDetail,
                goalLabel: goal.label,
              ),
            ).navigate(context: context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.cardPadding,
            vertical: AppDimens.sp12,
          ),
          child: Row(
            children: [
              const ExcludeSemantics(child: PortyAvatar(size: 40)),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'goal_ask_porty'.tr(),
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'goal_ask_porty_subtitle'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconMd,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(AppDimens.cardPadding),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    // Material (no Container con color): las filas tocables pintan su
    // ripple en el Material más cercano.
    return Material(
      color: colors.surfaceCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppDimens.sp4, bottom: AppDimens.sp8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.customColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );
}

/// "Ahorros fuera de la app": un solo monto total (banco, efectivo…).
class _OutsideSavingsSheet extends ConsumerStatefulWidget {
  const _OutsideSavingsSheet({required this.goalId, required this.current});

  final String goalId;
  final double current;

  @override
  ConsumerState<_OutsideSavingsSheet> createState() =>
      _OutsideSavingsSheetState();
}

class _OutsideSavingsSheetState extends ConsumerState<_OutsideSavingsSheet> {
  late final _amount = TextEditingController(
    text: widget.current > 0 ? widget.current.round().toString() : '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value {
    final text = _amount.text.trim();
    if (text.isEmpty) return 0;
    final v = double.tryParse(text.replaceAll(',', '.'));
    return v == null || v < 0 ? null : v;
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(goalsProvider.notifier)
          .setExternalSavings(widget.goalId, value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        MediaQuery.viewInsetsOf(context).bottom + AppDimens.sp24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'goal_outside_title'.tr(),
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            'goal_outside_body'.tr(),
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(prefixText: r'$ ', hintText: '0'),
          ),
          const SizedBox(height: AppDimens.sp16),
          PositionPrimaryButton(
            label: 'porty_memory_save'.tr(),
            loading: _saving,
            onPressed: _saving || _value == null ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// "Elegir qué cuenta": las inversiones de la cartera (y las del plan que
/// todavía no tiene). Una que ya cuenta para otra meta puede contar
/// también para esta: su valor se reparte (ver [GoalShares]).
class _LinkHoldingsSheet extends ConsumerStatefulWidget {
  const _LinkHoldingsSheet({required this.goal});

  final UserGoal goal;

  @override
  ConsumerState<_LinkHoldingsSheet> createState() => _LinkHoldingsSheetState();
}

class _LinkHoldingsSheetState extends ConsumerState<_LinkHoldingsSheet> {
  late final Set<String> _selected = {...widget.goal.linkedTickers};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(goalsProvider.notifier)
          .setLinkedTickers(widget.goal.id, _selected);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final holdings = ref.watch(goalHoldingsProvider);
    final goals = ref.watch(goalsProvider).goals;
    final tickers =
        {
            ...holdings.keys,
            for (final e in widget.goal.snapshot.buyPlan)
              e.ticker.toUpperCase(),
            ...widget.goal.linkedTickers,
          }.toList()
          ..sort();
    String? ownerOf(String t) =>
        goals
            .where((g) => g.id != widget.goal.id && g.linkedTickers.contains(t))
            .firstOrNull
            ?.label;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'goal_counts_edit'.tr(),
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'goal_link_body'.tr(),
              style: tt.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tickers)
                    CheckboxListTile(
                      value: _selected.contains(t),
                      onChanged:
                          (on) => setState(
                            () =>
                                on == true
                                    ? _selected.add(t)
                                    : _selected.remove(t),
                          ),
                      contentPadding: EdgeInsets.zero,
                      secondary: QaTickerAvatar(ticker: t, size: 36),
                      title: Text(
                        t,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                          (holdings[t] ?? 0) > 0
                              ? QaFormat.money(holdings[t]!)
                              : 'goal_counts_not_held'.tr(),
                          if (ownerOf(t) case final owner?)
                            'goal_link_also_in'.tr(namedArgs: {'goal': owner}),
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
            PositionPrimaryButton(
              label: 'porty_memory_save'.tr(),
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
