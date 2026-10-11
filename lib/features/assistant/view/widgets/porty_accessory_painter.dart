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
  static const _gold = Color(0xFFF2C14E);
  static const _goldDark = Color(0xFFD29B2E);
  static const _pink = Color(0xFFE86A8E);
  static const _pinkDark = Color(0xFFC94C72);
  static const _red = Color(0xFFC4533A);
  static const _redDark = Color(0xFF8F3324);
  static const _brightRed = Color(0xFFE0453A);
  static const _cream = Color(0xFFFFF4E6);
  static const _creamDark = Color(0xFFE3D3BF);
  static const _navy = Color(0xFF2E4A7D);
  static const _navyDark = Color(0xFF233961);
  static const _navyLight = Color(0xFF4A6AA3);
  static const _purple = Color(0xFF6A3FC2);
  static const _purpleLight = Color(0xFF8A63DB);
  static const _yellow = Color(0xFFFFD23F);
  static const _cyan = Color(0xFF2EC4E6);
  static const _coral = Color(0xFFFF5C5C);
  static const _brown = Color(0xFFA2693B);
  static const _brownDark = Color(0xFF7A4B27);
  static const _brownBand = Color(0xFF4A2D17);
  static const _leaf = Color(0xFF6FA36B);
  static const _leafDark = Color(0xFF4F7F4C);

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
      case PortyAccessory.cowboyHat:
        _cowboyHat(canvas);
      case PortyAccessory.cap:
        _cap(canvas);
      case PortyAccessory.peakedCap:
        _peakedCap(canvas);
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

  /// Gorro de lana bien puesto: baja hasta arriba de los ojos y envuelve
  /// los costados de la cabeza, con el doblez tejido y un pompón.
  static void _beanie(Canvas canvas) {
    final dome =
        Path()
          ..moveTo(8.2, 22)
          ..cubicTo(7.2, 8, 19, -1.5, 33, -1.5)
          ..cubicTo(47, -1.5, 57.6, 8, 56.8, 21)
          ..quadraticBezierTo(33, 15.5, 8.2, 22)
          ..close();
    canvas.drawPath(dome, _fill(_navy));
    // Pliegues del tejido en la copa.
    final knit = _stroke(_navyDark, 0.9);
    for (final x in [18.0, 25.5, 33.0, 40.5, 48.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + (x - 33) * 0.35, 4 + (x - 33).abs() * 0.12)
          ..quadraticBezierTo(x + (x - 33) * 0.1, 9, x, 13.5),
        knit,
      );
    }
    // Doblez: una banda más clara que sigue la curva del borde.
    final cuff =
        Path()
          ..moveTo(7.6, 14.8)
          ..quadraticBezierTo(33, 7.5, 57.4, 14)
          ..lineTo(56.8, 21.8)
          ..quadraticBezierTo(33, 16.2, 8.2, 22.8)
          ..close();
    canvas.drawPath(cuff, _fill(_navyLight));
    final rib = _stroke(_navy, 1);
    for (var i = 1; i < 10; i++) {
      final x = 7.6 + i * 4.98;
      final t = (x - 7.6) / 49.8;
      final bump = 1 - math.pow(2 * t - 1, 2);
      final top = 14.6 - 3.5 * bump + 0.9;
      final bottom = 22.4 - 2.9 * bump - 0.7;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), rib);
    }
    canvas
      ..drawCircle(const Offset(33, -0.6), 3.3, _fill(_cream))
      ..drawCircle(const Offset(33, -0.6), 3.3, _stroke(_creamDark, 0.7));
  }

  /// Gorro de cumpleaños: violeta con lunares de colores, ribete dorado en
  /// zigzag, pompón dorado con destellos y confeti alrededor.
  static void _partyHat(Canvas canvas) {
    const apex = Offset(36.5, -1.8);
    final cone =
        Path()
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(50, 11.5)
          ..quadraticBezierTo(35, 15, 20.5, 10.5)
          ..close();
    canvas
      ..save()
      ..clipPath(cone)
      ..drawPath(cone, _fill(_purple));
    // Franjas diagonales + lunares.
    final stripe = _stroke(_purpleLight, 2.2);
    for (final y in [1.0, 7.0, 13.0]) {
      canvas.drawLine(Offset(18, y + 6), Offset(54, y - 6), stripe);
    }
    for (final (dot, color) in const [
      (Offset(36, 4.5), _yellow),
      (Offset(31, 9.5), _cyan),
      (Offset(42, 9), _coral),
      (Offset(38.5, 1.6), _cyan),
    ]) {
      canvas.drawCircle(dot, 1.25, _fill(color));
    }
    // Ribete en zigzag dentro del gorro, siguiendo la curva de la base
    // (recortado al gorro: nunca pisa la cara).
    Offset base(double t) {
      const a = Offset(20.5, 10.5);
      const c = Offset(35, 15);
      const b = Offset(50, 11.5);
      final u = 1 - t;
      return a * (u * u) + c * (2 * u * t) + b * (t * t);
    }

    final trim = Path()..moveTo(base(0).dx, base(0).dy - 1);
    for (var i = 1; i <= 12; i++) {
      final p = base(i / 12);
      trim.lineTo(p.dx, p.dy - (i.isOdd ? 3 : 1));
    }
    canvas
      ..drawPath(trim, _stroke(_gold, 1.5))
      ..restore();
    // Pompón con destellos.
    final burst = _stroke(_gold, 0.9);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (i - 2.5) * 0.55;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(apex + dir * 2.8, apex + dir * 4.4, burst);
    }
    canvas.drawCircle(apex, 2.4, _fill(_gold));
    // Confeti.
    for (final (pos, color, angle) in const [
      (Offset(13.5, 4.5), _coral, 0.5),
      (Offset(56, 3), _cyan, -0.6),
      (Offset(59.5, 10.5), _yellow, 0.9),
      (Offset(9.5, 11.5), _cyan, -0.3),
      (Offset(25, -1.5), _yellow, 0.2),
      (Offset(49, -2), _coral, 1.1),
    ]) {
      canvas
        ..save()
        ..translate(pos.dx, pos.dy)
        ..rotate(angle)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 3, height: 1.4),
            const Radius.circular(0.5),
          ),
          _fill(color),
        )
        ..restore();
    }
  }

  /// Sombrero cowboy, marrón: ala ancha que sube en las puntas, copa con
  /// el hundido arriba y cinta oscura.
  static void _cowboyHat(Canvas canvas) {
    final crown =
        Path()
          ..moveTo(20.5, 10)
          ..cubicTo(20, 4, 20.5, -0.5, 24, -1.5)
          ..quadraticBezierTo(28.5, -2.2, 33, 0.8)
          ..quadraticBezierTo(37.5, -2.2, 42, -1.5)
          ..cubicTo(45.5, -0.5, 46, 4, 45.5, 10)
          ..close();
    canvas
      ..drawPath(crown, _fill(_brown))
      // El hundido de la copa.
      ..drawPath(
        Path()
          ..moveTo(33, 1)
          ..quadraticBezierTo(32.6, 3.5, 33, 5.5),
        _stroke(_brownDark, 1),
      )
      ..drawPath(
        Path()
          ..moveTo(20.6, 6)
          ..quadraticBezierTo(33, 8, 45.4, 6)
          ..lineTo(45.5, 9.6)
          ..quadraticBezierTo(33, 11.5, 20.5, 9.6)
          ..close(),
        _fill(_brownBand),
      );
    final brim =
        Path()
          ..moveTo(5, 6.5)
          ..cubicTo(9, 11.5, 19, 9.6, 33, 10.2)
          ..cubicTo(47, 9.6, 57, 11.5, 61, 6.5)
          ..cubicTo(60.5, 12.5, 52, 16.2, 33, 16)
          ..cubicTo(14, 16.2, 5.5, 12.5, 5, 6.5)
          ..close();
    canvas
      ..drawPath(brim, _fill(_brown))
      ..drawPath(
        Path()
          ..moveTo(9, 10.6)
          ..cubicTo(16, 14.4, 50, 14.4, 57, 10.6),
        _stroke(_brownDark, 0.8),
      );
  }

  /// Gorra de frente: copa en gajos, botón arriba y la visera curva sobre
  /// la frente.
  static void _cap(Canvas canvas) {
    final crown =
        Path()
          ..moveTo(11, 14.5)
          ..cubicTo(10.5, 5, 20.5, -0.8, 33, -0.8)
          ..cubicTo(45.5, -0.8, 55.5, 5, 55, 14.5)
          ..close();
    canvas.drawPath(crown, _fill(_red));
    final seam = _stroke(_redDark, 0.9);
    canvas
      ..drawPath(
        Path()
          ..moveTo(33, -0.6)
          ..lineTo(33, 13),
        seam,
      )
      ..drawPath(
        Path()
          ..moveTo(31.5, -0.5)
          ..quadraticBezierTo(21, 3, 19.5, 13.5),
        seam,
      )
      ..drawPath(
        Path()
          ..moveTo(34.5, -0.5)
          ..quadraticBezierTo(45, 3, 46.5, 13.5),
        seam,
      )
      // Escudito de la gorra.
      ..drawCircle(const Offset(33, 7.5), 2.2, _fill(_cream))
      ..drawCircle(const Offset(33, -0.6), 1.5, _fill(_redDark));
    final visor =
        Path()
          ..moveTo(10, 13.5)
          ..quadraticBezierTo(33, 9, 56, 13.5)
          ..quadraticBezierTo(57, 18, 52, 19)
          ..quadraticBezierTo(33, 15.5, 14, 19)
          ..quadraticBezierTo(9, 18, 10, 13.5)
          ..close();
    canvas
      ..drawPath(visor, _fill(_redDark))
      ..drawPath(
        Path()
          ..moveTo(14, 15.8)
          ..quadraticBezierTo(33, 12, 52, 15.8),
        _stroke(_red, 0.8),
      );
  }

  /// El contorno del cuerpo (mismo path que `PortyAvatarPainter`): la
  /// vincha se recorta con él para terminar justo en los bordes.
  static final Path _bodyOutline =
      Path()
        ..moveTo(33, 7)
        ..cubicTo(47, 7, 57, 17, 57, 32)
        ..cubicTo(57, 47, 47, 57, 31, 57)
        ..cubicTo(16, 57, 7, 48, 7, 34)
        ..cubicTo(7, 18, 18, 7, 33, 7)
        ..close();

  /// Gorrita con visera de costado: copa redonda en gajos, botón arriba,
  /// visera hacia la derecha y una costura clara.
  static void _peakedCap(Canvas canvas) {
    final crown =
        Path()
          ..moveTo(11.5, 16)
          ..cubicTo(10.5, 6, 20, -0.5, 32.5, -0.5)
          ..cubicTo(44.5, -0.5, 53.5, 5.5, 53, 15)
          ..quadraticBezierTo(32.5, 9.5, 11.5, 16)
          ..close();
    canvas.drawPath(crown, _fill(_brightRed));
    final seam = _stroke(_red, 0.9);
    canvas
      ..drawPath(
        Path()
          ..moveTo(30.5, -0.3)
          ..quadraticBezierTo(23, 4.5, 22.5, 12.8),
        seam,
      )
      ..drawPath(
        Path()
          ..moveTo(34.5, -0.3)
          ..quadraticBezierTo(41.5, 4.5, 42.5, 12.2),
        seam,
      )
      // Ribete claro en el borde.
      ..drawPath(
        Path()
          ..moveTo(12, 14.8)
          ..quadraticBezierTo(32.5, 8.4, 52.8, 13.8),
        _stroke(_cream, 1.1),
      )
      ..drawCircle(const Offset(32.5, -0.4), 1.6, _fill(_redDark));
    // Visera: nace del borde de la copa (su borde de arriba ES el borde de
    // la copa) y sale por delante hacia la derecha, apenas hacia abajo.
    final visor =
        Path()
          ..moveTo(45, 13.7)
          ..quadraticBezierTo(49.5, 14.2, 53, 15)
          ..cubicTo(57, 14.4, 62, 14, 66, 14.8)
          ..cubicTo(65.4, 16.8, 61.5, 17.8, 55, 17.9)
          ..cubicTo(50.5, 18, 47, 16.8, 45, 13.7)
          ..close();
    canvas
      ..drawPath(visor, _fill(_redDark))
      ..drawPath(
        Path()
          ..moveTo(49, 15.9)
          ..cubicTo(53, 16.6, 59, 16.4, 63.5, 15.6),
        _stroke(_red, 0.8),
      );
  }

  /// Vincha que cruza la frente de lado a lado, arriba de los ojos,
  /// curvada como si envolviera la cabeza, para que el moño o la flor no
  /// queden flotando.
  static void _headband(Canvas canvas, Color color, Color shade) {
    final band =
        Path()
          ..moveTo(4, 16.5)
          ..quadraticBezierTo(33, 24, 62, 15.5);
    canvas
      ..save()
      ..clipPath(_bodyOutline)
      ..drawPath(band, _stroke(color, 3.4))
      ..drawPath(
        band,
        _stroke(shade.withValues(alpha: 0.55), 0.7)..strokeCap = StrokeCap.butt,
      )
      ..restore();
  }

  static void _bow(Canvas canvas) {
    _headband(canvas, _pink, _pinkDark);
    canvas
      ..save()
      ..translate(45, 18)
      ..rotate(-0.3)
      ..scale(0.95);
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
    _headband(canvas, _leaf, _leafDark);
    const center = Offset(19, 18.4);
    // Hojitas a los costados, sobre la vincha.
    for (final (angle, dx) in const [(-0.5, -5.5), (0.5, 5.5)]) {
      canvas
        ..save()
        ..translate(center.dx + dx * 1.15, center.dy + 0.6 + dx * 0.08)
        ..rotate(angle * 0.6)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: 5.5, height: 2.6),
          _fill(_leaf),
        )
        ..restore();
    }
    for (var i = 0; i < 5; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / 5;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * 4,
        3.2,
        _fill(_cream),
      );
    }
    canvas
      ..drawCircle(center, 2.6, _fill(_gold))
      ..drawCircle(center, 2.6, _stroke(_goldDark, 0.6));
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

  // -------------------------------------------------------------------------
  // Cara
  // -------------------------------------------------------------------------

  /// Anteojos de ver: armazón fino y redondo, cristal sin relleno (el ojo
  /// se ve igual que siempre) y un brillo blanco de reflejo.
  static void _glasses(Canvas canvas, Offset leftEye) {
    const r = 5.7;
    final right = leftEye + const Offset(12, 0);
    final frame = _stroke(_ink, 1.1);
    final glare = _stroke(const Color(0xE6FFFFFF), 1);
    for (final c in [leftEye, right]) {
      canvas
        // Reflejo: un arco corto arriba a la derecha y un punto.
        ..drawArc(
          Rect.fromCircle(center: c, radius: r - 1.6),
          -1.35,
          0.9,
          false,
          glare,
        )
        ..drawCircle(c + const Offset(-1.3, -1.2), 0.75, _fill(const Color(0xE6FFFFFF)))
        ..drawCircle(c, r, frame);
    }
    canvas
      ..drawPath(
        Path()
          ..moveTo(leftEye.dx + r - 0.3, leftEye.dy - 1.4)
          ..quadraticBezierTo(
            leftEye.dx + 6,
            leftEye.dy - 2.6,
            right.dx - r + 0.3,
            right.dy - 1.4,
          ),
        frame,
      )
      ..drawLine(
        leftEye + const Offset(-r, -1),
        leftEye + const Offset(-r - 3.4, -2.2),
        frame,
      )
      ..drawLine(
        right + const Offset(r, -1),
        right + const Offset(r + 3.4, -2.2),
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
