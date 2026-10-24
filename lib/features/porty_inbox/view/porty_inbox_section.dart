import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/notifications/providers/price_alerts_provider.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insight.dart';
import 'package:portfolio_assistant/features/porty_inbox/providers/porty_inbox_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/porty_topics_provider.dart';

/// "Hoy te marco 2 cosas": lo que Porty ve en la cartera, el plan, las metas
/// y las alertas, en la Home y sin que el usuario pregunte. Cada fila abre el
/// chat con su pregunta (y su pantalla como contexto); deslizarla la oculta
/// una semana. Sin nada para marcar, no ocupa lugar.
class PortyInboxSection extends ConsumerStatefulWidget {
  const PortyInboxSection({super.key});

  @override
  ConsumerState<PortyInboxSection> createState() => _PortyInboxSectionState();
}

class _PortyInboxSectionState extends ConsumerState<PortyInboxSection> {
  @override
  void initState() {
    super.initState();
    // Lo que no carga la Home por su cuenta. Cada uno, si se puede: sin
    // sesión o sin el plan, la bandeja sale con lo que haya.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tier = ref.read(subscriptionProvider).tier;
      void tryLoad(void Function() load) {
        try {
          load();
        } catch (_) {}
      }

      if (SubscriptionPolicy.allows(tier, PlanFeature.allocationPlan)) {
        tryLoad(() => ref.read(allocationProvider.notifier).load());
      }
      tryLoad(() {
        if (!ref.read(goalsProvider).loaded) {
          ref.read(goalsProvider.notifier).load();
        }
      });
      tryLoad(() {
        if (!ref.read(priceAlertsProvider).loaded) {
          ref.read(priceAlertsProvider.notifier).load();
        }
      });
      tryLoad(() => ref.read(portyTopicsProvider.notifier).ensureLoaded());
    });
  }

  void _open(PortyInsight insight) {
    PortyHapticsService.maybeOf(context)?.selectionTap();
    GotoAssistant(
      initialQuestion: PortyInsightCopy.question(insight),
      screen: insight.screen,
    ).navigate(context: context);
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(portyInsightsProvider);
    if (insights.isEmpty) return const SizedBox.shrink();
    final colors = context.customColors;
    final mood =
        insights.any((i) => i.tone == PortyInsightTone.attention)
            ? PortyAvatarState.concerned
            : insights.every((i) => i.tone == PortyInsightTone.good)
            ? PortyAvatarState.answered
            : PortyAvatarState.idle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortySays(
            message: Text(
              insights.length == 1
                  ? 'porty_inbox_title_one'.tr()
                  : 'porty_inbox_title_many'.tr(
                    namedArgs: {'count': '${insights.length}'},
                  ),
            ),
            messageKey: insights.length,
            mood: mood,
          ),
          const SizedBox(height: AppDimens.sp16),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              border: Border.all(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, insight) in insights.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppDimens.sp16 + _iconBox + AppDimens.sp12,
                      endIndent: AppDimens.sp16,
                      color: colors.border,
                    ),
                  Dismissible(
                    key: ValueKey(insight.id),
                    direction: DismissDirection.endToStart,
                    onDismissed:
                        (_) => ref
                            .read(portyInboxHiddenProvider.notifier)
                            .hide(insight.id),
                    background: Container(
                      color: colors.inset,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp20,
                      ),
                      child: Text(
                        'porty_inbox_hide'.tr(),
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    child: _InsightRow(
                      insight: insight,
                      onTap: () => _open(insight),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _iconBox = 32.0;

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight, required this.onTap});

  final PortyInsight insight;
  final VoidCallback onTap;

  static IconData iconOf(PortyInsightKind kind) => switch (kind) {
    PortyInsightKind.allocationDrift => Icons.donut_large_rounded,
    PortyInsightKind.goalOverdue => Icons.event_busy_rounded,
    PortyInsightKind.goalBehind => Icons.flag_outlined,
    PortyInsightKind.goalAlmost => Icons.emoji_events_outlined,
    PortyInsightKind.concentration => Icons.pie_chart_outline_rounded,
    PortyInsightKind.alertNear => Icons.notifications_active_outlined,
    PortyInsightKind.deepLoss => Icons.trending_down_rounded,
    PortyInsightKind.topicMoved => Icons.history_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    // El ícono en el círculo silencioso de las filas; lo que pide atención
    // con el terracota de Porty y lo bueno en verde, nunca de fondo.
    final iconColor = switch (insight.tone) {
      PortyInsightTone.attention => colors.accentWarm,
      PortyInsightTone.good => colors.profit,
      PortyInsightTone.neutral => colors.onChip,
    };
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.touchTarget + AppDimens.sp12,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp16,
                vertical: AppDimens.sp12,
              ),
              child: Row(
                children: [
                  Container(
                    width: _iconBox,
                    height: _iconBox,
                    decoration: BoxDecoration(
                      color: colors.chip,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      iconOf(insight.kind),
                      size: AppDimens.iconSm,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PortyInsightCopy.title(insight),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          PortyInsightCopy.detail(insight),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
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

/// Los textos de cada insight, con los números en el formato de la app.
abstract final class PortyInsightCopy {
  static String _pct(double? v, {int decimals = 0}) =>
      AppNumberFormat.percent(v ?? 0, decimals: decimals, signed: false);
  static String _money(double? v) => AppNumberFormat.money(v ?? 0);

  static Map<String, String> _args(PortyInsight i) {
    final n = i.numbers;
    return {
      'ticker': i.ticker ?? '',
      'goal': i.goalLabel ?? '',
      'current': _pct(n['current']),
      'target_pct': _pct(n['target']),
      'pct': _pct(n['pct']),
      'weight': _pct(n['weight']),
      'required': _money(n['required']),
      'planned': _money(n['planned']),
      'left': _money(n['left']),
      'price': _money(n['price']),
      'target_price': _money(n['target']),
      'distance': _pct(n['distance'], decimals: 1),
      'pnl': AppNumberFormat.percent(n['pnl'] ?? 0, decimals: 0),
      'change': AppNumberFormat.percent(n['change'] ?? 0),
      'days': '${(n['days'] ?? 0).round()}',
      'price_then': _money(n['price_then']),
    };
  }

  static String _key(PortyInsight i) => switch (i.kind) {
    PortyInsightKind.allocationDrift => 'drift',
    PortyInsightKind.goalOverdue => 'goal_overdue',
    PortyInsightKind.goalBehind => 'goal_behind',
    PortyInsightKind.goalAlmost => 'goal_almost',
    PortyInsightKind.concentration => 'concentration',
    PortyInsightKind.alertNear => 'alert_near',
    PortyInsightKind.deepLoss => 'deep_loss',
    PortyInsightKind.topicMoved => 'topic_moved',
  };

  static String title(PortyInsight i) =>
      'porty_inbox_${_key(i)}_title'.tr(namedArgs: _args(i));

  static String detail(PortyInsight i) =>
      'porty_inbox_${_key(i)}_detail'.tr(namedArgs: _args(i));

  /// La pregunta que sale al chat al tocarlo.
  static String question(PortyInsight i) =>
      'porty_inbox_${_key(i)}_question'.tr(namedArgs: _args(i));
}
