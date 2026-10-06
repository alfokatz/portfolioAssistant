import 'package:flutter/animation.dart';

/// El ritmo de la espera de Porty en el chat (el que tenía el orbe que
/// usábamos antes): un ciclo de [period] con la onda de [wave]. Lo usa el
/// pulso de `PortyThinkingStyle.pulse` en `PortyAvatar`.
abstract final class PortyBreath {
  /// Un ciclo completo (inhala + exhala).
  static const period = Duration(milliseconds: 3600);

  /// 0 → 1 → 0 a lo largo de un ciclo, con ease in-out sinusoidal en cada
  /// mitad (la curva del orbe).
  static double wave(double t) =>
      Curves.easeInOutSine.transform(t < 0.5 ? t * 2 : 2 - t * 2);
}
