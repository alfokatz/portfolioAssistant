import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_shares.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/nav/goals_router.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_actions.dart';
import 'package:portfolio_assistant/features/goals/view/goal_analysis.dart';
import 'package:portfolio_assistant/features/goals/view/goals_verdict.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Pestaña Metas, con la forma de las pantallas donde Porty acompaña
/// (Posiciones cerradas, Agregar posición): arriba Porty dice en una frase
/// cómo vienen TODAS las metas, con la cara que corresponde; abajo, las
/// metas como filas de un grupo (no una pila de cards iguales), cada una
/// con su anillo de progreso. Sin metas, Porty propone por dónde empezar.
/// Las metas se guardan desde el chat (la card del plan o pidiéndoselo).
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
    final state = ref.watch(goalsProvider);
    final holdings = ref.watch(goalHoldingsProvider);
    final now = DateTime.now();
    ({UserGoal goal, GoalProgress progress}) withProgress(UserGoal g) => (
      goal: g,
      progress: GoalProgress.of(
        g,
        now,
        holdings: GoalShares.holdingsFor(g, state.goals, holdings),
      ),
    );
    final active = [for (final g in state.active) withProgress(g)];
    final done = [
      for (final g in state.goals)
        if (g.status == GoalStatus.achieved) withProgress(g),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LoadingSwitcher(
          loading: !state.loaded,
          placeholder:
              (_) => const SkeletonScope(
                child: _GoalsList(active: null, done: []),
              ),
          child:
              (_) => RefreshIndicator(
                color: colors.accentBlue,
                backgroundColor: colors.surfaceCard,
                onRefresh: () => ref.read(goalsProvider.notifier).load(),
                child: _GoalsList(active: active, done: done),
              ),
        ),
      ),
    );
  }
}

typedef _Goal = ({UserGoal goal, GoalProgress progress});

/// El título, lo que dice Porty y los grupos de metas. Con [active] en
/// `null` es su propio skeleton (la misma estructura, con barras).
class _GoalsList extends StatelessWidget {
  const _GoalsList({required this.active, required this.done});

  final List<_Goal>? active;
  final List<_Goal> done;

  static const skeletonRows = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final active = this.active;
    final skeleton = active == null;
    final empty = !skeleton && active.isEmpty && done.isEmpty;

    return ListView(
      physics:
          skeleton
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        // La barra de pestañas flota encima del final de la lista.
        AppDimens.sp48 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, AppDimens.sp20),
          child: Semantics(
            header: true,
            child: Text(
              'goals_title'.tr(),
              style: tt.displaySmall?.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        if (skeleton)
          const _VerdictSkeleton()
        else if (empty)
          PortySays(
            messageKey: 'empty',
            message: Text('goals_empty_porty'.tr()),
          )
        else
          _Verdict(verdict: GoalsVerdict.of(active, achieved: done.length)!),
        const SizedBox(height: AppDimens.sp32),
        if (skeleton) ...[
          const _GroupTitle(null),
          _Group(
            children: [
              for (var i = 0; i < skeletonRows; i++) const _GoalRow(goal: null),
            ],
          ),
        ] else if (empty) ...[
          _GroupTitle('goals_ideas_title'.tr()),
          _Group(children: [for (final idea in _ideas) _IdeaRow(idea: idea)]),
        ] else ...[
          if (active.isNotEmpty) ...[
            _GroupTitle('goals_active_section'.tr()),
            _Group(
              children: [
                for (final g in active) _GoalRow(goal: g),
                const _NewGoalRow(),
              ],
            ),
          ] else
            _Group(children: const [_NewGoalRow()]),
          if (done.isNotEmpty) ...[
            const SizedBox(height: AppDimens.sp28),
            _GroupTitle('goals_achieved_section'.tr()),
            _Group(children: [for (final g in done) _GoalRow(goal: g)]),
          ],
        ],
      ],
    );
  }
}

/// Porty sobre todas las metas juntas (ver [GoalsVerdict]).
class _Verdict extends StatelessWidget {
  const _Verdict({required this.verdict});

  final GoalsVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final footnote = verdict.footnote;
    return PortySays(
      messageKey: verdict.message,
      mood: verdict.mood,
      message: Text(verdict.message),
      footnote: footnote == null ? null : Text(footnote),
    );
  }
}

class _VerdictSkeleton extends StatelessWidget {
  const _VerdictSkeleton();

