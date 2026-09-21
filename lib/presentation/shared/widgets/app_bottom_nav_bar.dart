import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

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
      labelKey: 'nav_home',
    ),
    (
      destination: AppNavDestination.assistant,
      icon: Icons.auto_awesome_rounded,
      labelKey: 'nav_assistant',
    ),
    (
      destination: AppNavDestination.settings,
      icon: Icons.person_outline_rounded,
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
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final CustomColors colors;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                child: Icon(
                  widget.icon,
                  key: ValueKey(widget.selected),
                  size: AppDimens.iconMd,
                  color: color,
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
