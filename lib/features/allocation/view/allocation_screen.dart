import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/allocation/view/allocation_wizard_screen.dart';
import 'package:portfolio_assistant/features/allocation/view/widgets/allocation_widgets.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';

/// "Mi plan de cartera". Sin plan, Porty cuenta de qué se trata y abre el
/// armado de a pasos ([AllocationWizardScreen]); con plan, cómo viene la
/// cartera contra el plan, dónde poner el próximo aporte y los avisos.
/// Porty hace la cuenta del plan del usuario; no recomienda qué comprar.
class AllocationScreen extends ConsumerStatefulWidget {
  const AllocationScreen({super.key});

  @override
  ConsumerState<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends ConsumerState<AllocationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(allocationProvider.notifier).load();
    });
  }

  Future<void> _openWizard({
    AllocationPlan? initial,
    AllocationStep startAt = AllocationStep.pick,
  }) async {
    final saved = await AllocationWizardScreen.open(
      context,
      initial: initial,
      startAt: startAt,
    );
    if (saved && mounted) {
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'allocation_saved'.tr());
    }
  }

  void _seePlans() => SubscriptionPaywallSheet.show(
    context,
    ref,
    reason: PaywallReason.modeLocked,
  );

  @override
  Widget build(BuildContext context) {
    final tier = ref.watch(subscriptionProvider).tier;
    final allowed = SubscriptionPolicy.allows(tier, PlanFeature.allocationPlan);
    final state = ref.watch(allocationProvider);
    final values = ref.watch(goalHoldingsProvider);

    final Widget body;
    if (!allowed) {
      body = _Intro(locked: true, onStart: _seePlans);
    } else if (!state.loaded) {
      body = Center(child: PortyLoader(message: 'loader_one_moment'.tr()));
    } else if (state.saved.isEmpty && state.error != null) {
      body = PortyStatusMessage(
        title: 'allocation_error_load_title'.tr(),
        body: 'allocation_error_load_body'.tr(),
        actionLabel: 'allocation_retry'.tr(),
        onAction: () => ref.read(allocationProvider.notifier).load(),
      );
    } else if (state.saved.isEmpty) {
      body = _Intro(locked: false, onStart: () => _openWizard());
    } else {
      body = _Dashboard(
        plan: state.saved,
        values: values,
        onEdit: () => _openWizard(initial: state.saved),
        onEditAlerts:
            () => _openWizard(
              initial: state.saved,
              startAt: AllocationStep.alerts,
            ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('allocation_title'.tr())),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// Sin plan: Porty explica qué es y cómo se arma, en tres pasos. Si no es
/// Premium, lo mismo con el botón a los planes.
class _Intro extends StatelessWidget {
  const _Intro({required this.locked, required this.onStart});

  final bool locked;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final steps = [
      (
        Icons.checklist_rounded,
        'allocation_intro_step1_title'.tr(),
        'allocation_intro_step1_body'.tr(),
      ),
      (
        Icons.tune_rounded,
        'allocation_intro_step2_title'.tr(),
        'allocation_intro_step2_body'.tr(),
      ),
      (
        Icons.notifications_none_rounded,
        'allocation_intro_step3_title'.tr(),
        'allocation_intro_step3_body'.tr(),
      ),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp20,
              AppDimens.pageHorizontal,
              AppDimens.sp24,
            ),
            children: [
              PortySays(
                messageKey: 'intro',
                message: Text('allocation_intro_porty'.tr()),
                footnote: Text(
                  (locked ? 'allocation_locked_body' : 'allocation_intro_body')
                      .tr(),
                ),
              ),
              const SizedBox(height: AppDimens.sp24),
              AllocationCard(
                child: Column(
                  children: [
                    for (final (i, s) in steps.indexed) ...[
                      if (i > 0) const SizedBox(height: AppDimens.sp16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colors.chip,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              s.$1,
                              size: AppDimens.iconMd,
                              color: colors.onChip,
                            ),
                          ),
                          const SizedBox(width: AppDimens.sp12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.$2,
                                  style: tt.bodyMedium?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.$3,
                                  style: tt.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.sp16),
              Text(
                'allocation_disclaimer'.tr(),
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp16,
          ),
          child: PositionPrimaryButton(
            label: (locked ? 'allocation_see_plans' : 'allocation_start').tr(),
            onPressed: onStart,
          ),
        ),
      ],
    );
  }
}

/// Con plan: cómo viene la cartera, el próximo aporte y los avisos.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.plan,
    required this.values,
    required this.onEdit,
    required this.onEditAlerts,
  });

  final AllocationPlan plan;
  final Map<String, double> values;
  final VoidCallback onEdit;
  final VoidCallback onEditAlerts;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final rows = AllocationMath.rows(values: values, targets: plan.targets);
    final hasHoldings = values.values.any((v) => v > 0);
    final order = [
      for (final r in rows)
        if (r.targetPct > 0) r.ticker,
    ];
    Color colorOf(String t) {
      final i = order.indexOf(t);
      return i < 0
          ? colors.textSecondary.withValues(alpha: 0.35)
          : allocationColor(context, i);
    }

    final worst = rows.fold<AllocationRow?>(
      null,
      (w, r) => w == null || r.drift.abs() > w.drift.abs() ? r : w,
    );
    final offPlan =
        hasHoldings &&
        worst != null &&
        worst.drift.abs() >= plan.driftThreshold;

    // Cara de siempre: alejarse del plan no es una mala noticia (la cara
    // contenta o triste es solo para cómo le fue a la cartera en la semana).
    final (mood, message, footnote) =
        !hasHoldings
            ? (
              PortyAvatarState.idle,
              'allocation_status_no_holdings'.tr(),
              null,
            )
            : offPlan
            ? (
              PortyAvatarState.idle,
              (worst.targetPct == 0
                      ? 'allocation_status_off_outside'
                      : worst.drift > 0
                      ? 'allocation_status_off_over'
                      : 'allocation_status_off_under')
                  .tr(
                    namedArgs: {
                      'ticker': worst.ticker,
                      'current': allocationPct(worst.currentPct),
                      'target': allocationPct(worst.targetPct),
                    },
                  ),
              'allocation_status_off_note'.tr(),
            )
            : (
              PortyAvatarState.idle,
              'allocation_status_ok'.tr(),
              'allocation_status_ok_note'.tr(
                namedArgs: {'points': '${plan.driftThreshold.round()}'},
              ),
            );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp20,
        AppDimens.pageHorizontal,
        AppDimens.sp32,
      ),
      children: [
        PortySays(
          messageKey: message,
          mood: mood,
          message: Text(message),
          footnote: footnote == null ? null : Text(footnote),
        ),
        const SizedBox(height: AppDimens.sp20),

        // Plan contra hoy.
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle(
                'allocation_compare_title'.tr(),
                action: 'allocation_edit_plan'.tr(),
                onAction: onEdit,
              ),
              const SizedBox(height: AppDimens.sp8),
              _BarLabel('allocation_compare_plan'.tr()),
              PlanBar(
                slices: [
                  for (final t in order)
                    (ticker: t, pct: plan.targets[t] ?? 0, color: colorOf(t)),
                ],
              ),
              if (hasHoldings) ...[
                const SizedBox(height: AppDimens.sp12),
                _BarLabel('allocation_compare_today'.tr()),
                PlanBar(
                  slices: [
                    for (final r in rows)
                      (
                        ticker: r.ticker,
                        pct: r.currentPct,
                        color: colorOf(r.ticker),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppDimens.sp12),
              Divider(height: 1, color: colors.border),
              for (final r in rows)
                if (r.targetPct > 0 || r.currentPct > 0)
                  _CompareRow(
                    row: r,
                    color: colorOf(r.ticker),
                    threshold: plan.driftThreshold,
                    hasHoldings: hasHoldings,
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp12),

        // Próximo aporte.
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle('allocation_contribution_title'.tr()),
              const SizedBox(height: AppDimens.sp4),
              Text(
                'allocation_contribution_body'.tr(),
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimens.sp12),
              OutlinedButton.icon(
                onPressed:
                    () => ContributionSheet.show(
                      context,
                      values: values,
                      targets: plan.targets,
                      onAskPorty:
                          (amount) => GotoAssistant(
                            initialQuestion: 'allocation_ask_contribution'.tr(
                              namedArgs: {
                                'amount': AppNumberFormat.money(amount),
                              },
                            ),
                          ).navigate(context: context),
                    ),
                icon: const Icon(Icons.calculate_outlined),
                label: Text('allocation_contribution_cta'.tr()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppDimens.touchTarget),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp12),

        // Avisos.
        AllocationCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AllocationCardTitle(
                'allocation_review_alerts'.tr(),
                action: 'allocation_change'.tr(),
                onAction: onEditAlerts,
              ),
              const SizedBox(height: AppDimens.sp4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    plan.notify
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    size: AppDimens.iconMd,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Expanded(
                    child: Text(
                      allocationAlertSummary(plan),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp16),
        Center(
          child: TextButton.icon(
            onPressed:
                () => GotoAssistant(
                  initialQuestion: 'allocation_ask_plan'.tr(),
                ).navigate(context: context),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text('allocation_ask_porty'.tr()),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'allocation_disclaimer'.tr(),
          style: tt.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _BarLabel extends StatelessWidget {
  const _BarLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppDimens.sp6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.customColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Una fila de la comparación: plan, hoy y si está dentro del margen.
class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.row,
    required this.color,
    required this.threshold,
    required this.hasHoldings,
  });

  final AllocationRow row;
  final Color color;
  final double threshold;
  final bool hasHoldings;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final off = hasHoldings && row.drift.abs() >= threshold;
    final points = row.drift.abs().round();
    final status =
        !hasHoldings
            ? null
            : row.targetPct == 0
            ? 'allocation_row_outside'.tr()
            : !off
            ? 'allocation_row_ok'.tr()
            : (row.drift > 0 ? 'allocation_row_over' : 'allocation_row_under')
                .tr(namedArgs: {'points': '$points'});
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp12),
      child: Row(
        children: [
          PlanDot(color),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.ticker,
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  hasHoldings
                      ? 'allocation_row_detail'.tr(
                        namedArgs: {
                          'target': allocationPct(row.targetPct),
                          'current': allocationPct(row.currentPct),
                        },
                      )
                      : 'allocation_row_detail_plan'.tr(
                        namedArgs: {'target': allocationPct(row.targetPct)},
                      ),
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: AppDimens.sp8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.sp8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: off ? colors.chip : colors.profitContainer,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                ),
                child: Text(
                  status,
                  style: tt.labelSmall?.copyWith(
                    color: off ? colors.accentWarm : colors.profit,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
