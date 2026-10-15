import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/confirm_sheet.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/savings_plan_edit_sheet.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_replan.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_shares.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Acciones sobre una meta que comparten la lista de Metas y el detalle.
abstract final class GoalActions {
  /// Pide confirmación y borra la meta. `true` si se borró.
  static Future<bool> confirmDelete(
    BuildContext context,
    WidgetRef ref,
    UserGoal goal,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'goal_delete_title'.tr(namedArgs: {'goal': goal.label}),
      body: 'goal_delete_body'.tr(),
      confirmLabel: 'goal_delete'.tr(),
    );
    if (!confirmed) return false;
    try {
      await ref.read(goalsProvider.notifier).delete(goal.id);
      ref
          .read(alertProvider.notifier)
          .showSuccess(
            message: 'goal_deleted'.tr(namedArgs: {'goal': goal.label}),
          );
      return true;
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
      return false;
    }
  }

  static Future<void> setStatus(
    WidgetRef ref,
    UserGoal goal,
    GoalStatus status,
  ) async {
    try {
      await ref.read(goalsProvider.notifier).setStatus(goal.id, status);
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
    }
  }

  /// "Editar plan" de una meta guardada: el mismo editor que la card del
  /// chat. "Lo que ya tenés" es el mismo dato que "Ahorros fuera de la
  /// app" (se ven y se guardan iguales); el plan parte de eso más el valor
  /// de sus inversiones asignadas, y se recalcula y se guarda en la meta.
  static Future<void> editPlan(
    BuildContext context,
    WidgetRef ref,
    UserGoal goal,
  ) async {
    // Lo que le toca de cada inversión que comparte con otras metas.
    final holdings = GoalShares.holdingsFor(
      goal,
      ref.read(goalsProvider).goals,
      ref.read(goalHoldingsProvider),
    );
    final invested = GoalReplan.capital(goal, holdings, externalSavings: 0);
    final change = await SavingsPlanEditSheet.show(
      context,
      label: goal.label,
      inputs: goal.snapshot.inputs,
      targetDate: goal.targetDate,
      currentAmount: goal.externalSavings,
      currentLabel: 'goal_outside_title'.tr(),
      currentHelper:
          invested > 0
              ? 'goal_edit_outside_helper_invested'.tr(
                namedArgs: {'amount': QaFormat.money(invested)},
              )
              : 'goal_outside_subtitle'.tr(),
    );
    if (change == null) return;
    final draft = editedDraft(goal, change, holdings: holdings);
    if (draft == null) return;
    try {
      await ref
          .read(goalsProvider.notifier)
          .updatePlan(goal.id, draft, externalSavings: change.currentAmount);
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'goal_plan_updated'.tr());
    } catch (_) {
      ref.read(alertProvider.notifier).showError(message: 'goal_error'.tr());
    }
  }

  /// La meta [goal] con lo que el usuario cambió en el editor (ver
  /// [GoalReplan.draft]). Con [holdings], `change.currentAmount` son sus
  /// ahorros fuera de la app: el plan parte de eso + sus inversiones
  /// asignadas y, si eso cambió, se rehace desde hoy.
  static GoalDraft? editedDraft(
    UserGoal goal,
    SavingsPlanEdit change, {
    Map<String, double>? holdings,
    DateTime? now,
  }) {
    final capital =
        holdings == null
            ? change.currentAmount
            : GoalReplan.capital(
              goal,
              holdings,
              externalSavings: change.currentAmount,
            );
    final today = now ?? DateTime.now();
    return GoalReplan.draft(
      goal,
      label: change.label,
      targetAmount: change.targetAmount,
      targetDate: change.targetDate,
      currentAmount: capital,
      risk: change.risk,
      startDate:
          holdings != null && !GoalReplan.startsFrom(goal, capital)
              ? DateTime(today.year, today.month, today.day)
              : null,
    );
  }

  /// Las opciones de una meta (los tres puntitos del detalle, o mantenerla
  /// apretada en la lista): editar el plan, marcarla lograda (o volver a
  /// activa) y borrarla.
  static Future<void> showMenu(
    BuildContext context,
    WidgetRef ref,
    UserGoal goal, {
    VoidCallback? onDeleted,
  }) async {
    final active = goal.status == GoalStatus.active;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.customColors.surfaceCard,
      builder:
          (context) => _GoalMenu(
            goal: goal,
            options: [
              (
                key: 'edit',
                icon: Icons.tune_rounded,
                title: 'goal_edit_plan'.tr(),
                subtitle: 'goal_edit_plan_subtitle'.tr(),
                danger: false,
              ),
              (
                key: 'status',
                icon:
                    active ? Icons.emoji_events_outlined : Icons.replay_rounded,
                title:
                    active
                        ? 'goal_mark_achieved'.tr()
                        : 'goal_mark_active'.tr(),
                subtitle:
                    active
                        ? 'goal_mark_achieved_subtitle'.tr()
                        : 'goal_mark_active_subtitle'.tr(),
                danger: false,
              ),
              (
                key: 'delete',
                icon: Icons.delete_outline_rounded,
                title: 'goal_delete'.tr(),
                subtitle: 'goal_delete_subtitle'.tr(),
                danger: true,
              ),
            ],
          ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        await editPlan(context, ref, goal);
      case 'status':
        await setStatus(
          ref,
          goal,
          active ? GoalStatus.achieved : GoalStatus.active,
        );
      case 'delete':
        if (await confirmDelete(context, ref, goal)) onDeleted?.call();
    }
  }
}

typedef _GoalOption =
    ({String key, IconData icon, String title, String subtitle, bool danger});

/// La hoja de opciones de una meta: el nombre arriba y cada opción con su
/// ícono en un círculo de color, título y una línea que explica qué hace.
class _GoalMenu extends StatelessWidget {
  const _GoalMenu({required this.goal, required this.options});

  final UserGoal goal;
  final List<_GoalOption> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              goal.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
            for (final o in options) ...[
              if (o.danger) ...[
                Divider(height: 1, color: colors.border),
                const SizedBox(height: AppDimens.sp4),
              ],
              _option(context, o),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, _GoalOption o) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final tint = o.danger ? colors.loss : colors.accentBlue;
    return InkWell(
      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
      onTap: () => Navigator.of(context).pop(o.key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(o.icon, size: AppDimens.iconMd, color: tint),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.title,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: o.danger ? colors.loss : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.subtitle,
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