  @override
  Widget build(BuildContext context) {
    final line = PortySays.style(context);
    return PortySays(
      messageKey: 'skeleton',
      message: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonText(
            null,
            placeholder: 'Vas en camino con tus 0 metas.',
            style: line,
          ),
          const SizedBox(height: AppDimens.sp4),
          SkeletonText(
            null,
            placeholder: 'Este mes te tocan 0.000',
            style: line,
          ),
        ],
      ),
    );
  }
}

/// El nombre de un grupo, como los de Ajustes y los meses de Posiciones
/// cerradas (sin mayúsculas espaciadas).
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String? title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: AppDimens.sp4, bottom: AppDimens.sp8),
    child: Semantics(
      header: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SkeletonText(
          title,
          placeholder: 'En curso',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: context.customColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// Una sola superficie con las filas separadas por divisores alineados al
/// texto (como los grupos de Ajustes y las sugerencias del chat).
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: _rowPadding + _GoalRing.size + AppDimens.sp12,
                endIndent: _rowPadding,
                color: colors.border,
              ),
            child,
          ],
        ],
      ),
    );
  }
}

const _rowPadding = AppDimens.sp16;

/// Una meta: su anillo de progreso (del color del veredicto, con el ícono
/// del tipo adentro), nombre, cuánto lleva de cuánto y para cuándo; a la
/// derecha, cómo viene y el aporte por mes. Tocar abre el detalle;
/// mantener apretada, sus opciones; deslizar a la izquierda, borrarla (con
/// confirmación). Con [goal] en `null` es su propio skeleton.
class _GoalRow extends ConsumerWidget {
  const _GoalRow({required this.goal});

  final _Goal? goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    const tabular = [FontFeature.tabularFigures()];
    final g = goal;
    final p = g?.progress;
    final achieved = g?.goal.status == GoalStatus.achieved;
    final statusColor =
        p == null
            ? colors.textSecondary
            : GoalAnalysis.statusColor(p.status, colors);

    String? amounts;
    String? detail;
    if (g != null) {
      amounts = 'goals_card_saved'.tr(
        namedArgs: {
          'saved': QaFormat.money(g.progress.saved),
          'target': QaFormat.money(g.progress.target),
        },
      );
      final date = DateFormat.yMMM(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(g.goal.targetDate);
      // Cumplida: ya no hay aporte, solo para cuándo era.
      detail =
          achieved
              ? date
              : '${'goals_card_monthly'.tr(namedArgs: {'monthly': QaFormat.money(g.progress.plannedMonthly)})} · $date';
    }

    final secondary = tt.bodySmall?.copyWith(
      color: colors.textSecondary,
      height: 1.35,
      fontFeatures: tabular,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _rowPadding,
        vertical: AppDimens.sp16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          g == null
              ? const SkeletonBlock(
                width: _GoalRing.size,
                height: _GoalRing.size,
                radius: _GoalRing.size / 2,
              )
              : _GoalRing(
                fraction: g.progress.fraction,
                color: statusColor,
                icon: _iconFor(g.goal.type),
              ),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre y cómo viene, en el mismo renglón.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: SkeletonText(
                        g?.goal.label,
                        placeholder: 'Viaje a Japón',
                        style: tt.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimens.sp8),
                    SkeletonText(
                      p == null ? null : GoalAnalysis.statusLabel(p.status),
                      placeholder: 'En camino',
                      style: tt.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.sp4),
                SkeletonText(
                  amounts,
                  placeholder: '0.000 \$ de 00.000 \$',
                  style: tt.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                SkeletonText(
                  detail,
                  placeholder: '000 \$/mes · oct 2028',
                  style: secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (g == null) return row;

    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => GoalsRouter.openDetail(context, g.goal.id),
        onLongPress: () => GoalActions.showMenu(context, ref, g.goal),
        child: row,
      ),
    );

    return Semantics(
      button: true,
      onLongPressHint: 'goal_options'.tr(),
      child: Dismissible(
        key: ValueKey('goal-${g.goal.id}'),
        direction: DismissDirection.endToStart,
        // El borrado lo hace confirmDelete (que ya la saca de la lista):
        // la fila solo vuelve a su lugar si se cancela.
        confirmDismiss: (_) async {
          await GoalActions.confirmDelete(context, ref, g.goal);
          return false;
        },
        background: ColoredBox(
          color: colors.loss.withValues(alpha: 0.14),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: AppDimens.sp24),
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
          ),
        ),
        child: tappable,
      ),
    );
  }
}

