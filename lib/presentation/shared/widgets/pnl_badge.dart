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

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$sign${percent.toStringAsFixed(1)}%',
        style: TextStyle(
          color: fg,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
