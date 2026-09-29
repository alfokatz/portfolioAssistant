import 'package:flutter/animation.dart';

/// Reloj único de la "respiración" de Porty. El orbe de pensando del chat y
/// el avatar del header respiran a la vez mientras Porty trabaja; si cada
/// uno arrancara su ciclo por su cuenta quedarían desfasados y se leerían
/// como dos animaciones compitiendo. Con este reloj, cualquier controller
/// que arranque con [start] cae en la misma fase que los demás.
abstract final class PortyBreath {
  /// Un ciclo completo (inhala + exhala).
  static const period = Duration(milliseconds: 3600);

  static final _clock = Stopwatch()..start();

  /// Arranca [controller] (con `duration` == [period]) en la fase global,
  /// en loop. Leer su valor con [wave].
  static void start(AnimationController controller) {
    final us = period.inMicroseconds;
    controller.value = (_clock.elapsedMicroseconds % us) / us;
    controller.repeat();
  }

  /// 0 → 1 → 0 a lo largo de un ciclo, con ease in-out sinusoidal en cada
  /// mitad (misma curva que usaba el orbe con `repeat(reverse: true)`).
  static double wave(double t) =>
      Curves.easeInOutSine.transform(t < 0.5 ? t * 2 : 2 - t * 2);
}
