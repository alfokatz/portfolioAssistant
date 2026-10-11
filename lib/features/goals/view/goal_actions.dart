import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Acciones sobre una meta que comparten la lista de Metas y el detalle.
abstract final class GoalActions {
  /// Pide confirmación y borra la meta. `true` si se borró.
  static Future<bool> confirmDelete(
    BuildContext context,
    WidgetRef ref,
    UserGoal goal,
  ) async {
    final colors = context.customColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'goal_delete_title'.tr(namedArgs: {'goal': goal.label}),
            ),
            content: Text('goal_delete_body'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('porty_memory_cancel'.tr()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'goal_delete_confirm'.tr(),
                  style: TextStyle(
                    color: colors.loss,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return false;
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

  /// Mantener apretada una meta en la lista: marcarla lograda (o volver a
  /// activa) y borrarla.
  static Future<void> showMenu(
    BuildContext context,
    WidgetRef ref,
    UserGoal goal,
  ) async {
    final colors = context.customColors;
    final active = goal.status == GoalStatus.active;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    goal.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    active ? Icons.check_circle_outline : Icons.replay_rounded,
                    color: colors.textPrimary,
                  ),
                  title: Text(
                    active
                        ? 'goal_mark_achieved'.tr()
                        : 'goal_mark_active'.tr(),
                  ),
                  onTap: () => Navigator.of(context).pop('status'),
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.loss),
                  title: Text(
                    'goal_delete'.tr(),
                    style: TextStyle(color: colors.loss),
                  ),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              ],
            ),
          ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'status':
        await setStatus(
          ref,
          goal,
          active ? GoalStatus.achieved : GoalStatus.active,
        );
      case 'delete':
        await confirmDelete(context, ref, goal);
    }
  }
}
