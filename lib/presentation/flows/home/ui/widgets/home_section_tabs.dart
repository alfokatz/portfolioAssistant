import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';

enum HomeSection { assets, insights }

/// Selector Activos / Insights: el control segmentado de la app
/// ([SegmentedChoice]), con un único indicador que se desliza de una opción
/// a la otra.
class HomeSectionTabs extends StatelessWidget {
  const HomeSectionTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final HomeSection selected;
  final ValueChanged<HomeSection> onSelected;

  static const slideDuration = SegmentedChoice.slideDuration;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageHorizontal),
      child: SegmentedChoice<HomeSection>(
        indicatorKey: const ValueKey('home_section_indicator'),
        selected: selected,
        onChanged: onSelected,
        options: [
          (value: HomeSection.assets, label: 'home_tab_assets'.tr()),
          (value: HomeSection.insights, label: 'home_tab_insights'.tr()),
        ],
      ),
    );
  }
}
