import 'package:easy_localization/easy_localization.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/goals/view/goal_money.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// Lo que dice Porty arriba de la pestaña Metas: una frase sobre TODAS las
/// metas juntas (lo que más pide atención primero), con la cara que
/// corresponde, y una línea con los totales. Armada con los números de
/// [GoalProgress], nunca la escribe el modelo.
class GoalsVerdict {
  const GoalsVerdict._(this.message, this.mood, this.footnote);

  final String message;
  final PortyAvatarState mood;

  /// Los totales de las metas en curso (solo con más de una).
  final String? footnote;

  /// [active] = las metas en curso con su progreso; [achieved] = cuántas
  /// cumplidas hay. Sin ninguna de las dos, `null` (la pantalla muestra el
  /// estado vacío).
  static GoalsVerdict? of(
    List<({UserGoal goal, GoalProgress progress})> active, {
    required int achieved,
  }) {
    if (active.isEmpty) {
      return achieved == 0
          ? null
          : GoalsVerdict._(
            'goals_verdict_all_done'.tr(),
            PortyAvatarState.answered,
            null,
          );
    }

    final count = active.length;
    // Metas en monedas distintas no se suman entre sí: un total por moneda
    // ("$500 + $U 4,000"), en el orden en que aparecen.
    String total(double Function(GoalProgress p) amount) {
      final byCurrency = <DisplayCurrency, double>{};
      for (final g in active) {
        byCurrency[g.goal.currency] =
            (byCurrency[g.goal.currency] ?? 0) + amount(g.progress);
      }
      return [
        for (final e in byCurrency.entries) goalMoney(e.key, e.value),
      ].join(' + ');
    }

    final monthly = total((p) => p.plannedMonthly);
    final footnote =
        count < 2
            ? null
            : 'goals_verdict_totals'.tr(
              namedArgs: {
                'saved': total((p) => p.saved),
                'target': total((p) => p.target),
              },
            );

    List<({UserGoal goal, GoalProgress progress})> withStatus(
      GoalProgressStatus status,
    ) => [
      for (final g in active)
        if (g.progress.status == status) g,
    ];

    // Lo que más pide atención: una vencida, después una atrasada (la que
    // más aporte necesita).
    final overdue = withStatus(GoalProgressStatus.overdue);
    if (overdue.isNotEmpty) {
      final g = overdue.first;
      return GoalsVerdict._(
        'goals_verdict_overdue'.tr(
          namedArgs: {
            'goal': g.goal.label,
            'missing': g.goal.money(
              (g.progress.target - g.progress.saved).clamp(0, double.infinity),
            ),
          },
        ),
        PortyAvatarState.concerned,
        footnote,
      );
    }
    final behind = withStatus(GoalProgressStatus.behind)..sort(
      (a, b) => b.progress.requiredMonthlyNow.compareTo(
        a.progress.requiredMonthlyNow,
      ),
    );
    if (behind.isNotEmpty) {
      final g = behind.first;
      final args = {
        'goal': g.goal.label,
        'required': g.goal.money(g.progress.requiredMonthlyNow),
        'count': '${behind.length}',
      };
      return GoalsVerdict._(
        (behind.length == 1
                ? 'goals_verdict_behind_one'
                : 'goals_verdict_behind_many')
            .tr(namedArgs: args),
        PortyAvatarState.concerned,
        footnote,
      );
    }

    final args = {
      'goal': active.first.goal.label,
      'count': '$count',
      'monthly': monthly,
    };
    // Todas recién guardadas: todavía no hay nada que festejar.
    if (active.every(
      (g) => g.progress.status == GoalProgressStatus.justStarted,
    )) {
      return GoalsVerdict._(
        (count == 1
                ? 'goals_verdict_started_one'
                : 'goals_verdict_started_many')
            .tr(namedArgs: args),
        PortyAvatarState.idle,
        footnote,
      );
    }
    final ahead = withStatus(GoalProgressStatus.ahead);
    if (count > 1 && ahead.isNotEmpty) {
      return GoalsVerdict._(
        'goals_verdict_on_track_ahead'.tr(
          namedArgs: {...args, 'goal': ahead.first.goal.label},
        ),
        PortyAvatarState.answered,
        footnote,
      );
    }
    return GoalsVerdict._(
      (count == 1
              ? 'goals_verdict_on_track_one'
              : 'goals_verdict_on_track_many')
          .tr(namedArgs: args),
      PortyAvatarState.answered,
      footnote,
    );
  }
}
