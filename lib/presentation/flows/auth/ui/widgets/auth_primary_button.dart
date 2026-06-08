import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Botón primario de acción con resplandor azul para pantallas de auth.
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

  static const _radius = 12.0;
  static const _height = 52.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: PortfolioColors.accentBlue.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: _height,
        child: FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: PortfolioColors.accentBlue,
            disabledBackgroundColor:
                PortfolioColors.accentBlue.withValues(alpha: 0.5),
            foregroundColor: PortfolioColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
            elevation: 0,
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PortfolioColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PortfolioColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
        ),
      ),
    );
  }
}
