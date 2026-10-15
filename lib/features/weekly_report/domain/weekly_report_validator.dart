import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';

/// Resultado de validar un borrador: [draft] es lo que se puede mostrar
/// (sin las partes que fallaron); [issues], qué corregir si se pide una
/// reescritura.
class WeeklyReportReview {
  const WeeklyReportReview({required this.draft, required this.issues});

  final WeeklyReportDraft draft;
  final List<String> issues;

  bool get isClean => issues.isEmpty;
}

/// Chequeos determinísticos sobre lo que escribió Porty, contra los datos
/// de la semana. Nunca se muestra algo que no pase: o se pide reescribir, o
/// se saca esa parte.
abstract final class WeeklyReportValidator {
  static const maxHeadlines = 3;

  /// Largos máximos del prompt, con un margen (el modelo cuenta mal).
  static const readingMax = 160;
  static const whyMax = 160;
  static const headlineMax = 100;
  static const investorMax = 185;
  static const conceptMax = 50;
  static const learnMax = 250;

  /// "subió por X", "cayó debido a X": el informe no afirma causas.
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

  static const _letters = 'A-Za-zÁÉÍÓÚÜÑáéíóúüñ';
  static const _notLetter = '(?<![$_letters])';
  static const _endWord = '(?![$_letters])';

  /// Jerga que el informe no usa (o explica). "pts" era lo que más
  /// confundía en la versión anterior.
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

  /// Un titular "en español" que en realidad quedó en inglés.
  static final _english = RegExp(
    r'\b(the|and|with|after|stock|shares|says|amid|over|its|for)\b',
    caseSensitive: false,
  );

