import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class PositionPrimaryButton extends StatelessWidget {
  const PositionPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.textPrimary,
          foregroundColor: colors.surfaceCard,
          disabledBackgroundColor: colors.textPrimary.withValues(alpha: 0.4),
          disabledForegroundColor: colors.surfaceCard.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
        ),
        child: loading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.surfaceCard,
                ),
              )
            : Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.surfaceCard,
                      fontWeight: FontWeight.w600,
                    ),
              ),
      ),
    );
  }
}
