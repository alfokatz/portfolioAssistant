import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/content_state/content_state_widget.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/ai_insights_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_qa_entry_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/benchmark_comparison_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/home_app_bar.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/closed_positions_entry_card.dart';
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

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final summary = state.summary;

    final filteredHistory = HomeChartUtils.filterHistory(
      state.history,
      state.selectedRange,
    );
    final filteredBenchmark = HomeChartUtils.filterBenchmark(
      state.benchmark,
      state.selectedRange,
    );
    final chartValues = filteredHistory.map((p) => p.totalValue).toList();
    final periodPnl = summary == null
        ? const PeriodPnl(absolute: 0, percent: 0)
        : HomeChartUtils.periodPnl(
            currentValue: summary.totalValue,
            totalCostBasis: summary.totalCostBasis,
          );

    final valuations = summary?.valuations ?? [];
    final displayValuations = state.showAllPositions
        ? valuations
        : valuations.take(5).toList();

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      floatingActionButton: Material(
        color: PortfolioColors.accentBlue,
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        shadowColor: PortfolioColors.accentBlue.withValues(alpha: 0.4),
        child: InkWell(
          onTap: notifier.openAddPosition,
          borderRadius: BorderRadius.circular(14),
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.add,
              color: PortfolioColors.textPrimary,
              size: 28,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: ContentStateWidget(
        child: RefreshIndicator(
          color: PortfolioColors.accentBlue,
          backgroundColor: PortfolioColors.surfaceCard,
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
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Material(
                          color: PortfolioColors.surfaceCard,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              state.quoteError!,
                              style: const TextStyle(
                                color: PortfolioColors.textSecondary,
                                fontSize: 13,
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
                      const SizedBox(height: 16),
                      TimeRangeSelector(
                        selected: state.selectedRange,
                        onSelected: notifier.selectTimeRange,
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: BenchmarkComparisonCard(points: filteredBenchmark),
                      ),
                      const SizedBox(height: 20),
                      PositionsSection(
                        valuations: displayValuations,
                        onClosePosition: notifier.openClosePosition,
                        onDeletePosition: (valuation) =>
                            notifier.deletePositionsForTicker(
                              valuation.position.ticker,
                            ),
                        onViewAll: valuations.length > 5
                            ? notifier.showAllPositions
                            : null,
                      ),
                      ClosedPositionsEntryCard(
                        count: state.closedPositionsCount,
                        onTap: notifier.openClosedPositions,
                      ),
                      if (valuations.isNotEmpty) ...[
                        PnlDistributionCard(valuations: valuations),
                        const SizedBox(height: 20),
                      ],
                      PortfolioQaEntryCard(
                        onTap: notifier.openPortfolioQa,
                      ),
                      AiInsightsSection(onInsightTap: notifier.openGenUiFlow),
                      const SizedBox(height: 88),
                    ] else
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'positions_empty'.tr(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: PortfolioColors.textSecondary,
                                ),
                          ),
                        ),
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
