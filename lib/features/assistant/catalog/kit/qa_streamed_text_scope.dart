import 'package:flutter/widgets.dart';

/// El texto de Porty que ya se vio mientras la respuesta se escribía
/// (streaming). `QaAnswerText` no vuelve a tipear un texto que el usuario
/// ya leyó: lo muestra entero y sigue con las cards.
class QaStreamedTextScope extends InheritedWidget {
  const QaStreamedTextScope({
    super.key,
    required this.text,
    required super.child,
  });

  final String? text;

  /// Si [answer] ya se mostró completo en la vista previa.
  static bool wasShown(BuildContext context, String answer) {
    final shown =
        context.dependOnInheritedWidgetOfExactType<QaStreamedTextScope>()?.text;
    final trimmed = answer.trim();
    return shown != null && trimmed.isNotEmpty && shown.contains(trimmed);
  }

  @override
  bool updateShouldNotify(QaStreamedTextScope oldWidget) =>
      text != oldWidget.text;
}
