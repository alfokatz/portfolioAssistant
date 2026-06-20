import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class HomeAppBar extends StatelessWidget {
  final VoidCallback? onSettings;

  const HomeAppBar({super.key, this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        children: [
          Text(
            'app_name'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PortfolioColors.textSecondary,
                  letterSpacing: -0.1,
                ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(
              Icons.person_outline_rounded,
              color: PortfolioColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
