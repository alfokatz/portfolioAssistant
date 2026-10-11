import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/porty_outfit/domain/porty_outfit.dart';

/// Dibuja los accesorios de Porty en unidades del SVG (cuerpo en x/y
/// 7–57, caja de −4 a 68; ver `PortyAvatarPainter`). Se llama con el canvas
/// ya transformado como el cuerpo, así respiran, se inclinan y saltan con
/// él. Los de la cara se dibujan con la posición de los ojos de cada
/// estado (siguen la mirada y el crossfade).
abstract final class PortyAccessoryPainter {
  static const _ink = Color(0xFF2F3437);
  static const _teal = Color(0xFF3F7F86);
  static const _tealDark = Color(0xFF2F646A);
  static const _tealLight = Color(0xFF8FC1C4);
  static const _gold = Color(0xFFF2C14E);
  static const _goldDark = Color(0xFFD29B2E);
  static const _pink = Color(0xFFE86A8E);
  static const _pinkDark = Color(0xFFC94C72);
  static const _blue = Color(0xFF3E6FB0);
  static const _blueDark = Color(0xFF2D568C);
  static const _red = Color(0xFFC4533A);
  static const _cream = Color(0xFFFFF4E6);

  static Paint _fill(Color color) => Paint()..color = color;

  static Paint _stroke(Color color, double width) =>
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  /// Lo que va sobre la cabeza y en el cuerpo (no sigue a los ojos).
  static void paintBody(Canvas canvas, PortyOutfit outfit) {
    switch (outfit[PortyOutfitSlot.neck]) {
      case PortyAccessory.bowTie:
        _bowTie(canvas);
      default:
        break;
    }
    switch (outfit[PortyOutfitSlot.head]) {
      case PortyAccessory.beanie:
        _beanie(canvas);
      case PortyAccessory.partyHat:
        _partyHat(canvas);
      case PortyAccessory.topHat:
        _topHat(canvas);
      case PortyAccessory.cap:
        _cap(canvas);
      case PortyAccessory.crown:
        _crown(canvas);
      case PortyAccessory.bow:
        _bow(canvas);
      case PortyAccessory.flower:
        _flower(canvas);
      default:
        break;
    }
  }

  /// Lo de la cara, con el ojo izquierdo en [leftEye] (el derecho está 12
  /// unidades a la derecha) y radio de ojo [eyeRadius].
  static void paintFace(
    Canvas canvas,
    PortyOutfit outfit,
    Offset leftEye,
    double eyeRadius,
  ) {
    switch (outfit[PortyOutfitSlot.face]) {
      case PortyAccessory.glasses:
        _glasses(canvas, leftEye);
      case PortyAccessory.sunglasses:
        _sunglasses(canvas, leftEye);
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Cabeza
  // -------------------------------------------------------------------------

  static void _beanie(Canvas canvas) {
    final dome =
        Path()
          ..moveTo(11, 15)
          ..cubicTo(11, 4, 21, -0.5, 33, -0.5)
          ..cubicTo(45, -0.5, 55, 4, 55, 14)
          ..quadraticBezierTo(33, 7, 11, 15)
          ..close();
    canvas.drawPath(dome, _fill(_teal));
    final band =
        Path()
          ..moveTo(9.5, 13.5)
          ..quadraticBezierTo(33, 5, 56.5, 12.5)
          ..lineTo(57, 17.5)
          ..quadraticBezierTo(33, 10.5, 9, 18.5)
          ..close();
    canvas.drawPath(band, _fill(_tealDark));
    final rib = _stroke(_teal, 1.1);
    for (var i = 1; i < 8; i++) {
      final x = 9.5 + i * 5.9;
      // La banda es una curva: cada costilla sigue su altura.
      final t = (x - 9.5) / 47;
      final top = 13.5 - 4.2 * (1 - math.pow(2 * t - 1, 2)) + 0.8;
      canvas.drawLine(Offset(x, top), Offset(x, top + 3.6), rib);
    }
    canvas
      ..drawCircle(const Offset(33, -0.8), 3.2, _fill(_tealLight))
      ..drawCircle(const Offset(32, -1.8), 1.1, _fill(_cream));
  }

  static void _partyHat(Canvas canvas) {
    const apex = Offset(37, -2);
    final cone =
        Path()
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(49, 11)
          ..quadraticBezierTo(35, 14.5, 21.5, 10)
          ..close();
    canvas
      ..save()
      ..clipPath(cone)
      ..drawPath(cone, _fill(_gold));
    final stripe = _stroke(_pink, 2.4);
    for (final y in [2.5, 8.5]) {
      canvas.drawLine(Offset(20, y + 2), Offset(52, y - 2), stripe);
    }
    canvas
      ..restore()
      ..drawCircle(apex, 2.1, _fill(_pink));
  }

  static void _topHat(Canvas canvas) {
    final crown =
        Path()
          ..moveTo(22.5, 9)
          ..lineTo(23.5, -2.5)
          ..quadraticBezierTo(33, -3.8, 42.5, -2.5)
          ..lineTo(43.5, 9)
          ..close();
    canvas
      ..drawPath(crown, _fill(_ink))
      ..drawRect(const Rect.fromLTRB(22.9, 4, 43.1, 7.4), _fill(_red))
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(13.5, 8, 52.5, 12),
          const Radius.circular(2),
        ),
        _fill(_ink),
      );
  }

