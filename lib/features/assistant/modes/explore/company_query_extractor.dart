/// Extrae una consulta de búsqueda de empresa desde lenguaje natural.
abstract final class CompanyQueryExtractor {
  static const _phraseNoise = [
    'como le fue a la accion de',
    'como le fue a la accion',
    'como le fue la accion de',
    'como le fue al',
    'como le fue',
    'como esta la accion de',
    'como estan las acciones de',
    'como esta el precio de',
    'como estan',
    'como esta',
    'como fue',
    'precio de la accion de',
    'precio de las acciones de',
    'precio de la accion',
    'precio de',
    'cotizacion de',
    'cotizacion',
    'acciones de la empresa',
    'acciones de',
    'accion de la empresa',
    'accion de',
    'la accion de',
    'el precio de',
    'esta semana',
    'este mes',
    'ultimos 7 dias',
    'ultimos 30 dias',
    'ultimo ano',
    'en la semana',
    'en el mes',
    'cuentame de',
    'cuentame sobre',
    'cual es el',
    'cual es',
    'que paso con',
    'que paso en',
    'analiza la accion de',
    'analiza',
    'analizar',
    'decime de',
    'decime sobre',
    'informacion de',
    'informacion sobre',
    'noticias de',
    'noticias sobre',
  ];

  static const _stopWords = {
    'a',
    'al',
    'con',
    'de',
    'del',
    'el',
    'en',
    'es',
    'esta',
    'este',
    'fue',
    'ha',
    'la',
    'las',
    'le',
    'lo',
    'los',
    'me',
    'mi',
    'por',
    'que',
    'cual',
    'se',
    'sin',
    'su',
    'te',
    'the',
    'un',
    'una',
    'y',
    'hoy',
    'dia',
    'mes',
    'semana',
    'mercado',
    'market',
  };

  static String? fromMessage(String message) {
    var text = _normalize(message);
    if (text.isEmpty) return null;

    final sortedPhrases = List<String>.from(_phraseNoise)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final phrase in sortedPhrases) {
      text = text.replaceAll(phrase, ' ');
    }

    final words = text
        .split(' ')
        .where((word) => word.length > 1 && !_stopWords.contains(word))
        .toList();

    final query = words.join(' ').trim();
    if (query.length < 2) return null;
    return query;
  }

  static String _normalize(String message) {
    var text = message.toLowerCase();
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      '¿': ' ',
      '?': ' ',
      '!': ' ',
      ',': ' ',
      '.': ' ',
      ';': ' ',
      ':': ' ',
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
