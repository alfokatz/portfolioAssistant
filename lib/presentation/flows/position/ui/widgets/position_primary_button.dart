import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';

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
      child: LoadingButtonContent(
        loading: loading,
        spinnerColor: colors.surfaceCard,
        label: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colors.surfaceCard,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Se ve deshabilitado recién con el spinner; antes solo ignora los
        // toques (ver LoadingButtonContent).
        builder:
            (context, showSpinner, child) => FilledButton(
              onPressed:
                  showSpinner || onPressed == null
                      ? null
                      : loading
                      ? () {}
                      : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: colors.textPrimary,
                foregroundColor: colors.surfaceCard,
                disabledBackgroundColor: colors.textPrimary.withValues(
                  alpha: 0.4,
                ),
                disabledForegroundColor: colors.surfaceCard.withValues(
                  alpha: 0.7,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
              ),
              child: child,
            ),
      ),
    );
  }
}
