import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

enum HomeSection { assets, insights }

/// Selector Activos / Insights: un único indicador que se desliza de una
/// opción a la otra. Antes cada opción animaba su propio fondo por
/// separado, así que a mitad de camino las dos quedaban grises a la vez.
///
/// Control segmentado sobrio: riel gris, indicador del color de las cards
/// con una sombra apenas visible (no un relleno de acento, que competía con
/// la tarjeta del informe y los botones), y la opción activa en negrita.
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

  static const slideDuration = Duration(milliseconds: 220);
  static const _height = 44.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final duration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : slideDuration;
    final selectedIndex = _tabs.indexWhere((t) => t.section == selected);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageHorizontal),
      child: Container(
        height: _height,
        padding: const EdgeInsets.all(_inset),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment:
                  selectedIndex == 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
              child: FractionallySizedBox(
                key: const ValueKey('home_section_indicator'),
                widthFactor: 1 / _tabs.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // En oscuro la card es más oscura que el riel: el
                    // indicador se aclara un poco para despegarse.
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? Color.lerp(
                              colors.surfaceElevated,
                              Colors.white,
                              0.10,
                            )
                            : colors.surfaceCard,
                    borderRadius: BorderRadius.circular(
                      AppDimens.radiusPill - _inset,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final tab in _tabs)
                  Expanded(
                    child: _TabLabel(
                      label: tab.labelKey.tr(),
                      active: selected == tab.section,
                      duration: duration,
                      onTap: () {
                        if (tab.section == selected) return;
                        PortyHapticsService.maybeOf(context)?.selectionTap();
                        onSelected(tab.section);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.active,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final base = Theme.of(context).textTheme.labelLarge!;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        // `onTap` y no `onTapDown`: dentro del scroll de la home, el down
        // recién se confirma al soltar (o a los 100 ms) igual que el tap, y
        // así un scroll que arranca sobre el selector no cambia de pestaña.
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOutCubic,
            style: base.copyWith(
              color: active ? colors.textPrimary : colors.textSecondary,
              fontSize: 14,
              // Peso fijo: interpolar el peso hace "respirar" el ancho del
              // texto durante el cambio. La activa se distingue por color y
              // por el indicador.
              fontWeight: FontWeight.w700,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
