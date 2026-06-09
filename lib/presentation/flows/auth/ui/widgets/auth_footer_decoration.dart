import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Onda decorativa suave al pie de la pantalla de auth.
class AuthFooterDecoration extends StatelessWidget {
  const AuthFooterDecoration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: CustomPaint(
        painter: _SoftWavePainter(),
        size: const Size(double.infinity, 56),
      ),
    );
  }
}

class _SoftWavePainter extends CustomPainter {
  static const _warmAccent = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final wavePath = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.35,
        size.width * 0.5,
        size.height * 0.55,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.75,
        size.width,
        size.height * 0.4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final wavePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          PortfolioColors.accentBlue.withValues(alpha: 0.12),
          _warmAccent.withValues(alpha: 0.08),
          PortfolioColors.accentBlue.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(wavePath, wavePaint);

    final linePaint = Paint()
      ..color = PortfolioColors.accentBlue.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final linePath = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.35,
        size.width * 0.5,
        size.height * 0.55,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.75,
        size.width,
        size.height * 0.4,
      );

    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