  static void _cap(Canvas canvas) {
    final visor =
        Path()
          ..moveTo(45, 10.5)
          ..quadraticBezierTo(58, 8.5, 65, 12.5)
          ..quadraticBezierTo(57, 16.5, 46, 15.5)
          ..close();
    canvas.drawPath(visor, _fill(_blueDark));
    final dome =
        Path()
          ..moveTo(12, 15.5)
          ..cubicTo(12, 6, 21, 0.5, 33, 0.5)
          ..cubicTo(44, 0.5, 52, 5.5, 52.5, 13.5)
          ..quadraticBezierTo(33, 8.5, 12, 15.5)
          ..close();
    canvas
      ..drawPath(dome, _fill(_blue))
      ..drawPath(
        Path()
          ..moveTo(33, 1)
          ..quadraticBezierTo(31, 6, 32, 10.5),
        _stroke(_blueDark, 0.9),
      )
      ..drawCircle(const Offset(33, 1), 1.5, _fill(_blueDark));
  }

  static void _crown(Canvas canvas) {
    final crown =
        Path()
          ..moveTo(21, 11)
          ..lineTo(20, 1)
          ..lineTo(26.5, 5.5)
          ..lineTo(33, -2.5)
          ..lineTo(39.5, 5.5)
          ..lineTo(46, 1)
          ..lineTo(45, 11)
          ..quadraticBezierTo(33, 12.5, 21, 11)
          ..close();
    canvas
      ..drawPath(crown, _fill(_gold))
      ..drawPath(crown, _stroke(_goldDark, 0.9))
      ..drawCircle(const Offset(33, 7.5), 1.7, _fill(_red))
      ..drawCircle(const Offset(25.5, 8.5), 1.2, _fill(_teal))
      ..drawCircle(const Offset(40.5, 8.5), 1.2, _fill(_teal));
    for (final tip in const [Offset(20, 1), Offset(33, -2.5), Offset(46, 1)]) {
      canvas.drawCircle(tip, 1.2, _fill(_goldDark));
    }
  }

