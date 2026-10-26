import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/watchlist/nav/watchlist_router.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// En la Home, debajo de las posiciones: "Lista de seguimiento · N". Para
/// Free también (abre la explicación y el paywall).
class WatchlistEntryCard extends ConsumerStatefulWidget {
  const WatchlistEntryCard({super.key});

  @override
  ConsumerState<WatchlistEntryCard> createState() => _WatchlistEntryCardState();
}

class _WatchlistEntryCardState extends ConsumerState<WatchlistEntryCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tier = ref.read(subscriptionProvider).tier;
      final state = ref.read(watchlistProvider);
      if (PlanMatrix.of(tier).watchlistLimit > 0 && !state.loaded) {
        ref.read(watchlistProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final count = ref.watch(watchlistProvider.select((s) => s.items.length));
    final subtitle =
        count > 0
            ? (count == 1
                    ? 'watchlist_entry_subtitle_one'
                    : 'watchlist_entry_subtitle')
                .tr(namedArgs: {'count': '$count'})
            : 'watchlist_entry_subtitle_empty'.tr();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(WatchlistRouter.routeName),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.visibility_outlined,
                    color: colors.textSecondary,
                    size: AppDimens.iconMd,
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'watchlist_title'.tr(),
                        style: tt.titleMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppDimens.iconMd,
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
