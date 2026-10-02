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
  static const maxMovers = 3;
  static const maxNews = 4;
  static const maxInvestors = 4;

  /// Largos máximos del prompt, con un margen (el modelo cuenta mal).
  static const headlineMax = 100;
  static const moverMax = 160;
  static const newsMax = 160;
  static const investorMax = 185;
  static const conceptMax = 50;
  static const learnMax = 250;
  static const questionMax = 95;
  static const closingMax = 160;

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

  /// "No hay reportes de resultados": una lista vacía no prueba que algo
  /// no exista (los earnings cubren solo las posiciones de más peso).
  static final _absence = RegExp(
    r'no\s+(hay|tiene[ns]?|presenta[n]?|habr[aá])\s+[^.]{0,30}'
    r'(resultados|reportes|ganancias|balances|earnings)',
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

  /// Mencionar la cartera del usuario en un ítem que no la toca.
  static final _mentionsPortfolio = RegExp(
    r'(tu\s+cartera|ten[eé]s|no\s+la\s+ten[eé]s)',
    caseSensitive: false,
  );

  /// ", aunque no tenés LEN en tu cartera": el modelo insiste en aclararlo
  /// aunque no suma. Es una cláusula sobrante, no un error de fondo: se saca
  /// sin pedir reescritura.
  static final _notHeldClause = RegExp(
    r',?\s*(aunque|pero|y)?\s*no\s+(la|lo|las|los)?\s*ten[eé]s\b[^.]*',
    caseSensitive: false,
  );

  static String _withoutNotHeld(String take) {
    final cleaned = take.replaceAll(_notHeldClause, '').trim();
    if (cleaned.isEmpty) return take;
    return cleaned.endsWith('.') ? cleaned : '$cleaned.';
  }

  /// Comillas: en lo atribuido a terceros, una cita inventada.
  static final _quotes = RegExp('["“”«»]');

  static WeeklyReportReview review(
    WeeklyReportDraft draft,
    WeeklyReportInput input,
  ) {
    final issues = <String>[];
    final backing = _numbersIn(input.toPromptJson());
    final newsById = {for (final n in input.news) n.id: n};
    final investorsById = {for (final r in input.investors) r.item.id: r};
    final positionTickers = {
      for (final p in input.numbers.positions)
        if (p.contributionPp != 0) p.ticker,
    };

    /// `null` si [text] falla algún chequeo general (y anota por qué).
    String? check(
      String field,
      String? text,
      int max, {
      bool noQuotes = false,
      bool noCausal = false,
    }) {
      if (text == null) return null;
      final problems = <String>[
        if (text.length > max) 'es demasiado largo (máx. $max caracteres)',
        if (AnalysisProseCheck.hasAdvice(text))
          'da un consejo de compra o venta',
        if (AnalysisProseCheck.hasValuationJudgment(text))
          'hace un juicio de valuación',
        if (_relayedAdvice.hasMatch(text))
          'repite un consejo de compra o venta de un tercero',
        if (_absence.hasMatch(text))
          'afirma que no hay resultados; si no hay datos, no hables de eso',
        if (noQuotes && _quotes.hasMatch(text))
          'usa comillas: parafraseá sin citar',
        if (noCausal && _causal.hasMatch(text))
          'afirma una causa; usá "coincidió con" o "en una semana en la que"',
        for (final n in AnalysisProseCheck.numbersIn(text))
          if (!AnalysisProseCheck.isBacked(n, backing))
            'usa el número ${_fmt(n.value)}, que no está en los datos',
      ];
      if (problems.isEmpty) return text;
      issues.add('$field ${problems.toSet().join('; ')}: «$text»');
      return null;
    }

    final movers = <DraftMover>[];
    for (final m in draft.movers) {
      if (movers.length >= maxMovers) break;
      if (!positionTickers.contains(m.ticker)) {
        issues.add('movers: ${m.ticker} no es una posición que se movió');
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
        moverMax,
        noCausal: true,
      );
      if (why != null) {
        movers.add(DraftMover(ticker: m.ticker, why: why, newsId: newsId));
      }
    }

    final news = <DraftNews>[];
    for (final n in draft.news) {
      if (news.length >= maxNews) break;
      if (!newsById.containsKey(n.newsId)) {
        issues.add('news: ${n.newsId} no existe');
        continue;
      }
      if (news.any((x) => x.newsId == n.newsId)) continue;
      final take = check(
        'news ${n.newsId}.take',
        n.take,
        newsMax,
        noCausal: true,
      );
      if (take != null) news.add(DraftNews(newsId: n.newsId, take: take));
    }

    final investors = <DraftInvestor>[];
    for (final i in draft.investors) {
      if (investors.length >= maxInvestors) break;
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
    if (learn != null && learn.topic != input.learnTopic) {
      issues.add(
        'learn.topic "${learn.topic}" no es el de esta semana: tiene que ser '
        '"${input.learnTopic}"',
      );
      learn = null;
    }
    final concept = check('learn.concept', learn?.concept, conceptMax);
    final learnText = check('learn.text', learn?.text, learnMax);

    return WeeklyReportReview(
      draft: WeeklyReportDraft(
        headline: check(
          'headline',
          draft.headline,
          headlineMax,
          noCausal: true,
        ),
        movers: movers,
        news: news,
        investors: investors,
        learn:
            concept != null && learnText != null
                ? DraftLearn(
                  topic: learn!.topic,
                  concept: concept,
                  text: learnText,
                )
                : null,
        followUpQuestion: check(
          'follow_up_question',
          draft.followUpQuestion,
          questionMax,
        ),
        closing: check('closing', draft.closing, closingMax, noCausal: true),
      ),
      issues: issues,
    );
  }

  /// Todos los números de los datos que vio el modelo (para respaldar los
  /// que cite). Las fechas `YYYY-MM-DD` aportan año, mes y día sueltos.
  static List<double> _numbersIn(Object? json) {
    final out = <double>[];
    void walk(Object? v) {
      switch (v) {
        case num n:
          out.add(n.toDouble());
        case String s:
          final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
          if (date != null) {
            for (var g = 1; g <= 3; g++) {
              out.add(double.parse(date.group(g)!));
            }
          }
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
