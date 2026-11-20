import 'package:portfolio_assistant/features/weekly_report/domain/report_prose_rules.dart';
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

  /// [language] es el del informe ('es' | 'en', ver
  /// `weeklyReportSystemPromptFor`): decide qué reglas de redacción aplican
  /// y en qué idioma se le explican al modelo los problemas.
  static WeeklyReportReview review(
    WeeklyReportDraft draft,
    WeeklyReportInput input, {
    String language = 'es',
  }) {
    final en = language == 'en';
    String t(String es, String english) => en ? english : es;
    final issues = <String>[];
    final backing = ReportProseRules.numbersIn(input.toPromptJson());
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
      final problems = ReportProseRules.problems(
        text,
        language: language,
        max: max,
        backing: backing,
        noQuotes: noQuotes,
        noCausal: noCausal,
        source: source,
      );
      if (problems.isEmpty) return text;
      issues.add('$field ${problems.toSet().join('; ')}: «$text»');
      return null;
    }

    final movers = <DraftMover>[];
    for (final m in draft.movers) {
      if (!explain.contains(m.ticker)) {
        issues.add(
          t(
            'movers: ${m.ticker} no necesita un "por qué"',
            'movers: ${m.ticker} does not need a "why"',
          ),
        );
        continue;
      }
      if (movers.any((x) => x.ticker == m.ticker)) continue;
      var newsId = m.newsId;
      if (newsId != null && newsById[newsId]?.ticker != m.ticker) {
        issues.add(
          t(
            'movers ${m.ticker}: news_id $newsId no es de ese ticker',
            'movers ${m.ticker}: news_id $newsId is not about that ticker',
          ),
        );
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
        issues.add(
          t(
            'headlines: ${h.newsId} no existe',
            "headlines: ${h.newsId} doesn't exist",
          ),
        );
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
        issues.add(
          t(
            'headlines ${h.newsId}: sin el ticker adelante: «$title»',
            'headlines ${h.newsId}: no ticker prefix: «$title»',
          ),
        );
        title = null;
      }
      if (title != null && !en && ReportProseRules.looksEnglish(title)) {
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
        issues.add(
          t(
            'investors: ${i.itemId} no existe',
            "investors: ${i.itemId} doesn't exist",
          ),
        );
        continue;
      }
      if (investors.any((x) => x.itemId == i.itemId)) continue;
      final take = check(
        'investors ${i.itemId}.take',
        related.isRelevant
            ? i.take
            : ReportProseRules.withoutNotHeld(i.take, english: en),
        investorMax,
        noQuotes: true,
      );
      if (take != null &&
          !related.isRelevant &&
          ReportProseRules.mentionsPortfolio(take, english: en)) {
        issues.add(
          t(
            'investors ${i.itemId}.take habla de la cartera del usuario, pero '
                'ese ítem no toca ninguna de sus posiciones: «$take»',
            "investors ${i.itemId}.take talks about the user's portfolio, "
                "but that item doesn't touch any of their holdings: «$take»",
          ),
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
            ? t(
              'learn tiene que ser null esta semana',
              'learn must be null this week',
            )
            : t(
              'learn.topic "${learn.topic}" no es el de esta semana: '
                  'tiene que ser "$topic"',
              'learn.topic "${learn.topic}" is not this week\'s: it must be '
                  '"$topic"',
            ),
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
}
