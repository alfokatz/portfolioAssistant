import 'package:flutter/widgets.dart';

/// Canal para que una card del catálogo dispare la próxima pregunta del
/// usuario ("Ver noticias de NVDA", tocar un ticker de una lista…).
///
/// La provee la pantalla del asistente alrededor de cada surface y la
/// implementa con el mismo camino que las sugerencias iniciales (auto-typing
/// + envío), así un follow-up se ve y se cobra exactamente igual que una
/// pregunta escrita. No usa los `UserActionEvent` de genui a propósito: en
/// este servicio esos eventos van al camino de "repair" de la última
/// surface, no a un turno nuevo.
///
/// Fuera de la pantalla (tests aislados) no hay scope y las cards muestran
/// sus acciones deshabilitadas.
class QaFollowUpScope extends InheritedWidget {
  const QaFollowUpScope({
    super.key,
    required this.onFollowUp,
    required super.child,
  });

  final ValueChanged<String> onFollowUp;

  static ValueChanged<String>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<QaFollowUpScope>()?.onFollowUp;

  @override
  bool updateShouldNotify(QaFollowUpScope oldWidget) => false;
}
