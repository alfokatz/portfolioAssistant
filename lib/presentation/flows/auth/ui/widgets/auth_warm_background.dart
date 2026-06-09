import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Fondo suave con gradientes cálidos y formas orgánicas para pantallas de auth.
class AuthWarmBackground extends StatelessWidget {
  const AuthWarmBackground({super.key, required this.child});

  final Widget child;

  static const _warmGlow = Color(0xFFF59E0B);
  static const _softRose = Color(0xFFF472B6);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF12151C),
                Color(0xFF0B0E14),
                Color(0xFF101218),
              ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: _GlowOrb(
            color: _warmGlow.withValues(alpha: 0.14),
            size: 260,
          ),
        ),
        Positioned(
          bottom: 120,
          left: -90,
          child: _GlowOrb(
            color: PortfolioColors.accentBlue.withValues(alpha: 0.12),
            size: 220,
          ),
        ),
        Positioned(
          top: 180,
          left: -40,
          child: _GlowOrb(
            color: _softRose.withValues(alpha: 0.07),
            size: 160,
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _SoftBlobPainter()),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _SoftBlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = PortfolioColors.accentBlue.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.48,
        size.width * 0.55,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.68,
        size.width * 0.9,
        size.height * 0.52,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
