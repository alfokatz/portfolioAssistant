import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/typewriter_text.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class PortfolioQaChatBubble extends StatelessWidget {
  const PortfolioQaChatBubble({super.key, required this.message, this.onTypingComplete});

  final PortfolioQaMessage message;

  /// Mensajes de usuario: se llama una sola vez, cuando el typewriter de
  /// esta burbuja termina de revelarse (ver TypewriterText). Como mensajes
  /// ya existentes no vuelven a montarse en rebuilds posteriores, esto solo
  /// dispara para el mensaje recién agregado, nunca para los previos.
  final VoidCallback? onTypingComplete;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == PortfolioQaRole.user;

    // El usuario mantiene una pill compacta a la derecha — marca claramente
    // "esto lo escribiste vos". La respuesta de Porty no lleva chrome de
    // burbuja: mismo tratamiento que la surface de GenUI (ver
    // PortfolioQaAssistantSurface), texto plano que respira en el fondo en
    // vez de un bloque encerrado — así ambos caminos de respuesta (texto
    // simple y GenUI) se sienten como el mismo lenguaje visual.
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: AppDimens.sp12),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppDimens.sp12,
            ),
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceElevated,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppDimens.radiusLg),
                topRight: const Radius.circular(AppDimens.radiusLg),
                bottomLeft: const Radius.circular(AppDimens.radiusLg),
                bottomRight: const Radius.circular(4),
              ),
            ),
            child: TypewriterText(
              text: message.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PortfolioColors.textPrimary,
                height: 1.5,
              ),
              skipAnimation: message.hasRevealed,
              onComplete: onTypingComplete,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp16),
      child: SelectableText(
        message.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: PortfolioColors.textPrimary,
          height: 1.55,
        ),
      ),
    );
  }
}
