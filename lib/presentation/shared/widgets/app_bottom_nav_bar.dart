import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

enum AppNavDestination { home, assistant, settings }

/// Floating pill nav bar used to move between the app's main sections.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final AppNavDestination current;
  final ValueChanged<AppNavDestination> onSelect;

  static const _items = [
    (
      destination: AppNavDestination.home,
      icon: Icons.home_rounded,
      porty: false,
      labelKey: 'nav_home',
    ),
    (
      destination: AppNavDestination.assistant,
      // Porty en una sola tinta, con el color de la pestaña.
      icon: null,
      porty: true,
      labelKey: 'nav_assistant',
    ),
    (
      destination: AppNavDestination.settings,
      icon: Icons.person_outline_rounded,
      porty: false,
      labelKey: 'nav_settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: colors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colors.border),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final item in _items)
                _NavItem(
                  icon: item.icon,
                  porty: item.porty,
                  label: item.labelKey.tr(),
                  selected: current == item.destination,
                  onTap: () => onSelect(item.destination),
                  colors: colors,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.porty,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final IconData? icon;
  final bool porty;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final CustomColors colors;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  /// Caja del avatar: el cuerpo (~70 %) mide lo mismo que los íconos.
  static const _portySize = 28.0;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.selected
            ? widget.colors.textPrimary
            : widget.colors.textSecondary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.86 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Misma altura para todos: los labels quedan alineados.
              SizedBox(
                height: _portySize,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder:
                      (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                  child:
                      widget.porty
                          ? PortyAvatar(
                            key: ValueKey(widget.selected),
                            size: _portySize,
                            palette: PortyAvatarPalette(
                              body: color,
                              features: widget.colors.surfaceCard,
                            ),
                          )
                          : Icon(
                            widget.icon,
                            key: ValueKey(widget.selected),
                            size: AppDimens.iconMd,
                            color: color,
                          ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
