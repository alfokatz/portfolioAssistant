import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/charts/sparkline_chart.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Una posición de la Home. Con [PositionRowWidget.skeleton] es su propio
/// skeleton: mismos paddings y alturas, valores en barras.
class PositionRowWidget extends StatelessWidget {
  final PositionValuation? valuation;
  final VoidCallback? onDetailTap;

  const PositionRowWidget({
    super.key,
    required PositionValuation this.valuation,
    this.onDetailTap,
  });

  const PositionRowWidget.skeleton({super.key})
    : valuation = null,
      onDetailTap = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final valuation = this.valuation;
    final skeleton = valuation == null;
    final pnl = valuation?.pnlAbsolute ?? 0;
    final sign = pnl >= 0 ? '+' : '';

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(
                  valuation?.position.ticker,
                  placeholder: 'AAPL',
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                SkeletonText(
                  skeleton
                      ? null
                      : 'position_shares'.tr(
                        namedArgs: {
                          'count': valuation.position.quantity.toString(),
                        },
                      ),
                  placeholder: '00 acciones',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (skeleton)
            const SkeletonBlock(
              width: SparklineChart.defaultWidth,
              height: SparklineChart.defaultHeight,
              radius: 8,
            )
          else
            SparklineChart(
              values: HomeChartUtils.sparklineFromPrices(
                purchasePrice: valuation.position.purchasePrice,
                currentPrice: valuation.currentPrice,
              ),
              isPositive: pnl >= 0,
            ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SkeletonText(
                skeleton ? null : currency.format(valuation.marketValue),
                animate: true,
                placeholder: '\$0,000.00',
                style: textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              SkeletonText(
                skeleton ? null : '$sign${currency.format(pnl)}',
                animate: true,
                placeholder: '+\$000.00',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.pnlColor(pnl),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // El chevron es de la fila, no un dato: el skeleton lo lleva
          // igual, así las columnas quedan alineadas con las filas reales.
          if (onDetailTap != null || skeleton) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    );

    if (onDetailTap == null) return content;

    return InkWell(
      onTap: () {
        // Haptic y navegación en el mismo frame del tap.
        PortyHapticsService.maybeOf(context)?.selectionTap();
        onDetailTap!();
      },
      child: content,
    );
  }
}
