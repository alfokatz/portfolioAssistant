import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Gráfico decorativo de barras al pie de la pantalla de auth.
class AuthFooterDecoration extends StatelessWidget {
  const AuthFooterDecoration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: CustomPaint(
        painter: _BarChartPainter(),
        size: const Size(double.infinity, 72),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  static const _barHeights = [0.35, 0.55, 0.42, 0.72, 0.48, 0.65, 0.38, 0.58];

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 8;
    const gap = 6.0;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final maxHeight = size.height * 0.85;

    for (var i = 0; i < barCount; i++) {
      final barHeight = maxHeight * _barHeights[i];
      final left = i * (barWidth + gap);
      final top = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(3),
      );

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            PortfolioColors.accentBlue.withValues(alpha: 0.08),
            PortfolioColors.accentBlue.withValues(alpha: 0.35),
          ],
        ).createShader(Rect.fromLTWH(left, top, barWidth, barHeight));

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
