import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children:
            ChartTimeRange.values.map((range) {
              final isActive = range == selected;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(range),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            isActive
                                ? colors.accentWarm.withValues(alpha: 0.14)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        range.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color:
                              isActive
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
