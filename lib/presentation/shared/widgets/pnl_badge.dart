import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
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
        // Mismo formato que el resto de las cifras (coma decimal en
        // español): antes salía "-1.6%" al lado de "56.997,28 $".
        AppNumberFormat.percent(percent),
        style: base?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