IconData _iconFor(GoalType type) => switch (type) {
  GoalType.purchase => Icons.shopping_bag_outlined,
  GoalType.retirement => Icons.beach_access_outlined,
  GoalType.other => Icons.flag_outlined,
};

/// Cuánto lleva una meta, como un anillo alrededor del ícono de su tipo:
/// la vuelta completa es el monto. Un avance mínimo se ve igual (un punto),
/// para que "recién empezás" y "llevás algo" no se confundan.
class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.fraction,
    required this.color,
    required this.icon,
  });

  final double fraction;
  final Color color;
  final IconData icon;

  static const size = 44.0;
  static const stroke = 3.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      value: '${(fraction * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion ? fraction : 0, end: fraction),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutQuart,
          builder:
              (context, value, child) => CustomPaint(
                painter: _RingPainter(
                  fraction: value,
                  color: color,
                  // Visible sobre la card en claro y en oscuro (el
                  // surfaceElevated casi no se distinguía del blanco).
                  track: colors.textSecondary.withValues(alpha: 0.16),
                ),
                child: child,
              ),
          child: Center(
            child: Icon(icon, size: AppDimens.iconMd - 2, color: colors.onChip),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _GoalRing.stroke / 2,
      _GoalRing.stroke / 2,
      size.width - _GoalRing.stroke,
      size.height - _GoalRing.stroke,
    );
    final base =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _GoalRing.stroke
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = track);
    if (fraction <= 0) return;
    // Un avance chiquito se ve como un punto, no desaparece.
    final sweep = math.max(fraction, 0.015) * 2 * math.pi;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Al final del grupo: armar otra meta con Porty (abre el chat con la
/// pregunta).
class _NewGoalRow extends StatelessWidget {
  const _NewGoalRow();

  @override
  Widget build(BuildContext context) => _ActionRow(
    icon: Icons.add_rounded,
    label: 'goals_new'.tr(),
    accent: true,
    onTap:
        () => GotoAssistant(
          initialQuestion: 'goals_new_question'.tr(),
        ).navigate(context: context),
  );
}

/// Una idea para la primera meta: el chat se abre con la pregunta.
typedef _Idea = ({String label, String question, IconData icon});

final _ideas = <_Idea>[
  (
    label: 'goals_idea_emergency',
    question: 'goals_idea_emergency_q',
    icon: Icons.health_and_safety_outlined,
  ),
  (
    label: 'goals_idea_trip',
    question: 'goals_idea_trip_q',
    icon: Icons.flight_takeoff_rounded,
  ),
  (
    label: 'goals_idea_purchase',
    question: 'goals_idea_purchase_q',
    icon: Icons.shopping_bag_outlined,
  ),
  (
    label: 'goals_idea_retirement',
    question: 'goals_idea_retirement_q',
    icon: Icons.beach_access_outlined,
  ),
];

class _IdeaRow extends StatelessWidget {
  const _IdeaRow({required this.idea});

  final _Idea idea;

  @override
  Widget build(BuildContext context) => _ActionRow(
    icon: idea.icon,
    label: idea.label.tr(),
    onTap:
        () => GotoAssistant(
          initialQuestion: idea.question.tr(),
        ).navigate(context: context),
  );
}

/// Una fila que lleva al chat: círculo con ícono, texto y la flecha ↗ de
/// las sugerencias del chat (tocar le pregunta a Porty, no navega).
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Armar una meta es la acción de la pantalla: en terracota.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.touchTarget + AppDimens.sp16,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _rowPadding,
                vertical: AppDimens.sp12,
              ),
              child: Row(
                children: [
                  Container(
                    width: _GoalRing.size,
                    height: _GoalRing.size,
                    decoration: BoxDecoration(
                      // En oscuro, un lavado terracota sobre grafito se lee
                      // marrón (DESIGN.md, "Quiet Chips"): el círculo va en
                      // grafito y solo el ícono lleva el acento.
                      color:
                          accent &&
                                  Theme.of(context).brightness ==
                                      Brightness.light
                              ? colors.accentBlue.withValues(alpha: 0.12)
                              : colors.chip,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: AppDimens.iconMd,
                      color: accent ? colors.accentBlue : colors.onChip,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.north_east_rounded,
                      size: AppDimens.iconSm,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
