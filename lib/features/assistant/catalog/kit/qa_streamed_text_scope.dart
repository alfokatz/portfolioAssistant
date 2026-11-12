import 'package:flutter/widgets.dart';

/// Lo que la vista previa del streaming ya le mostró al usuario de la
/// respuesta de una surface (tipeado palabra por palabra, ver
/// `StreamingTypewriter`). Con eso, el `QaAnswerText` de la respuesta
/// final sigue tipeando desde donde iba la vista previa, sin volver a
/// empezar ni saltar al texto completo.
class QaStreamedTextScope extends InheritedWidget {
  const QaStreamedTextScope({
    super.key,
    required this.text,
    required super.child,
  });

  /// El texto que la vista previa llegó a revelar (null sin streaming).
  final String? text;

  /// Cuántos caracteres de [answer] ya se vieron en la vista previa: el
  /// typewriter de la respuesta final arranca ahí.
  static int revealedChars(BuildContext context, String answer) => revealedIn(
    context.dependOnInheritedWidgetOfExactType<QaStreamedTextScope>()?.text,
    answer,
  );

  /// [revealedChars] sin contexto. Se compara sin espacios ni saltos de
  /// línea: la vista previa parte en párrafos un texto a medias y la
  /// respuesta final, el texto entero, y pueden cortar distinto.
  ///
  /// - La respuesta empieza con lo revelado → sigue desde ahí.
  /// - Lo revelado ya incluye el principio de la respuesta (el control de
  ///   calidad sacó una oración del comienzo) → sigue desde lo que coincide.
  /// - Si no (respuesta reescrita), 0: se tipea de nuevo.
  static int revealedIn(String? shown, String answer) {
    if (shown == null || shown.trim().isEmpty || answer.trim().isEmpty) {
      return 0;
    }
    final revealed = _strip(shown);
    final finalText = _strip(answer);
    // Un pedazo del principio de la respuesta para ubicarla en lo revelado
    // (más corto si se reveló poco).
    var anchorLength = finalText.length < 12 ? finalText.length : 12;
    if (revealed.length < anchorLength) anchorLength = revealed.length;
    final anchor = finalText.substring(0, anchorLength);
    final at = revealed.indexOf(anchor);
    if (at < 0) return 0;
    var same = 0;
    while (same < finalText.length &&
        at + same < revealed.length &&
        finalText.codeUnitAt(same) == revealed.codeUnitAt(at + same)) {
      same++;
    }
    return _indexAfter(answer, same);
  }

  static final _space = RegExp(r'\s');

  static String _strip(String s) => s.replaceAll(_space, '');

  /// El índice de [text] justo después de sus primeros [count] caracteres
  /// que no son espacio (o el largo entero si los cubre todos).
  static int _indexAfter(String text, int count) {
    if (count <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (_space.hasMatch(text[i])) continue;
      seen++;
      if (seen == count) {
        // Los espacios que siguen ya "se vieron" con la palabra.
        var end = i + 1;
        while (end < text.length && _space.hasMatch(text[end])) {
          end++;
        }
        return end;
      }
    }
    return text.length;
  }

  @override
  bool updateShouldNotify(QaStreamedTextScope oldWidget) =>
      text != oldWidget.text;
}