  static void _bow(Canvas canvas) {
    canvas
      ..save()
      ..translate(45, 9)
      ..rotate(-0.35);
    final left =
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-4, -7, -11, -6, -10, 0)
          ..cubicTo(-11, 6, -4, 7, 0, 0)
          ..close();
    final right =
        Path()
          ..moveTo(0, 0)
          ..cubicTo(4, -7, 11, -6, 10, 0)
          ..cubicTo(11, 6, 4, 7, 0, 0)
          ..close();
    canvas
      ..drawPath(left, _fill(_pink))
      ..drawPath(right, _fill(_pink))
      ..drawLine(const Offset(-3, 0), const Offset(-7.5, 0), _stroke(_pinkDark, 1))
      ..drawLine(const Offset(3, 0), const Offset(7.5, 0), _stroke(_pinkDark, 1))
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 4.6, height: 5.4),
          const Radius.circular(1.8),
        ),
        _fill(_pinkDark),
      )
      ..restore();
  }

  static void _flower(Canvas canvas) {
    const center = Offset(18.5, 11);
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * 4.6,
        3.7,
        _fill(_cream),
      );
    }
    canvas
      ..drawCircle(center, 3, _fill(_gold))
      ..drawCircle(center, 3, _stroke(_goldDark, 0.6));
  }

  // -------------------------------------------------------------------------
  // Cara
  // -------------------------------------------------------------------------

  static void _glasses(Canvas canvas, Offset leftEye) {
    const r = 5.6;
    final right = leftEye + const Offset(12, 0);
    final frame = _stroke(_ink, 1.5);
    final lens = _fill(const Color(0x33FFFFFF));
    for (final c in [leftEye, right]) {
      canvas
        ..drawCircle(c, r, lens)
        ..drawCircle(c, r, frame);
    }
    canvas
      ..drawPath(
        Path()
          ..moveTo(leftEye.dx + r, leftEye.dy - 0.5)
          ..quadraticBezierTo(
            leftEye.dx + 6,
            leftEye.dy - 2,
            right.dx - r,
            right.dy - 0.5,
          ),
        frame,
      )
      ..drawLine(
        leftEye + const Offset(-r, -1),
        leftEye + const Offset(-r - 4, -2.5),
        frame,
      )
      ..drawLine(
        right + const Offset(r, -1),
        right + const Offset(r + 4, -2.5),
        frame,
      );
  }

  static void _sunglasses(Canvas canvas, Offset leftEye) {
    final right = leftEye + const Offset(12, 0);
    final dark = _fill(const Color(0xFF1E2124));
    final shine = _stroke(const Color(0x66FFFFFF), 0.9);
    for (final c in [leftEye, right]) {
      final lens = RRect.fromRectAndCorners(
        Rect.fromCenter(center: c + const Offset(0, 0.6), width: 11, height: 8),
        topLeft: const Radius.circular(1.5),
        topRight: const Radius.circular(1.5),
        bottomLeft: const Radius.circular(4.5),
        bottomRight: const Radius.circular(4.5),
      );
      canvas
        ..drawRRect(lens, dark)
        ..drawLine(
          c + const Offset(-3.2, -1.6),
          c + const Offset(-1.2, -2.6),
          shine,
        );
    }
    final bar = _stroke(const Color(0xFF1E2124), 1.5);
    canvas
      ..drawLine(
        leftEye + const Offset(5.5, -2),
        right + const Offset(-5.5, -2),
        bar,
      )
      ..drawLine(
        leftEye + const Offset(-5.5, -2),
        leftEye + const Offset(-9, -3),
        bar,
      )
      ..drawLine(
        right + const Offset(5.5, -2),
        right + const Offset(9, -3),
        bar,
      );
  }

  // -------------------------------------------------------------------------
  // Cuello
  // -------------------------------------------------------------------------

  static void _bowTie(Canvas canvas) {
    const c = Offset(33, 51.5);
    Path wing(double side) =>
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + side * 8.5, c.dy - 4.6)
          ..quadraticBezierTo(
            c.dx + side * 9.8,
            c.dy,
            c.dx + side * 8.5,
            c.dy + 4.6,
          )
          ..close();
    canvas
      ..drawPath(wing(-1), _fill(_teal))
      ..drawPath(wing(1), _fill(_teal))
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 4.2, height: 5),
          const Radius.circular(1.6),
        ),
        _fill(_tealDark),
      );
  }
}
