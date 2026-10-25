/// El nombre de Porty en lo que se dicta por voz.
///
/// El reconocimiento del sistema no conoce "Porty" (no hay forma de
/// enseñarle palabras): lo escribe "porti", "portí" o, casi siempre, "por
/// ti". Las variantes de una palabra no existen en castellano y se corrigen
/// siempre. "Por ti" sí existe ("lo hice por ti"), así que se corrige solo
/// donde se lo está nombrando:
///
/// - al empezar: "Por ti, ¿cuánto tengo?" / "Por ti cuánto tengo…";
/// - al empezar otra oración: "Hola. Por ti, …";
/// - después de un saludo: "Hola por ti", "Che por ti", "Buen día por ti";
/// - entre comas o al final después de una coma: "Mirá, por ti, …",
///   "¿Cuánto tengo, por ti?";
/// - "gracias por ti" al final.
abstract final class PortyNameFix {
  static const name = 'Porty';

  /// "porti", "portí", "pórti", "porty", "portie": nunca son otra cosa.
  static final _oneWord = RegExp(
    r'(?<!\p{L})p[oó]rt(?:[ií]|y|ie)(?!\p{L})',
    caseSensitive: false,
    unicode: true,
  );

  static const _porTi = r'por\s+t[ií](?!\p{L})';

  static const _greetings =
      r'hola|che|hey|ey|oye|buenas|buen\s+d[ií]a|buenos\s+d[ií]as|'
      r'buenas\s+tardes|buenas\s+noches|dale|bueno|mir[aá]|ok|okay|'
      r'perd[oó]n|disculp[aá]';

  static final _named = [
    // Al principio, o al principio de otra oración (con ¿ o ¡ delante).
    RegExp(
      '(?<=(?:^|[.!?…]\\s+)[¿¡]?)$_porTi',
      caseSensitive: false,
      unicode: true,
    ),
    // Después de un saludo.
    RegExp(
      '(?<=(?<!\\p{L})(?:$_greetings)[,\\s]+)$_porTi',
      caseSensitive: false,
      unicode: true,
    ),
    // Entre comas, o después de una coma al final.
    RegExp(
      '(?<=,\\s*)$_porTi(?=\\s*,|\\s*[.!?…]*\\s*\$)',
      caseSensitive: false,
      unicode: true,
    ),
    // "Gracias por ti" al final.
    RegExp(
      '(?<=(?<!\\p{L})gracias[,\\s]+)$_porTi(?=\\s*[.!?…]*\\s*\$)',
      caseSensitive: false,
      unicode: true,
    ),
  ];

  static String fix(String text) {
    var out = text.replaceAll(_oneWord, name);
    for (final pattern in _named) {
      out = out.replaceAll(pattern, name);
    }
    return out;
  }
}
