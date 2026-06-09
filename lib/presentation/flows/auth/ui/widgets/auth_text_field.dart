import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Campo de texto estilizado para formularios de autenticación.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
    this.autocorrect = true,
  });

  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final bool autocorrect;

  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      autocorrect: autocorrect,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: PortfolioColors.textPrimary,
          ),
      cursorColor: PortfolioColors.accentBlue,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: PortfolioColors.textSecondary,
            ),
        filled: true,
        fillColor: PortfolioColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(
                prefixIcon,
                color: PortfolioColors.textSecondary,
                size: 22,
              )
            : null,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: PortfolioColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(
            color: PortfolioColors.accentBlue,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(color: PortfolioColors.loss),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: const BorderSide(
            color: PortfolioColors.loss,
            width: 1.4,
          ),
        ),
        errorStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PortfolioColors.loss,
            ),
      ),
    );
  }
}
