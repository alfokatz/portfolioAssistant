import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/nav/goals_router.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_actions.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Pestaña Metas: lo que el usuario quiere lograr, con el plan que armó
/// Porty y si va en camino. Las metas se guardan desde el chat (la card del
/// plan o pidiéndoselo a Porty).
class GoalsScreen extends StatefulHookConsumerWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends BaseStatefulWidget<GoalsScreen> {
  // Pestaña del shell: el shell ya escucha los eventos globales.
  @override
  bool get subscribesToGlobalEvents => false;

  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(() => ref.read(goalsProvider.notifier).load());
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(goalsProvider);
    final active = state.active;
    final done = [
      for (final g in state.goals)
        if (g.status == GoalStatus.achieved) g,
    ];
    final now = DateTime.now();
    final holdings = ref.watch(goalHoldingsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(goalsProvider.notifier).load(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp8,
              AppDimens.pageHorizontal,
              // La barra de pestañas flota encima del final de la lista.
              AppDimens.sp32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, AppDimens.sp8),
                child: Semantics(
                  header: true,
                  child: Text(
                    'goals_title'.tr(),
                    style: tt.displaySmall?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              Text(
                'goals_subtitle'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppDimens.sp20),
              if (!state.loaded)
                // El loader se expande: dentro de la lista necesita un alto.
                SizedBox(
                  height: 280,
                  child: Center(
                    child: PortyLoader(message: 'loader_one_moment'.tr()),
                  ),
                )
              else if (active.isEmpty && done.isEmpty)
                const _EmptyGoals()
              else ...[
                for (final goal in active) ...[
                  _GoalCard(
                    goal: goal,
                    progress: GoalProgress.of(goal, now, holdings: holdings),
                  ),
                  const SizedBox(height: AppDimens.sp12),
                ],
                const SizedBox(height: AppDimens.sp8),
                _NewGoalButton(),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: AppDimens.sp24),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppDimens.sp4,
                      bottom: AppDimens.sp8,
                    ),
                    child: Text(
                      'goals_achieved_section'.tr().toUpperCase(),
                      style: tt.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  for (final goal in done) ...[
                    _GoalCard(
                    goal: goal,
                    progress: GoalProgress.of(goal, now, holdings: holdings),
                  ),
                    const SizedBox(height: AppDimens.sp12),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sin metas: Porty invita a contarle una.
class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.sp20),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          const ExcludeSemantics(
            child: PortyAvatar(size: 72, animated: true),
          ),
          const SizedBox(height: AppDimens.sp16),
          Text(
            'goals_empty_title'.tr(),
            textAlign: TextAlign.center,
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            'goals_empty_body'.tr(),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimens.sp20),
          PositionPrimaryButton(
            label: 'goals_new'.tr(),
            onPressed:
                () => GotoAssistant(
                  initialQuestion: 'goals_new_question'.tr(),
                ).navigate(context: context),
          ),
        ],
      ),
    );
  }
}

class _NewGoalButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return OutlinedButton.icon(
      onPressed:
          () => GotoAssistant(
            initialQuestion: 'goals_new_question'.tr(),
          ).navigate(context: context),
      icon: Icon(Icons.add_rounded, color: colors.accentBlue),
      label: Text(
        'goals_new'.tr(),
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppDimens.touchTarget + 4),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
      ),
    );
  }
}

/// Una meta en la lista: nombre, monto y fecha, barra de progreso y el
/// veredicto ("En camino", "Atrasada"…). Deslizarla a la izquierda la borra
/// (con confirmación); mantenerla apretada abre sus opciones.
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal, required this.progress});

  final UserGoal goal;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final statusColor = GoalAnalysis.statusColor(progress.status, colors);
    final date = DateFormat.yMMMM(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(goal.targetDate);

    final card = Material(
      color: colors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoalsRouter.openDetail(context, goal.id),
        onLongPress: () => GoalActions.showMenu(context, ref, goal),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _GoalIcon(type: goal.type),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'goals_card_subtitle'.tr(
                            namedArgs: {
                              'amount': QaFormat.money(goal.targetAmount),
                              'date': date,
                            },
                          ),
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(
                    label: GoalAnalysis.statusLabel(progress.status),
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.sp16),
              GoalProgressBar(fraction: progress.fraction, color: statusColor),
              const SizedBox(height: AppDimens.sp8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'goals_card_saved'.tr(
                        namedArgs: {
                          'saved': QaFormat.money(progress.saved),
                          'target': QaFormat.money(progress.target),
                        },
                      ),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (goal.status == GoalStatus.active)
                    Text(
                      'goals_card_monthly'.tr(
                        namedArgs: {
                          'monthly': QaFormat.money(progress.plannedMonthly),
                        },
                      ),
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      onLongPressHint: 'goal_options'.tr(),
      child: Dismissible(
        key: ValueKey('goal-${goal.id}'),
        direction: DismissDirection.endToStart,
        // El borrado lo hace confirmDelete (que ya la saca de la lista):
        // el Dismissible solo vuelve a su lugar si se cancela.
        confirmDismiss: (_) async {
          await GoalActions.confirmDelete(context, ref, goal);
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppDimens.sp24),
          decoration: BoxDecoration(
            color: colors.loss.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, color: colors.loss),
              const SizedBox(width: AppDimens.sp6),
              Text(
                'goal_delete_confirm'.tr(),
                style: tt.labelLarge?.copyWith(
                  color: colors.loss,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        child: card,
      ),
    );
  }
}

class _GoalIcon extends StatelessWidget {
  const _GoalIcon({required this.type});

  final GoalType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        switch (type) {
          GoalType.purchase => Icons.shopping_bag_outlined,
          GoalType.retirement => Icons.beach_access_outlined,
          GoalType.other => Icons.flag_outlined,
        },
        size: 20,
        color: colors.accentBlue,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppDimens.sp8,
      vertical: 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Barra de progreso de una meta (también en el detalle).
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      value: '${(fraction * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder:
              (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: height,
                color: color,
                backgroundColor: colors.surfaceElevated,
              ),
        ),
      ),
    );
  }
}
