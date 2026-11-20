/// El idioma ELEGIDO en la app ('es' | 'en'), legible fuera de un
/// `BuildContext` (el asistente, las tools, el informe semanal).
///
/// Lo fija `MyApp.build` con `context.locale` en cada build (también cuando
/// el usuario cambia de idioma). No usar `Intl.getCurrentLocale()` para
/// esto: easy_localization no fija `Intl.defaultLocale`, así que devuelve
/// el idioma del sistema, no el de la app.
abstract final class AppLanguage {
  static String _code = 'es';

  /// 'es' o 'en'.
  static String get code => _code;

  static bool get isEnglish => _code == 'en';

  /// Normaliza cualquier código ('en', 'en_US', 'es-AR'…) a 'es' | 'en'.
  static String normalize(String languageCode) =>
      languageCode.toLowerCase().startsWith('en') ? 'en' : 'es';

  static void set(String languageCode) => _code = normalize(languageCode);

  /// El idioma en que conviene responder a [text]: el del mensaje si se
  /// nota (palabras frecuentes de cada idioma), si no [fallback] (el de la
  /// app). Un ticker, un número o "ok" no dicen nada: gana la app.
  static String detect(String text, {String? fallback}) {
    final words = RegExp(r"[a-záéíóúñü']+", caseSensitive: false)
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    var es = 0;
    var en = 0;
    for (final w in words) {
      if (_spanish.contains(w)) es++;
      if (_english.contains(w)) en++;
    }
    if (RegExp('[¿¡ñáéíóú]').hasMatch(text)) es += 2;
    if (es == en) return fallback ?? _code;
    return es > en ? 'es' : 'en';
  }

  static const _spanish = {
    'el', 'la', 'los', 'las', 'de', 'del', 'que', 'qué', 'en', 'un', 'una',
    'y', 'es', 'por', 'para', 'con', 'mi', 'mis', 'cuánto', 'cuanto',
    'cómo', 'como', 'tengo', 'quiero', 'está', 'esta', 'sube', 'subió',
    'bajó', 'cartera', 'acciones', 'acción', 'hola', 'gracias', 'me', 'se',
    'lo', 'al', 'pero', 'hoy', 'invertir', 'ahorrar', 'puedo', 'hacer',
    'dónde', 'donde', 'cuál', 'cual', 'sí', 'mes', 'año', 'semana',
  };

  static const _english = {
    'the', 'an', 'of', 'what', 'how', 'is', 'are', 'my', 'i', 'to',
    'in', 'and', 'for', 'with', 'much', 'many', 'did', 'does', 'do', 'it',
    'this', 'that', 'should', 'can', 'want', 'have', "what's", "i'm",
    'portfolio', 'stock', 'stocks', 'hello', 'hi', 'thanks', 'today',
    'invest', 'save', 'where', 'which', 'yes', 'month', 'year', 'week',
    'why', 'show', 'up', 'down', 'buy', 'sell', 'price',
  };
}
