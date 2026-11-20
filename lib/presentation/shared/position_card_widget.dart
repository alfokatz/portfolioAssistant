import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class PositionCardWidget extends StatelessWidget {
  final PositionValuation valuation;
  final VoidCallback? onDelete;

  const PositionCardWidget({
    super.key,
    required this.valuation,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final pnlColor = colors.pnlColor(valuation.pnlAbsolute);
    final sign = valuation.pnlAbsolute >= 0 ? '+' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.smallMargin),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.mediumMargin),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valuation.position.ticker,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${valuation.position.quantity} uds · ${currency.format(valuation.currentPrice)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currency.format(valuation.marketValue),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$sign${currency.format(valuation.pnlAbsolute)} (${valuation.pnlPercent.toStringAsFixed(1)}%)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: pnlColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
