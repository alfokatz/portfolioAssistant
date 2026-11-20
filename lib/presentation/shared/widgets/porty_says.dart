import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Porty hablando fuera del chat, con la forma de su respuesta allá: el
/// avatar con la expresión del momento y su frase suelta al lado (sin
/// burbuja ni caja). Es la cabecera de las pantallas donde Porty acompaña
/// una tarea (agregar una posición, el balance de tus ventas).
///
/// Cuando cambia lo que dice ([messageKey]), la frase nueva entra con un
/// fundido corto; con reduced motion, de una.
class PortySays extends StatelessWidget {
  const PortySays({
    super.key,
    required this.message,
    required this.messageKey,
    this.mood = PortyAvatarState.idle,
    this.footnote,
  });

  /// La frase de Porty (un `Text` o `Text.rich` con [style] como base).
  final Widget message;

  /// Identifica la frase: si cambia, se anima el cambio.
  final Object messageKey;
  final PortyAvatarState mood;

  /// Una línea chica debajo de la frase (un dato que la completa).
  final Widget? footnote;

  static const avatarSize = 44.0;

  /// La voz de Porty: el saludo del login, un punto más chica.
  static TextStyle? style(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: -0.2,
        color: context.customColors.textPrimary,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final footnote = this.footnote;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: PortyAvatar(size: avatarSize, state: mood, animated: true),
        ),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: Padding(
            // La primera línea, a la altura de los ojos de Porty.
            padding: const EdgeInsets.only(top: 9),
            child: Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration:
                    reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                layoutBuilder:
                    (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, if (current != null) current],
                    ),
                child: KeyedSubtree(
                  key: ValueKey(messageKey),
                  child: DefaultTextStyle.merge(
                    style: style(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        message,
                        if (footnote != null) ...[
                          const SizedBox(height: AppDimens.sp6),
                          DefaultTextStyle.merge(
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              height: 1.45,
                            ),
                            child: footnote,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
