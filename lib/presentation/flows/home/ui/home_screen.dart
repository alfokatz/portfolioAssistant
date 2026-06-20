import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/content_state/content_state_widget.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/assistant_mode_chips.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_comparison_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_locked_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/closed_positions_entry_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_app_bar.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_empty_state.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_qa_entry_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/time_range_selector.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';

class HomeScreen extends StatefulHookConsumerWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomeScreenState();
}

class _HomeScreenState extends BaseStatefulWidget<HomeScreen> {
  @override
  void initState() {
    runAfterPostFrameCallback(() {
      ref.read(homeProvider.notifier).init();
    });
    super.initState();
  }

  void _onAddPosition(BuildContext context) {
    final tier = ref.read(subscriptionProvider).tier;
    final limit = SubscriptionPolicy.positionLimit(tier);
    final count = ref.read(homeProvider).summary?.valuations.length ?? 0;
    if (limit != null && count >= limit) {
      SubscriptionPaywallSheet.show(
        context,
        ref,
        reason: PaywallReason.modeLocked,
      );
      return;
    }
    ref.read(homeProvider.notifier).openAddPosition();
  }

  @override
  Widget buildView(BuildContext context) {
    final colors = context.customColors;
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final subscription = ref.watch(subscriptionProvider);
    final summary = state.summary;
    final isBenchmarkAllowed =
        SubscriptionPolicy.isBenchmarkAllowed(subscription.tier);

    final filteredHistory = HomeChartUtils.filterHistory(
      state.history,
      state.selectedRange,
    );
    final filteredBenchmark = HomeChartUtils.filterBenchmark(
      state.benchmark,
      state.selectedRange,
    );
    final chartValues = filteredHistory.map((p) => p.totalValue).toList();
    final periodPnl = state.selectedRange == ChartTimeRange.all && summary != null
        ? PeriodPnl(
            absolute: summary.totalPnlAbsolute,
            percent: summary.totalPnlPercent,
          )
        : HomeChartUtils.periodPnlFromHistory(filteredHistory);

    final valuations = List<PositionValuation>.from(
      summary?.valuations ?? const [],
    )..sort((a, b) => b.pnlAbsolute.compareTo(a.pnlAbsolute));
    final hasMorePositions = valuations.length > 5;
    final displayValuations = state.showAllPositions
        ? valuations
        : valuations.take(5).toList(growable: false);

    return Scaffold(
      floatingActionButton: Material(
        color: colors.textPrimary,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        elevation: 0,
        child: InkWell(
          onTap: () => _onAddPosition(context),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.add,
              color: colors.surfaceCard,
              size: 26,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ContentStateWidget(
        child: RefreshIndicator(
          color: colors.accentBlue,
          backgroundColor: colors.surfaceCard,
          onRefresh: notifier.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HomeAppBar(onSettings: notifier.openSettings),
                    if (state.quoteError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.pageHorizontal,
                          0,
                          AppDimens.pageHorizontal,
                          AppDimens.sp8,
                        ),
                        child: Material(
                          color: colors.surfaceCard,
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusLg),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              state.quoteError!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                            ),
                            trailing: TextButton(
                              onPressed: notifier.refresh,
                              child: Text('retry'.tr()),
                            ),
                          ),
                        ),
                      ),
                    if (summary != null) ...[
                      PortfolioHeroSection(
                        summary: summary,
                        chartValues: chartValues,
                        periodPnlAbsolute: periodPnl.absolute,
                        periodPnlPercent: periodPnl.percent,
                      ),
                      const SizedBox(height: AppDimens.sp16),
                      TimeRangeSelector(
                        selected: state.selectedRange,
                        onSelected: notifier.selectTimeRange,
                      ),
                      const SizedBox(height: AppDimens.sectionGap),
                      PortfolioQaEntryCard(
                        onTap: notifier.openAssistant,
                      ),
                      AssistantModeChips(
                        onModeTap: (mode) => notifier.openAssistant(mode: mode),
                      ),
                      PositionsSection(
                        valuations: displayValuations,
                        onPositionTap: notifier.openPositionDetail,
                        onDeletePosition: (valuation) =>
                            notifier.deletePositionsForTicker(
                              valuation.position.ticker,
                            ),
                        actionLabel: hasMorePositions
                            ? (state.showAllPositions
                                ? 'view_less'.tr()
                                : 'view_all'.tr())
                            : null,
                        onAction: hasMorePositions
                            ? notifier.togglePositionsExpanded
                            : null,
                      ),
                      if (isBenchmarkAllowed)
                        BenchmarkComparisonCard(
                          portfolioPercent: periodPnl.percent,
                          benchmarkPoints: filteredBenchmark,
                        )
                      else
                        const BenchmarkLockedCard(),
                      ClosedPositionsEntryCard(
                        count: state.closedPositionsCount,
                        onTap: notifier.openClosedPositions,
                      ),
                      if (valuations.isNotEmpty)
                        PnlDistributionCard(valuations: valuations),
                      const SizedBox(height: 88),
                    ] else
                      HomeEmptyState(
                        onAddPosition: () => _onAddPosition(context),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
