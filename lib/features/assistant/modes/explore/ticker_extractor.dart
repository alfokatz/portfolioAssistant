/// Extrae símbolos de ticker explícitos del mensaje del usuario (ej. AAPL, NVDA).
abstract final class TickerExtractor {
  static const maxTickers = 3;

  static const _stopWords = {
    'I',
    'A',
    'EL',
    'LA',
    'YO',
    'QUE',
    'COMO',
    'ESTA',
    'ESTO',
    'ESO',
    'ESA',
    'LOS',
    'LAS',
    'DEL',
    'POR',
    'CON',
    'SIN',
    'THE',
    'AND',
    'FOR',
    'HOW',
    'IS',
    'ARE',
    'HOY',
    'DIA',
    'MES',
    'SEMANA',
    'MERCADO',
    'MARKET',
  };

  static final _pureTickerPattern = RegExp(r'^[A-Z]{1,5}$');

  /// Alias retrocompatible: solo símbolos ASCII en mayúsculas.
  static List<String> extractTickers(String message) =>
      extractSymbolTickers(message);

  static List<String> extractSymbolTickers(String message) {
    final seen = <String>{};
    final result = <String>[];

    for (final raw in message.split(RegExp(r'\s+'))) {
      final token = _normalizeTickerToken(raw);
      if (token == null || _stopWords.contains(token)) continue;
      if (seen.add(token)) {
        result.add(token);
        if (result.length >= maxTickers) break;
      }
    }

    return result;
  }

  /// Acepta solo tokens cuyo texto completo (sin puntuación periférica) es
  /// ASCII mayúsculas de 1–5 letras. Evita tomar la "C" de "¿Cómo?".
  static String? _normalizeTickerToken(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'^[^A-Za-z\$]+|[^A-Za-z\$]+$'), '');
    if (!_pureTickerPattern.hasMatch(trimmed)) return null;
    return trimmed;
  }
}
