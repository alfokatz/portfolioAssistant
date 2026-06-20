import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class AuthWarmBackground extends StatelessWidget {
  const AuthWarmBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.customColors.background,
      child: child,
    );
  }
}
