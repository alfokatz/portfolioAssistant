import 'package:flutter/widgets.dart';

/// Arranca [controller] como lo hace cada widget de "reveal una sola vez" en
/// esta app: `.forward()` cuando anima normalmente, o un salto instantáneo
/// al valor final cuando [skip] es true (ya revelado en un mount anterior, o
/// `MediaQuery.disableAnimationsOf`).
///
/// CRÍTICO: todos los callers invocan esto desde `didChangeDependencies`,
/// es decir, todavía dentro de la fase de build. Setear `controller.value =
/// 1` directamente dispara los status listeners del controller de forma
/// SÍNCRONA, inline con ese llamado — a diferencia de `.forward()`, cuya
/// finalización se dispara después, en la fase de scheduler, que es segura.
/// Si un status listener termina mutando estado (`setState`, un `state =`
/// de Riverpod), dispararlo sincrónicamente acá tira "setState() or
/// markNeedsBuild() called during build".
///
/// Fix: saltar el valor sincrónicamente (así el primer paint ya muestra el
/// contenido totalmente revelado, sin flash) pero desconectando primero
/// [statusListener], y volver a invocarlo manualmente una sola vez desde un
/// `addPostFrameCallback` — el idiom que ya usa esta pantalla para diferir
/// mutaciones de estado fuera de la fase de build.
void startRevealAnimation(
  AnimationController controller, {
  required bool skip,
  required AnimationStatusListener statusListener,
  required bool Function() isMounted,
}) {
  if (!skip) {
    controller.forward();
    return;
  }
  controller.removeStatusListener(statusListener);
  controller.value = 1;
  controller.addStatusListener(statusListener);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (isMounted()) statusListener(AnimationStatus.completed);
  });
}
