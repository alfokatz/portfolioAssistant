import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/daily_brief/nav/daily_brief_router.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_format.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// "Tu brief de hoy" en la Home: una fila editorial (sin card) con la
/// variación del último cierre. Lleva a la pantalla del brief.
///
/// Con el interruptor `daily_brief` apagado, sin cartera, en fin de semana o
/// en un día sin cierre nuevo, no ocupa lugar: la Home queda como siempre.
/// Mientras se calcula (o Porty escribe) muestra la misma fila con el texto
/// en skeleton, del alto final.
class DailyBriefHomeRow extends ConsumerStatefulWidget {
  const DailyBriefHomeRow({
    super.key,
    required this.history,
    required this.lots,
  });

  /// El historial de la Home (`HomeState.history`): de ahí sale el número.
  final List<PortfolioHistoryPoint> history;

  /// Las compras de la cartera (de `PortfolioSummary.lots`).
  final List<Position> lots;

  @override
  ConsumerState<DailyBriefHomeRow> createState() => _DailyBriefHomeRowState();
}

class _DailyBriefHomeRowState extends ConsumerState<DailyBriefHomeRow> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(DailyBriefHomeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lots, widget.lots) ||
        !identical(oldWidget.history, widget.history)) {
      _ensure();
    }
  }

  /// Después del frame: un provider no se modifica en medio de un build.
  void _ensure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(dailyBriefControllerProvider.notifier)
          .ensureFor(widget.history, widget.lots);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyBriefControllerProvider);
    if (state.phase == DailyBriefPhase.hidden) return const SizedBox.shrink();
    final brief = state.phase == DailyBriefPhase.ready ? state.brief : null;
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.sp12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'daily_brief_home_title'.tr(),
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (brief == null && state.generating)
                  Text(
                    'daily_brief_home_preparing'.tr(),
                    style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                  )
                else
                  SkeletonText(
                    brief == null
                        ? null
                        : 'daily_brief_home_summary'.tr(
                          namedArgs: {
                            'pct': DailyBriefFormat.pct(brief.numbers.pct),
                          },
                        ),
                    placeholder: 'Tu cartera cerró +0,0%',
                    style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
          if (brief != null)
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: MotionAwareSize(
        duration: const Duration(milliseconds: 220),
        child: Semantics(
          button: brief != null,
          onTapHint: brief == null ? null : 'daily_brief_home_open_hint'.tr(),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            onTap:
                brief == null
                    ? null
                    : () {
                      PortyHapticsService.maybeOf(context)?.selectionTap();
                      context.pushNamed(
                        DailyBriefRouter.routeName,
                        extra: DailyBriefRouter.args(
                          day: brief.day,
                          source: 'home',
                        ),
                      );
                    },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget,
              ),
              child: AnimatedSwitcher(
                duration:
                    reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(
                    brief == null ? 'loading' : 'ready-${brief.day}',
                  ),
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La entrada secundaria al feed de noticias (Fase 2): solo si el
/// interruptor está prendido, la pieza `feed` también y la pantalla existe
/// (`newsFeedAvailableProvider`).
class DailyBriefFeedEntry extends ConsumerWidget {
  const DailyBriefFeedEntry({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      dailyBriefControllerProvider.select((s) => s.status),
    );
    if (!ref.watch(newsFeedAvailableProvider) || !status.piece('feed')) {
      return const SizedBox.shrink();
    }
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'daily_brief_feed_entry_title'.tr(),
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'daily_brief_feed_entry_subtitle'.tr(),
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
