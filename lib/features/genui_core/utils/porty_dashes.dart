/// Porty no escribe con rayas (—), el guion largo típico de los textos
/// generados: en la respuesta del modelo se cambian por una coma (o se
/// borran al principio o al final de un texto). El prompt ya lo pide; esto
/// cubre lo que se escape.
///
/// Se aplica sobre el JSON A2UI crudo: la raya no es sintaxis de JSON, así
/// que solo toca el contenido de los textos. Los rangos con guion corto
/// ("5–10", "3–9 nov") no se tocan; la raya sola que las cards usan para
/// "sin dato" la pone la app, no el modelo.
abstract final class PortyDashes {
  static final _dash = RegExp(r'[ \t]*[—―][ \t]*|[ \t]+–[ \t]+');

  static String clean(String text) {
    if (!text.contains('—') && !text.contains('―') && !text.contains(' – ')) {
      return text;
    }
    return text.replaceAllMapped(_dash, (m) {
      final before = m.start > 0 ? text[m.start - 1] : '';
      final after = m.end < text.length ? text[m.end] : '';
      // Al principio o al final de un texto (o de un renglón): se borra.
      if (before.isEmpty || before == '"' || before == '\n') return '';
      if (after.isEmpty || after == '"' || after == '\n') return '';
      // Pegada a un signo ("datos —, y"): el signo ya separa.
      if ('.,;:!?)'.contains(after)) return '';
      return ', ';
    });
  }
}
