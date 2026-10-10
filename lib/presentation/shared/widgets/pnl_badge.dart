import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class PnlBadge extends StatelessWidget {
  final double percent;
  final bool compact;

  const PnlBadge({
    super.key,
    required this.percent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final isPositive = percent >= 0;
    final bg = isPositive ? colors.profitContainer : colors.lossContainer;
    final fg = colors.pnlColor(percent);
    final sign = isPositive ? '+' : '';

    final base = compact
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.labelMedium;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$sign${percent.toStringAsFixed(1)}%',
        style: base?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
