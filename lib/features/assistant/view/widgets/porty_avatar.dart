import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// La marca de Porty: disco terracota con el sparkle en claro. Se probó
/// también sparkle terracota sobre un tinte tenue, pero en light ese disco
/// se funde con el halo de `AppBackgroundGradient` y Porty volvía a verse
/// apagado. Es marca, no fondo (ver "The One Accent Rule" en DESIGN.md).
///
/// Lo usan el header del chat (38 px) y el login (más grande); el sparkle
/// escala con el disco para que se vea igual en cualquier tamaño.
class PortyAvatar extends StatelessWidget {
  const PortyAvatar({super.key, this.size = defaultSize});

  final double size;

  static const defaultSize = 38.0;

  /// Proporción sparkle / disco del avatar original (20 px en 38 px).
  static const _iconRatio = AppDimens.iconMd / defaultSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accentWarm,
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * _iconRatio,
        // En dark el acento es más claro (#E3A472): el sparkle va en el
        // fondo de la app para mantener el contraste.
        color: dark ? colors.background : colors.surfaceCard,
      ),
    );
  }
}
