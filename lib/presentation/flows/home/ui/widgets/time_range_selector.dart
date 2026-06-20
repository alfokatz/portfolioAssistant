import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
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
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: ChartTimeRange.values.map((range) {
          final isActive = range == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(range),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    range.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isActive
                              ? colors.textPrimary
                              : colors.textSecondary,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
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
