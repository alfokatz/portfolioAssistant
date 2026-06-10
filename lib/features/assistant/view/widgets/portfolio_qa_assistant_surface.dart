import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Burbuja del asistente que renderiza una surface GenUI.
class PortfolioQaAssistantSurface extends StatelessWidget {
  const PortfolioQaAssistantSurface({
    super.key,
    required this.surfaceId,
    required this.surfaceContext,
  });

  final String surfaceId;
  final SurfaceContext surfaceContext;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: PortfolioColors.surfaceCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(14),
            ),
            border: Border.all(
              color: PortfolioColors.textSecondary.withValues(alpha: 0.2),
            ),
          ),
          child: Surface(
            key: ValueKey(surfaceId),
            surfaceContext: surfaceContext,
          ),
        ),
      ),
    );
  }
}
