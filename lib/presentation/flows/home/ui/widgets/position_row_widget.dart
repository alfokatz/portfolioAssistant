import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/charts/sparkline_chart.dart';

class PositionRowWidget extends StatelessWidget {
  final PositionValuation valuation;
  final VoidCallback? onDetailTap;

  const PositionRowWidget({
    super.key,
    required this.valuation,
    this.onDetailTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final pnl = valuation.pnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';
    final sparkline = HomeChartUtils.sparklineFromPrices(
      purchasePrice: valuation.position.purchasePrice,
      currentPrice: valuation.currentPrice,
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valuation.position.ticker,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PortfolioColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'position_shares'.tr(
                    namedArgs: {
                      'count': valuation.position.quantity.toString(),
                    },
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PortfolioColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          SparklineChart(
            values: sparkline,
            isPositive: pnl >= 0,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(valuation.marketValue),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '$sign${currency.format(pnl)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.pnlColor(pnl),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          if (onDetailTap != null) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: PortfolioColors.textSecondary,
            ),
          ],
        ],
      ),
    );

    if (onDetailTap == null) return content;

    return InkWell(onTap: onDetailTap, child: content);
  }
}
