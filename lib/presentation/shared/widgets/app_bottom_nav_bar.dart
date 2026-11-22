import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

/// En el orden de las ramas del shell (`app_router`) y de la barra.
///
/// Con el brief y el feed prendidos (`daily_brief` + pieza `feed`) son cuatro
/// pestañas: Inicio · Noticias · Porty · Metas. Es el orden de las ramas, y
/// deja a Porty tercero, entre Noticias y Metas, en el centro de la mano.
/// Perfil/Ajustes sale de la barra: es el botón redondo de la Home y una ruta
/// push (la rama [settings] queda oculta). Con el interruptor apagado, [news]
/// no se dibuja y la barra queda como siempre: Inicio · Porty · Metas · Ajustes.
enum AppNavDestination { home, news, assistant, goals, settings }

/// Floating pill nav bar used to move between the app's main sections.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.current,
    required this.onSelect,
    this.showNews = false,
    this.newsBadge = false,
  });

  final AppNavDestination current;
  final ValueChanged<AppNavDestination> onSelect;

  /// La pestaña Noticias (detrás del interruptor `daily_brief`).
  final bool showNews;

  /// Punto de "hay algo nuevo" en Noticias (brief o notas sin ver).
  final bool newsBadge;

  static const _items = [
    (
      destination: AppNavDestination.home,
      icon: Icons.home_rounded,
      porty: false,
      labelKey: 'nav_home',
    ),
    (
      destination: AppNavDestination.news,
      icon: Icons.article_outlined,
      porty: false,
      labelKey: 'nav_news',
    ),
    (
      destination: AppNavDestination.assistant,
      // Porty en una sola tinta, con el color de la pestaña.
      icon: null,
      porty: true,
      labelKey: 'nav_assistant',
    ),
    (
      destination: AppNavDestination.goals,
      icon: Icons.flag_rounded,
      porty: false,
      labelKey: 'nav_goals',
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
                if (showNews
                    ? item.destination != AppNavDestination.settings
                    : item.destination != AppNavDestination.news)
                  _NavItem(
                    badge:
                        newsBadge && item.destination == AppNavDestination.news,
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

/// El ícono de una pestaña con, si hace falta, el punto terracota de "hay algo
/// nuevo" (8 px, con un aro del color de la barra para despegarlo del ícono).
class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    super.key,
    required this.icon,
    required this.color,
    required this.badge,
    required this.badgeColor,
    required this.ring,
  });

  final IconData icon;
  final Color color;
  final bool badge;
  final Color badgeColor;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: AppDimens.iconMd, color: color);
    if (!badge) return glyph;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        glyph,
        Positioned(
          top: 1,
          right: -3,
          child: Container(
            key: const Key('nav_news_badge'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 1.5),
            ),
          ),
        ),
      ],
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
    this.badge = false,
  });

  final bool badge;
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
      child: Semantics(
        selected: widget.selected,
        // "Noticias, hay novedades": el punto no se lee solo.
        value: widget.badge ? 'nav_news_new'.tr() : null,
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
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
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
                            : _BadgedIcon(
                              key: ValueKey(widget.selected),
                              icon: widget.icon!,
                              color: color,
                              badge: widget.badge,
                              badgeColor: widget.colors.accentWarm,
                              ring: widget.colors.surfaceCard,
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
      ),
    );
  }
}
