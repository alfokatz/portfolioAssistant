import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';

/// Reglas de redacción que comparten el informe semanal y el brief diario
/// (es/en): lo que Porty escribe nunca afirma causas, no aconseja, no usa
/// jerga ni cifras que no estén en los datos, no cita ni repite el consejo
/// de un tercero. Extraídas de `WeeklyReportValidator` sin cambiar su
/// comportamiento (sus tests son la red).
abstract final class ReportProseRules {
  static const _letters = 'A-Za-zÁÉÍÓÚÜÑáéíóúüñ';
  static const _notLetter = '(?<![$_letters])';
  static const _endWord = '(?![$_letters])';

  /// "subió por X", "cayó debido a X": no se afirman causas.
  static final _causal = RegExp(
    // Sin `\b`: en Dart no reconoce "ó" como letra ("subió" nunca cerraba).
    '$_notLetter(subi[oó]|baj[oó]|cay[oó]|repunt[oó]|se\\s+dispar[oó]|'
    'se\\s+desplom[oó]|gan[oó]|perdi[oó]|retrocedi[oó]|avanz[oó])$_endWord'
    '[^.]{0,40}?'
    // "destacado por X" es voz pasiva, no una causa.
    '$_notLetter((?<!(ad|id)[oa]s?\\s)por(?!\\s+ciento)|debido\\s+a|'
    'a\\s+causa\\s+de|gracias\\s+a|'
    'por\\s+culpa\\s+de)$_endWord',
    caseSensitive: false,
  );

  /// Jerga que no se usa (o se explica). "pts" era lo que más confundía.
  static final _jargon = RegExp(
    '$_notLetter(pts|pp|puntos\\s+porcentuales|puntos\\s+b[aá]sicos|'
    'basis\\s+points|exposici[oó]n|rally|sell-?off|bullish|bearish|'
    'outperform\\w*|underperform\\w*)$_endWord',
    caseSensitive: false,
  );

  /// Frases que no dicen nada que el número no diga.
  static final _empty = RegExp(
    'liderando\\s+(el\\s+movimiento|la\\s+suba|la\\s+baja)|'
    'en\\s+terreno\\s+(positivo|negativo)',
    caseSensitive: false,
  );

  /// "recomendó comprar NVDA": repetir el consejo de otro también es dar
  /// un consejo.
  static final _relayedAdvice = RegExp(
    // `\w` no reconoce acentos en Dart ("recomendó").
    r'(recomend[a-záéíóú]*|sugiri[oó]|aconsej[a-záéíóú]*|propuso)\s+'
    r'(a\s+[a-záéíóúñ]+\s+)?'
    r'(comprar|vender|entrar|salir|invertir)',
    caseSensitive: false,
  );

  /// "No hay reportes de resultados": una lista vacía no prueba que algo
  /// no exista.
  static final _absence = RegExp(
    r'no\s+(hay|tiene[ns]?|presenta[n]?|habr[aá])\s+[^.]{0,30}'
    r'(resultados|reportes|ganancias|balances|earnings)',
    caseSensitive: false,
  );

  /// Mencionar la cartera del usuario en un ítem que no la toca.
  static final _mentionsPortfolio = RegExp(
    r'(tu\s+cartera|ten[eé]s|no\s+la\s+ten[eé]s)',
    caseSensitive: false,
  );

  /// ", aunque no tenés LEN en tu cartera": cláusula sobrante, se saca sin
  /// pedir reescritura.
  static final _notHeldClause = RegExp(
    r',?\s*(aunque|pero|y)?\s*no\s+(la|lo|las|los)?\s*ten[eé]s\b[^.]*',
    caseSensitive: false,
  );

  /// "S&P 500" es un nombre, no una cifra.
  static final _sp500 = RegExp(r'S&P\s*500', caseSensitive: false);

  /// Comillas: en lo atribuido a terceros, una cita inventada.
  static final _quotes = RegExp('["“”«»]');

  static final _causalEn = RegExp(
    r'\b(rose|rallied|climbed|jumped|gained|fell|dropped|slid|sank|declined|'
    r'tumbled|lost|moved|surged|soared)\b[^.]{0,40}?'
    r'\b(because\s+of|due\s+to|thanks\s+to|driven\s+by|on\s+the\s+back\s+of|'
    r'as\s+a\s+result\s+of|caused\s+by|after)\b',
    caseSensitive: false,
  );

  static final _jargonEn = RegExp(
    r'\b(pts|pp|percentage\s+points|basis\s+points|bps|exposure|rally|'
    r'sell-?off|bullish|bearish|outperform\w*|underperform\w*)\b',
    caseSensitive: false,
  );

  static final _emptyEn = RegExp(
    r'leading\s+the\s+(move|gains|losses|way)|'
    r'in\s+(positive|negative)\s+territory',
    caseSensitive: false,
  );

  static final _relayedAdviceEn = RegExp(
    r'\b(recommend\w*|suggest\w*|advis\w*|urg\w*|told\s+investors\s+to)\s+'
    r'(\w+\s+)?(to\s+)?(buy|sell|buying|selling|invest|investing|get\s+in|get\s+out)\b',
    caseSensitive: false,
  );

  static final _absenceEn = RegExp(
    r"\b(there\s+(are|were|is)\s+no|has\s+no|have\s+no|had\s+no|didn't\s+have|"
    r"won't\s+have|no)\s+[^.]{0,30}(earnings|results|reports|filings)",
    caseSensitive: false,
  );

