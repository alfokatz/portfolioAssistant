import 'dart:math' as math;

/// Chequeos determinísticos sobre el TEXTO que escribe el modelo (no sobre
/// los números de las cards, que la app llena desde las tools):
/// - todo número citado tiene que estar en los datos del turno;
/// - nada de lenguaje de compra/venta;
/// - la frase que acompaña a una card no repite los números de la card.
///
/// Se usa dos veces por turno: como `answerCheck` (si falla, se le pide al
/// modelo que regenere una vez) y como post-proceso (si vuelve a fallar, se
/// sacan las oraciones problemáticas — nunca se muestra un número inventado).
abstract final class AnalysisProseCheck {
  /// Un número citado, con cuántos decimales se escribió y su sufijo de
  /// escala ("3,78T").
  static List<({double value, int decimals, String scale, bool percent})>
  numbersIn(String text) {
    final out = <({double value, int decimals, String scale, bool percent})>[];
    // Miles con punto ("1.234,5") o número simple con coma/punto decimal.
    // Escalas en palabras (escala larga del español: "billón" = 10^12):
    // "3,5 billones", "330 mil millones", "12 millones".
    final re = RegExp(
      r'(?<![\w.,])(\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)\s?'
      r'(%|x|×|billones|bill[oó]n|mil\s+millones|millones|mill[oó]n|[TBMK](?![a-záéíóú]))?',
      caseSensitive: false,
    );
    for (final m in re.allMatches(text)) {
      final raw = m.group(1)!;
      final word = (m.group(2) ?? '').toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final suffix = switch (word) {
        'billones' || 'billón' || 'billon' => 'T',
        'mil millones' => 'B',
        'millones' || 'millón' || 'millon' => 'M',
        _ => word.toUpperCase(),
      };
      final String normalized;
      int decimals;
      if (RegExp(r'^\d{1,3}(\.\d{3})+').hasMatch(raw)) {
        normalized = raw.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = raw.replaceAll(',', '.');
      }
      final dot = normalized.indexOf('.');
      decimals = dot < 0 ? 0 : normalized.length - dot - 1;
      final value = double.tryParse(normalized);
      if (value == null) continue;
      out.add((
        value: value,
        decimals: decimals,
        scale: const {'T', 'B', 'M', 'K'}.contains(suffix) ? suffix : '',
        percent: suffix == '%',
      ));
    }
    return out;
  }

  /// Números de lenguaje llano que no son datos: "2 de cada 3", "los
  /// últimos 4 trimestres", "30 de cada 100", "52 semanas", años.
  static bool _isFraming(double v, int decimals, String scale) {
    if (decimals > 0 || scale.isNotEmpty) return false;
    if (v >= 0 && v <= 10) return true;
    if (const {12, 52, 100, 1000}.contains(v)) return true;
    return v >= 2020 && v <= 2035;
  }

  /// `true` si [n] (tal como se escribió) sale de alguno de [backing].
  static bool isBacked(
    ({double value, int decimals, String scale, bool percent}) n,
    Iterable<double> backing,
  ) {
    if (_isFraming(n.value, n.decimals, n.scale)) return true;
    // Tolerancia de UN paso de la precisión escrita: cubre redondear
    // (11,6 por 11,63; 28 por 27,6) y truncar, que en lenguaje llano es lo
    // natural ("le quedan 27 de cada 100" con un margen de 27,6%). Más un
    // piso relativo por si el modelo redondeó distinto.
    final halfStep = 1.0 * math.pow(10, -n.decimals);
    final candidates = <double>[
      n.value,
      // market_capitalization viene en millones (Finnhub).
      if (n.scale == 'T') n.value * 1e6,
      if (n.scale == 'B') n.value * 1e3,
      if (n.scale == 'M') n.value,
      if (n.scale == 'K') n.value / 1e3,
      // Ratios que el modelo pasa a porcentaje o al revés.
      if (n.scale.isEmpty) n.value / 100,
      if (n.scale.isEmpty) n.value * 100,
    ];
    for (final b in backing) {
      for (final c in candidates) {
        final scaledStep =
            c == n.value ? halfStep : halfStep * (c / n.value).abs();
        final tolerance = math.max(scaledStep, c.abs() * 0.006);
        if ((b - c).abs() <= tolerance + 1e-9) return true;
        // Valor absoluto de una variación ("bajó 1,96%" con dato -1.96).
        if ((b.abs() - c).abs() <= tolerance + 1e-9) return true;
      }
    }
    return false;
  }

