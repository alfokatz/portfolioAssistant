import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';

/// Cuerpo de carga para pantallas GenUI.
class GenUiFlowLoadingBody extends StatelessWidget {
  const GenUiFlowLoadingBody({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF2979FF)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AnalysisColors.textSecondary),
          ),
        ],
      ),
    );
  }
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AnalysisColors.loss,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AnalysisColors.textPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AnalysisColors.textPrimary,
                side: const BorderSide(color: AnalysisColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