  static WeeklyReportReview review(
    WeeklyReportDraft draft,
    WeeklyReportInput input,
  ) {
    final issues = <String>[];
    final backing = _numbersIn(input.toPromptJson());
    final newsById = {for (final n in input.news) n.id: n};
    final investorsById = {for (final r in input.investors) r.item.id: r};
    final explain = input.explainTickers.toSet();

    /// `null` si [text] falla algún chequeo general (y anota por qué).
    String? check(
      String field,
      String? text,
      int max, {
      bool noQuotes = false,
      bool noCausal = false,
      String? source,
    }) {
      if (text == null) return null;
      // Un número del titular citado está respaldado ("iPhone 18", "10 mil
      // millones" de "$10 billion"); el resto de la prosa no lleva cifras.
      final backed = [
        ...backing,
        if (source != null)
          for (final n in AnalysisProseCheck.numbersIn(source)) n.value,
      ];
      final problems = <String>[
        if (text.length > max) 'es demasiado largo (máx. $max caracteres)',
        if (AnalysisProseCheck.hasAdvice(text))
          'da un consejo de compra o venta',
        if (AnalysisProseCheck.hasValuationJudgment(text))
          'hace un juicio de valuación',
        if (_relayedAdvice.hasMatch(text))
          'repite un consejo de compra o venta de un tercero',
        if (_absence.hasMatch(text))
          'afirma que algo no existe; si no hay datos, no hables de eso',
        if (_jargon.hasMatch(text))
          'usa jerga ("${_jargon.firstMatch(text)!.group(0)}"); decilo en palabras simples',
        if (_empty.hasMatch(text)) 'es una frase vacía: decí algo concreto',
        if (noQuotes && _quotes.hasMatch(text))
          'usa comillas: parafraseá sin citar',
        if (noCausal && _causal.hasMatch(text))
          'afirma una causa; usá "coincidió con" o "en una semana en la que"',
        for (final n in AnalysisProseCheck.numbersIn(
          text.replaceAll(_sp500, ''),
        ))
          if (!AnalysisProseCheck.isBacked(n, backed))
            'usa el número ${_fmt(n.value)}: la prosa no lleva cifras',
      ];
      if (problems.isEmpty) return text;
      issues.add('$field ${problems.toSet().join('; ')}: «$text»');
      return null;
    }

    final movers = <DraftMover>[];
    for (final m in draft.movers) {
      if (!explain.contains(m.ticker)) {
        issues.add('movers: ${m.ticker} no necesita un "por qué"');
        continue;
      }
      if (movers.any((x) => x.ticker == m.ticker)) continue;
      var newsId = m.newsId;
      if (newsId != null && newsById[newsId]?.ticker != m.ticker) {
        issues.add('movers ${m.ticker}: news_id $newsId no es de ese ticker');
        newsId = null;
      }
      final why = check(
        'movers ${m.ticker}.why',
        m.why,
        whyMax,
        noCausal: true,
        source: newsById[newsId]?.headline,
      );
      if (why != null) {
        movers.add(DraftMover(ticker: m.ticker, why: why, newsId: newsId));
      }
    }
    final usedNews = {
      for (final m in movers)
        if (m.newsId != null) m.newsId!,
    };

    final headlines = <DraftHeadline>[];
    for (final h in draft.headlines) {
      if (headlines.length >= maxHeadlines) break;
      final item = newsById[h.newsId];
      if (item == null) {
        issues.add('headlines: ${h.newsId} no existe');
        continue;
      }
      if (usedNews.contains(h.newsId) ||
          headlines.any((x) => x.newsId == h.newsId)) {
        continue; // ya está en un "por qué": no repetir
      }
      var title = check(
        'headlines ${h.newsId}.title_es',
        h.title,
        headlineMax,
        noQuotes: true,
        source: item.headline,
      );
      if (title != null && title.toUpperCase().startsWith('${item.ticker} ')) {
        issues.add('headlines ${h.newsId}: sin el ticker adelante: «$title»');
        title = null;
      }
      if (title != null && _english.hasMatch(title)) {
        issues.add(
          'headlines ${h.newsId}: tiene que estar en español: «$title»',
        );
        title = null;
      }
      if (title != null) {
        headlines.add(DraftHeadline(newsId: h.newsId, title: title));
      }
    }

    final investors = <DraftInvestor>[];
    for (final i in draft.investors) {
      final related = investorsById[i.itemId];
      if (related == null) {
        issues.add('investors: ${i.itemId} no existe');
        continue;
      }
      if (investors.any((x) => x.itemId == i.itemId)) continue;
      final take = check(
        'investors ${i.itemId}.take',
        related.isRelevant ? i.take : _withoutNotHeld(i.take),
        investorMax,
        noQuotes: true,
      );
      if (take != null &&
          !related.isRelevant &&
          _mentionsPortfolio.hasMatch(take)) {
        issues.add(
          'investors ${i.itemId}.take habla de la cartera del usuario, pero '
          'ese ítem no toca ninguna de sus posiciones: «$take»',
        );
      } else if (take != null) {
        investors.add(DraftInvestor(itemId: i.itemId, take: take));
      }
    }

    var learn = draft.learn;
    final topic = input.learnTopic;
    if (learn != null && (topic == null || learn.topic != topic)) {
      issues.add(
        topic == null
            ? 'learn tiene que ser null esta semana'
            : 'learn.topic "${learn.topic}" no es el de esta semana: '
                'tiene que ser "$topic"',
      );
      learn = null;
    }
    final concept = check('learn.concept', learn?.concept, conceptMax);
    final learnText = check('learn.text', learn?.text, learnMax);

    return WeeklyReportReview(
      draft: WeeklyReportDraft(
        reading: check('reading', draft.reading, readingMax),
        movers: movers,
        headlines: headlines,
        investors: investors,
        learn:
            concept != null && learnText != null
                ? DraftLearn(topic: topic, concept: concept, text: learnText)
                : null,
      ),
      issues: issues,
    );
  }

  static String _withoutNotHeld(String take) {
    final cleaned = take.replaceAll(_notHeldClause, '').trim();
    if (cleaned.isEmpty) return take;
    return cleaned.endsWith('.') ? cleaned : '$cleaned.';
  }

  /// Todos los números de los datos que vio el modelo (para respaldar los
  /// que cite). En v2 casi no hay: la prosa no lleva cifras.
  static List<double> _numbersIn(Object? json) {
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
