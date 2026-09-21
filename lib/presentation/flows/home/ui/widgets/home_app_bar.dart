import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class HomeAppBar extends StatelessWidget {
  const HomeAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        'app_name'.tr(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: -0.1,
            ),
      ),
    );
  }
}
