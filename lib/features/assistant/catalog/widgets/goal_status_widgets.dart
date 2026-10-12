import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_goal_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart'
    show GoalProgressBar;
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// `QaGoalStatus`: una meta guardada (pestaña Metas) tal como está HOY:
/// lo juntado, la barra, cuánto aportar por mes, cuánto falta y el análisis
/// de Porty. Responde "¿cómo va mi meta?" sin rehacer el plan.
///
/// Los números los pone la app (la misma cuenta que el detalle de la meta,
/// ver [GoalProgress]), nunca el modelo: él solo nombra la meta. Se busca
/// por nombre en [QaGoalScope], así la card sigue viva si cambia la meta.
abstract final class GoalStatusWidgets {
  static Widget qaGoalStatus(CatalogItemContext ctx) {
    final map = ctx.data as JsonMap;
    final label = '${map['goal'] ?? ''}'.trim();
    return Builder(
      builder: (context) {
        final status = QaGoalScope.maybeOf(context)?.statusFor?.call(label);
        if (status == null) {
          return QaCardShell(
            child: Text(
              'No encontré la meta "$label" en Metas.',
              style: QaText.body,
            ),
          );
        }
        return QaCardShell(
          child: QaGoalStatusCard(
            goal: status.goal,
            progress: status.progress,
            onOpen: () => QaGoalScope.maybeOf(context)?.onOpen(status.goal.id),
          ),
        );
      },
    );
  }
}

class QaGoalStatusCard extends StatelessWidget {
  const QaGoalStatusCard({
    super.key,
    required this.goal,
    required this.progress,
    this.onOpen,
  });

  final UserGoal goal;
  final GoalProgress progress;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final locale = Localizations.localeOf(context);
    final p = progress;
    final statusColor = GoalAnalysis.statusColor(p.status, colors);
    final date = DateFormat.yMMMM(locale.toLanguageTag()).format(goal.targetDate);
    final missing = (p.target - p.saved).clamp(0.0, double.infinity);
    final behind = p.status == GoalProgressStatus.behind;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QaCardTitle(
          title: goal.label,
          subtitle: 'goals_card_subtitle'.tr(
            namedArgs: {'amount': QaFormat.money(goal.targetAmount), 'date': date},
          ),
          icon:
              goal.type == GoalType.retirement
                  ? Icons.beach_access_outlined
                  : Icons.flag_outlined,
          trailing: QaTag(GoalAnalysis.statusLabel(p.status), color: statusColor),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(QaFormat.money(p.saved), style: QaText.display, maxLines: 1),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'goal_of_target'.tr(
                  namedArgs: {'target': QaFormat.money(goal.targetAmount)},
                ),
                style: QaText.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(p.fraction * 100).round()}%',
              style: QaText.value.copyWith(color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: QaSpace.gap),
        GoalProgressBar(fraction: p.fraction, color: statusColor, height: 8),
        const SizedBox(height: QaSpace.sectionGap),
        Row(
          children: [
            // Atrasada: lo que hace falta desde hoy, no lo del plan.
            Expanded(
              child: QaStat(
                label:
                    behind
                        ? 'goal_stat_monthly_now'.tr()
                        : 'goal_stat_monthly'.tr(),
                value: QaFormat.money(
                  behind ? p.requiredMonthlyNow : p.plannedMonthly,
                ),
              ),
            ),
            Expanded(
              child: QaStat(
                label: 'goal_plan_months_left'.tr(),
                value: 'goal_months'.plural(p.monthsRemaining),
              ),
            ),
            Expanded(
              child: QaStat(
                label: 'goal_stat_missing'.tr(),
                value: QaFormat.money(missing),
              ),
            ),
          ],
        ),
        const SizedBox(height: QaSpace.gap),
        QaInset(
          color: statusColor.withValues(alpha: 0.08),
          child: Text(
            GoalAnalysis.text(goal, p, locale),
            style: QaText.body,
          ),
        ),
        if (onOpen != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: QaColors.accentBlue,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ver meta',
                    style: QaText.label.copyWith(
                      color: QaColors.accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: QaColors.accentBlue,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
