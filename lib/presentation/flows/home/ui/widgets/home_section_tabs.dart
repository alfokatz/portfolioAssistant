import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

enum HomeSection { assets, insights }

class HomeSectionTabs extends StatelessWidget {
  const HomeSectionTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  static const _tabs = [
    (section: HomeSection.assets, labelKey: 'home_tab_assets'),
    (section: HomeSection.insights, labelKey: 'home_tab_insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageHorizontal),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        ),
        child: Row(
          children: [
            for (final tab in _tabs)
              Expanded(
                child: _TabButton(
                  label: tab.labelKey.tr(),
                  active: selected == tab.section,
                  onTap: () => onSelected(tab.section),
                  colors: colors,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final CustomColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color:
              active
                  ? Color.lerp(colors.surfaceCard, colors.accentWarm, 0.30)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl - 4),
          boxShadow:
              active
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                  : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: active ? colors.textPrimary : colors.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
