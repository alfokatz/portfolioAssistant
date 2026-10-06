import 'package:flutter/widgets.dart';

/// Sangría del texto de Porty en el chat: el texto arranca al lado de su
/// avatar, pero las cards de la respuesta ocupan todo el ancho. La pone la
/// pantalla del asistente; el texto (`QaAnswerText`) la lee y las cards no.
/// Sin scope (tests, otras pantallas) es 0.
class QaTextIndentScope extends InheritedWidget {
  const QaTextIndentScope({
    super.key,
    required this.indent,
    required super.child,
  });

  final double indent;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QaTextIndentScope>()?.indent ??
      0;

  @override
  bool updateShouldNotify(QaTextIndentScope oldWidget) =>
      indent != oldWidget.indent;
}