  /// Consejo de compra/venta. Apunta a imperativos y recomendaciones, no a
  /// palabras sueltas: "gana 30 de cada 100 dólares que vende" o "la compra
  /// de X" son descripciones, no consejos.
  static final _advice = RegExp(
    r'\b(compr[aá](la|lo|las|los)?|vend[eé](la|lo|las|los)?|compralas?|vendelas?)(?=[\s,.!?;:]|$)'
    r'|\b(te\s+)?(conviene|recomiendo|recomendamos|deber[ií]as?)\s+(comprar|vender|entrar|salir|invertir)'
    r'|\b(buen|mal|mejor)\s+momento\s+(para|de)\s+(comprar|vender|entrar|salir|invertir)'
    r'|\boportunidad\s+de\s+(compra|venta)'
    r'|\bes\s+hora\s+de\s+(comprar|vender|entrar|salir)',
    caseSensitive: false,
  );

  /// Juicios de valuación ("barata", "cara", "sobrevaluada"): sin un dato
  /// comparable en las tools (no hay promedios de sector), no se sostienen.
  static final _valuationJudgment = RegExp(
    r'\b(barat[oa]s?|car[oa]s?\s+(para|frente|comparad)|sobrevaluad[oa]s?|'
    r'sobrevalorad[oa]s?|infravalorad[oa]s?|subvaluad[oa]s?|subvalorad[oa]s?|'
    r'(valuaci[oó]n|precio)\s+atractiv[oa]|(p/e|per)\s+(alto|bajo|elevado|razonable))',
    caseSensitive: false,
  );

  static bool hasValuationJudgment(String text) =>
      _valuationJudgment.hasMatch(text);

  static bool hasAdvice(String text) {
    // "compra"/"vende" sin tilde son 3ra persona: solo cuentan con tilde
    // (imperativo rioplatense) o seguidos de pronombre.
    for (final m in _advice.allMatches(text)) {
      final word = m.group(0)!.toLowerCase();
      if (word == 'compra' || word == 'vende') continue;
      return true;
    }
    return false;
  }

  /// Oraciones de [text] (por puntuación final).
  static List<String> sentences(String text) => [
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+')))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  /// Problemas de una oración: números sin respaldo y/o consejo.
  static List<String> problemsIn(String sentence, Iterable<double> backing) {
    final problems = <String>[];
    final unbacked = [
      for (final n in numbersIn(sentence))
        if (!isBacked(n, backing)) n.value,
    ];
    if (unbacked.isNotEmpty) {
      problems.add(
        'numbers not in the tool results (${unbacked.map(_fmt).join(', ')}) in "$sentence"',
      );
    }
    if (hasAdvice(sentence)) {
      problems.add('buy/sell advice in "$sentence"');
    }
    if (hasValuationJudgment(sentence)) {
      problems.add(
        'cheap/expensive judgment without comparable data in "$sentence" '
        '(describe what the number means instead)',
      );
    }
    return problems;
  }

  /// [text] sin las oraciones que tienen problemas.
  static String clean(String text, Iterable<double> backing) =>
      sentences(text).where((s) => problemsIn(s, backing).isEmpty).join(' ');

  /// Cuántos números de [text] aparecen también en [widgetNumbers] (la
  /// frase que acompaña a una card no debería repetirlos).
  static int repeatedNumbers(String text, Iterable<double> widgetNumbers) {
    var count = 0;
    // "los últimos 30 días", "52 semanas": el período que la card cubre,
    // no un dato que la card muestra — nombrarlo es justo lo que se espera
    // de la intro.
    for (final n in numbersIn(text.replaceAll(_timeSpan, ''))) {
      if (_isFraming(n.value, n.decimals, n.scale)) continue;
      if (isBacked(n, widgetNumbers)) count++;
    }
    return count;
  }

  static final _timeSpan = RegExp(
    r'\b\d+\s*(?:d[ií]as?|semanas?|mes(?:es)?|años?|horas?|trimestres?)\b',
    caseSensitive: false,
  );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}
