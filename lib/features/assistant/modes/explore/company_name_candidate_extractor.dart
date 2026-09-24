/// Extrae de texto libre el candidato más probable a nombre de compañía,
/// para pasárselo a `CompanyTickerResolver` (Finnhub `/search`, que tolera
/// texto ruidoso — no hace falta ser exacto acá).
abstract final class CompanyNameCandidateExtractor {
  static final _capitalizedRun = RegExp(
    r'\b[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+(?:\s+[A-ZÁÉÍÓÚÑ][a-záéíóúñ]+){0,2}\b',
  );

  static const _leadingStopWords = {
    'Que', 'Como', 'Cual', 'Cuando', 'Donde', 'Por', 'Para',
    'What', 'How', 'When', 'Where', 'Why', 'Is', 'Are', 'Tell', 'Show',
  };

  static const _connectorWords = {
    'que', 'como', 'esta', 'esto', 'para', 'con', 'sin', 'las', 'los', 'del',
    'noticias', 'noticia', 'acciones', 'accion', 'precio', 'cotizacion',
    'hoy', 'reciente', 'recientes', 'ultimas', 'ultimo', 'mercado', 'dia',
    'news', 'about', 'stock', 'price', 'the', 'and', 'for',
  };

  /// Prefiere una corrida de palabras capitalizadas ("Nvidia", "Johnson
  /// Johnson") — así se escriben los nombres de marca aun en mitad de una
  /// oración en minúscula. Si no hay ninguna (mensaje todo en minúscula,
  /// "noticias de apple"), cae a probar el mensaje entero menos conectores.
  /// `null` si no queda ningún candidato razonable.
  static String? extract(String message) {
    final capitalized =
        _capitalizedRun
            .allMatches(message)
            .map((m) => m.group(0)!)
            .where((w) => !_leadingStopWords.contains(w.split(' ').first))
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (capitalized.isNotEmpty) return capitalized.first;

    final words =
        message
            .split(RegExp(r'\s+'))
            .map((w) => w.replaceAll(RegExp(r'[^\wÀ-ÿ]'), ''))
            .where((w) => w.length >= 3 && !_connectorWords.contains(w.toLowerCase()))
            .toList();
    return words.isEmpty ? null : words.join(' ');
  }
}
