import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

class LabeledValueRow extends StatelessWidget {
  const LabeledValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.dense = false,
    this.animateValue = false,
  });

  final String label;

  /// `null` muestra una barra de skeleton del alto del valor.
  final String? value;
  final Color? valueColor;
  final bool dense;

  /// Crossfade corto cuando el valor cambia (refresh en el lugar).
  final bool animateValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final labelStyle = dense
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;
    final valueStyle = dense
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: labelStyle?.copyWith(color: colors.textSecondary),
            ),
          ),
          SkeletonText(
            value,
            animate: animateValue,
            style: valueStyle?.copyWith(
              color: valueColor ?? colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
