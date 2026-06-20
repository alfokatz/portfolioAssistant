import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.cardPaddingLg,
          AppDimens.sp24,
          AppDimens.cardPaddingLg,
          AppDimens.sp24,
        ),
        child: child,
      ),
    );
  }
}
