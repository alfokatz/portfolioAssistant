import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_feature_row.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';

class OnboardingDashboardPage extends StatelessWidget {
  const OnboardingDashboardPage({super.key, required this.activePage});

  static const pageIndex = 1;

  final int activePage;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    const selectedRange = ChartTimeRange.m1;

    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'onboarding_dashboard_title'.tr(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'onboarding_dashboard_subtitle'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PortfolioColors.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PortfolioColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'onboarding_mock_total_label'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PortfolioColors.textSecondary,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r'$42,190.50',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: PortfolioColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(width: 10),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: PnlBadge(percent: 12.4),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OnboardingMiniLineChart.upward(height: 96),
                const SizedBox(height: 14),
                Row(
                  children: ChartTimeRange.values.map((range) {
                    final isActive = range == selectedRange;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isActive
                                ? PortfolioColors.accentBlue
                                : PortfolioColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            range.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? PortfolioColors.textPrimary
                                  : PortfolioColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  'chart_benchmark_title'.tr(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: PortfolioColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: OnboardingMiniLineChart(
                    height: 56,
                    showArea: false,
                    lineColor: PortfolioColors.accentBlue,
                    values: const [0.7, 0.75, 0.72, 0.8, 0.85, 0.82, 0.9],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _LegendDot(color: PortfolioColors.accentBlue, label: 'Portfolio'),
                    const SizedBox(width: 16),
                    _LegendDot(
                      color: PortfolioColors.benchmarkSp500,
                      label: 'S&P 500',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _PositionRow(
                  ticker: 'AAPL',
                  shares: '12',
                  pnl: r'+$840',
                  pnlColor: colors.pnlColor(1),
                ),
                const SizedBox(height: 8),
                _PositionRow(
                  ticker: 'NVDA',
                  shares: '5',
                  pnl: r'+$1,240',
                  pnlColor: colors.pnlColor(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OnboardingFeatureRow(
            icon: Icons.add_box_outlined,
            title: 'onboarding_dashboard_feature_add_title'.tr(),
            subtitle: 'onboarding_dashboard_feature_add_subtitle'.tr(),
          ),
          const SizedBox(height: 16),
          OnboardingFeatureRow(
            icon: Icons.account_balance_wallet_outlined,
            title: 'onboarding_dashboard_feature_close_title'.tr(),
            subtitle: 'onboarding_dashboard_feature_close_subtitle'.tr(),
          ),
          const SizedBox(height: 16),
          OnboardingFeatureRow(
            icon: Icons.refresh_rounded,
            title: 'onboarding_dashboard_feature_refresh_title'.tr(),
            subtitle: 'onboarding_dashboard_feature_refresh_subtitle'.tr(),
          ),
        ],
      ),
    ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PortfolioColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.ticker,
    required this.shares,
    required this.pnl,
    required this.pnlColor,
  });

  final String ticker;
  final String shares;
  final String pnl;
  final Color pnlColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          ticker,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: PortfolioColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 8),
        Text(
          shares,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PortfolioColors.textSecondary,
              ),
        ),
        const Spacer(),
        Text(
          pnl,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: pnlColor,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
