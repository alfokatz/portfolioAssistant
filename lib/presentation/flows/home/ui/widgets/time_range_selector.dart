import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';

class TimeRangeSelector extends StatelessWidget {
  final ChartTimeRange selected;
  final ValueChanged<ChartTimeRange> onSelected;

  const TimeRangeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: ChartTimeRange.values.map((range) {
          final isActive = range == selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: isActive
                    ? PortfolioColors.accentBlue
                    : PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => onSelected(range),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Text(
                      range.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? PortfolioColors.textPrimary
                            : PortfolioColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
