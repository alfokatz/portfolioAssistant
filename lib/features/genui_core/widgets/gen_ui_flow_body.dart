import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';

/// Cuerpo de carga para pantallas GenUI: Porty pensando, con [message]
/// debajo si la espera se alarga (ver [PortyLoader]).
class GenUiFlowLoadingBody extends StatelessWidget {
  const GenUiFlowLoadingBody({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PortyLoader(message: message);
}

/// Cuerpo de error con botón de reintento para pantallas GenUI.
class GenUiFlowErrorBody extends StatelessWidget {
  const GenUiFlowErrorBody({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: colors.loss,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
