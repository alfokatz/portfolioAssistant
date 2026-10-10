import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Alias del CTA primario compartido para pantallas de auth.
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

  @override
  Widget build(BuildContext context) {
    return PositionPrimaryButton(
      label: label,
      loading: isLoading,
      onPressed: onPressed,
    );
  }
}
