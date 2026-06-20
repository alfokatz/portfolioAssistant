import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  static const _height = 52.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _height,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: PortfolioColors.textPrimary,
          disabledBackgroundColor:
              PortfolioColors.textPrimary.withValues(alpha: 0.35),
          foregroundColor: PortfolioColors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: PortfolioColors.surfaceCard,
                ),
              )
            : Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.surfaceCard,
                      fontWeight: FontWeight.w600,
                    ),
              ),
      ),
    );
  }
}
