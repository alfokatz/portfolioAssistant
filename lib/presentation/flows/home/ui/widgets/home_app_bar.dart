import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class HomeAppBar extends StatelessWidget {
  final VoidCallback? onSettings;

  const HomeAppBar({super.key, this.onSettings});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        children: [
          Text(
            'app_name'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: -0.1,
                ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            tooltip: 'settings_title'.tr(),
            icon: Icon(
              Icons.person_outline_rounded,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
