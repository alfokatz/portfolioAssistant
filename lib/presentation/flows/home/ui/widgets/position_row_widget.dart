import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/charts/sparkline_chart.dart';

class PositionRowWidget extends StatelessWidget {
  final PositionValuation valuation;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;

  const PositionRowWidget({
    super.key,
    required this.valuation,
    this.onTap,
    this.onClose,
    this.onDelete,
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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w600,
                        color: PortfolioColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sign${currency.format(pnl)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.pnlColor(pnl),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            if (onClose != null || onDelete != null) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: PortfolioColors.textSecondary,
                ),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'close') {
                    onClose?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onClose != null)
                    PopupMenuItem(
                      value: 'close',
                      child: Text('position_close_action'.tr()),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'delete'.tr(),
                        style: const TextStyle(color: PortfolioColors.loss),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