  static final _mentionsPortfolioEn = RegExp(
    r"\b(your\s+portfolio|you\s+hold|you\s+own|you\s+don't\s+(hold|own))\b",
    caseSensitive: false,
  );

  static final _notHeldClauseEn = RegExp(
    r",?\s*(although|but|and|though)?\s*you\s+(don't|do\s+not)\s+(hold|own)\b[^.]*",
    caseSensitive: false,
  );

  /// Un texto "en español" que en realidad quedó en inglés.
  static final _english = RegExp(
    r'\b(the|and|with|after|stock|shares|says|amid|over|its|for)\b',
    caseSensitive: false,
  );

  /// `true` si [text] parece haber quedado en inglés.
  static bool looksEnglish(String text) => _english.hasMatch(text);

  /// `true` si [text] habla de la cartera del usuario ("tu cartera",
  /// "tenés" / "your portfolio", "you hold").
  static bool mentionsPortfolio(String text, {required bool english}) =>
      (english ? _mentionsPortfolioEn : _mentionsPortfolio).hasMatch(text);

  /// `true` si [text] tiene comillas.
  static bool hasQuotes(String text) => _quotes.hasMatch(text);

  /// Saca la cláusula "aunque no tenés X" de [text] (si no queda vacío).
  static String withoutNotHeld(String text, {bool english = false}) {
    final cleaned =
        text.replaceAll(english ? _notHeldClauseEn : _notHeldClause, '').trim();
    if (cleaned.isEmpty) return text;
    return cleaned.endsWith('.') ? cleaned : '$cleaned.';
  }

  /// Los problemas de [text] contra las reglas generales, en el idioma
  /// [language] ('es' | 'en') del texto y de los mensajes (que se le pasan
  /// al modelo para que reescriba). Vacío = pasa.
  ///
  /// - [max]: largo máximo en caracteres.
  /// - [backing]: números de los datos que vio el modelo; un número que no
  ///   salga de ahí (ni de [source]) es un problema.
  /// - [source]: el titular o texto que se parafrasea; sus cifras están
  ///   respaldadas ("iPhone 18", "10 mil millones" de "$10 billion").
  /// - [causalHint]: cómo reformular una causa (cambia según el período).
  static List<String> problems(
    String text, {
    required String language,
    required int max,
    required Iterable<double> backing,
    bool noQuotes = false,
    bool noCausal = false,
    String? source,
    ({String es, String en}) causalHint = (
      es: 'usá "coincidió con" o "en una semana en la que"',
      en: 'use "coincided with" or "in a week when"',
    ),
  }) {
    final en = language == 'en';
    String t(String es, String english) => en ? english : es;
    final causal = en ? _causalEn : _causal;
    final jargon = en ? _jargonEn : _jargon;
    final empty = en ? _emptyEn : _empty;
    final relayedAdvice = en ? _relayedAdviceEn : _relayedAdvice;
    final absence = en ? _absenceEn : _absence;
    final backed = [
      ...backing,
      if (source != null)
        for (final n in AnalysisProseCheck.numbersIn(source)) n.value,
    ];
    return [
      if (text.length > max)
        t(
          'es demasiado largo (máx. $max caracteres)',
          'is too long (max $max characters)',
        ),
      if (AnalysisProseCheck.hasAdvice(text))
        t('da un consejo de compra o venta', 'gives buy or sell advice'),
      if (AnalysisProseCheck.hasValuationJudgment(text))
        t('hace un juicio de valuación', 'makes a valuation judgment'),
      if (relayedAdvice.hasMatch(text))
        t(
          'repite un consejo de compra o venta de un tercero',
          "relays a third party's buy or sell advice",
        ),
      if (absence.hasMatch(text))
        t(
          'afirma que algo no existe; si no hay datos, no hables de eso',
          "claims something doesn't exist; if there is no data, don't talk "
              'about it',
        ),
      if (jargon.hasMatch(text))
        t(
          'usa jerga ("${jargon.firstMatch(text)!.group(0)}"); decilo en palabras simples',
          'uses jargon ("${jargon.firstMatch(text)!.group(0)}"); say it in plain words',
        ),
      if (empty.hasMatch(text))
        t(
          'es una frase vacía: decí algo concreto',
          'is an empty phrase: say something concrete',
        ),
      if (noQuotes && _quotes.hasMatch(text))
        t(
          'usa comillas: parafraseá sin citar',
          'uses quotation marks: paraphrase without quoting',
        ),
      if (noCausal && causal.hasMatch(text))
        t(
          'afirma una causa; ${causalHint.es}',
          'states a cause; ${causalHint.en}',
        ),
      for (final n in AnalysisProseCheck.numbersIn(text.replaceAll(_sp500, '')))
        if (!AnalysisProseCheck.isBacked(n, backed))
          t(
            'usa el número ${_fmt(n.value)}: la prosa no lleva cifras',
            'uses the number ${_fmt(n.value)}: the prose has no figures',
          ),
    ];
  }

  /// Todos los números de los datos que vio el modelo (para respaldar los
  /// que cite).
  static List<double> numbersIn(Object? json) {
    final out = <double>[];
    void walk(Object? v) {
      switch (v) {
        case num n:
          out.add(n.toDouble());
        case Map m:
          m.values.forEach(walk);
        case List l:
          l.forEach(walk);
      }
    }

    walk(json);
    return out;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
