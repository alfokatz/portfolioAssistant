import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_draft.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_prose_rules.dart';

/// Resultado de validar un borrador: [draft] es lo que se puede mostrar
/// (sin las partes que fallaron); [issues], qué corregir si se pide una
/// reescritura; [removed], cuántos ítems quedaron afuera (para el evento
/// `daily_brief_generated.removed_items`).
class DailyBriefReview {
  const DailyBriefReview({
    required this.draft,
    required this.issues,
    required this.removed,
  });

  final DailyBriefDraft draft;
  final List<String> issues;
  final int removed;

  bool get isClean => issues.isEmpty;
}

/// Chequeos determinísticos sobre lo que escribió Porty, contra los datos
/// del día. Reusa las reglas de redacción del semanal
/// ([ReportProseRules]: causas, consejo propio y de terceros, jerga, frases
/// vacías, ausencias, comillas, cifras respaldadas, "tu cartera" en ítems
/// que no la tocan, inglés en un brief en español) y suma las propias:
/// ids que existan y sean del tipo correcto, un "por qué" solo para quien lo
/// necesita, la `connection` solo con la clase de activo que el usuario
/// tiene, y el tope de palabras. Nunca se muestra algo que no pase.
abstract final class DailyBriefValidator {
  /// Largos máximos (los del prompt llevan un margen más chico: el modelo
  /// cuenta mal).
  static const whyMax = 120;
  static const newsMax = 100;
  static const connectionMax = 120;

  /// Palabras de toda la prosa del brief (lectura de un minuto).
  static const maxWords = 120;

  static final _link = RegExp(r'https?://|www\.', caseSensitive: false);

  static DailyBriefReview review(
    DailyBriefDraft draft,
    DailyBriefInput input, {
    String? language,
  }) {
    final lang = (language ?? input.language) == 'en' ? 'en' : 'es';
    final en = lang == 'en';
    String t(String es, String english) => en ? english : es;
    final issues = <String>[];
    final backing = ReportProseRules.numbersIn(input.toPromptJson());
    final heldById = {for (final h in input.held) h.id: h};
    final watchById = {for (final h in input.watch) h.id: h};
    final connectable = {for (final f in input.connectable) f.topicId!: f};
    final whyTickers = {
      for (final m in input.whyMovers) m.ticker.toUpperCase(),
    };

    /// `null` si [text] falla algún chequeo general (y anota por qué).
    String? check(
      String field,
      String text,
      int max, {
      required String source,
    }) {
      final problems = [
        ...ReportProseRules.problems(
          text,
          language: lang,
          max: max,
          backing: backing,
          noQuotes: true,
          noCausal: true,
          source: source,
          causalHint: (
            es: 'usá "coincidió con" o "el día que"',
            en: 'use "coincided with" or "on the day"',
          ),
        ),
        if (_link.hasMatch(text))
          t(
            'tiene un link: la app muestra el link del medio',
            'has a link: the app shows the outlet link',
          ),
        if (!en && ReportProseRules.looksEnglish(text))
          'tiene que estar en español',
      ];
      if (problems.isEmpty) return text;
      issues.add('$field ${problems.toSet().join('; ')}: «$text»');
      return null;
    }

    // Prioridad si la prosa se pasa del tope de palabras: por qué, noticias
    // de la cartera, de la watchlist y, al final, las conexiones.
    final why = <DraftBriefLine>[];
    final usedTickers = <String>{};
    for (final l in draft.why) {
      final item = heldById[l.newsId];
      if (item == null) {
        issues.add(
          t(
            'why: ${l.newsId} no es un titular de "held_news"',
            'why: ${l.newsId} is not a "held_news" headline',
          ),
        );
        continue;
      }
      final ticker = item.ticker.toUpperCase();
      if (!whyTickers.contains(ticker)) {
        issues.add(
          t(
            'why: ${item.ticker} no necesita un "por qué"',
            'why: ${item.ticker} does not need a "why"',
          ),
        );
        continue;
      }
      if (usedTickers.contains(ticker)) continue;
      final text = check('why ${l.newsId}', l.text, whyMax, source: item.title);
      if (text != null) {
        usedTickers.add(ticker);
        why.add(DraftBriefLine(newsId: l.newsId, text: text));
      }
    }

    final held = <DraftBriefLine>[];
    final heldTickers = <String>{};
    for (final l in draft.held) {
      if (held.length >= DailyBriefInput.maxHeld) break;
      final item = heldById[l.newsId];
      if (item == null) {
        issues.add(
          t(
            'held_news: ${l.newsId} no es un titular de "held_news"',
            'held_news: ${l.newsId} is not a "held_news" headline',
          ),
        );
        continue;
      }
      final ticker = item.ticker.toUpperCase();
      // Ya está en un "por qué" o ya hay una línea de ese ticker: no repetir.
      if (usedTickers.contains(ticker) || heldTickers.contains(ticker)) {
        continue;
      }
      final text = check(
        'held_news ${l.newsId}',
        l.text,
        newsMax,
        source: item.title,
      );
      if (text != null) {
        heldTickers.add(ticker);
        held.add(DraftBriefLine(newsId: l.newsId, text: text));
      }
    }

    final watch = <DraftBriefLine>[];
    final watchTickers = <String>{};
    for (final l in draft.watch) {
      if (watch.length >= DailyBriefInput.maxWatch) break;
      final item = watchById[l.newsId];
      if (item == null) {
        issues.add(
          t(
            'watch_news: ${l.newsId} no es un titular de "watch_news"',
            'watch_news: ${l.newsId} is not a "watch_news" headline',
          ),
        );
        continue;
      }
      final ticker = item.ticker.toUpperCase();
      if (watchTickers.contains(ticker)) continue;
      // Es de la watchlist: el usuario no lo tiene, y no se le dice que sí.
      final text = check(
        'watch_news ${l.newsId}',
        ReportProseRules.withoutNotHeld(l.text, english: en),
        newsMax,
        source: item.title,
      );
      if (text != null &&
          ReportProseRules.mentionsPortfolio(text, english: en)) {
        issues.add(
          t(
            'watch_news ${l.newsId} habla de la cartera del usuario, pero '
                'ese titular es de un ticker que solo sigue: «$text»',
            'watch_news ${l.newsId} talks about the user\'s portfolio, but '
                'that headline is about a ticker they only follow: «$text»',
          ),
        );
      } else if (text != null) {
        watchTickers.add(ticker);
        watch.add(DraftBriefLine(newsId: l.newsId, text: text));
      }
    }

    final market = <DraftConnection>[];
    final seenTopics = <String>{};
    for (final c in draft.market) {
      if (c.connection == null || seenTopics.contains(c.topicId)) continue;
      final fact = connectable[c.topicId];
      if (fact == null) {
        issues.add(
          t(
            'market ${c.topicId}: no hay una conexión posible (el usuario no '
                'tiene esa clase de activo o el tema no está); va null',
            'market ${c.topicId}: no connection is possible (the user does '
                'not hold that asset class or the topic is missing); use null',
          ),
        );
        continue;
      }
      final text = check(
        'market ${c.topicId}.connection',
        c.connection!,
        connectionMax,
        source: fact.text,
      );
      if (text != null) {
        seenTopics.add(c.topicId);
        market.add(DraftConnection(topicId: c.topicId, connection: text));
      }
    }

    // Tope de palabras de toda la prosa, en orden de prioridad.
    var words = 0;
    var tooLong = false;
    bool fits(String text) {
      final n = _words(text);
      if (words + n > maxWords) {
        tooLong = true;
        return false;
      }
      words += n;
      return true;
    }

    final keptWhy = [
      for (final l in why)
        if (fits(l.text)) l,
    ];
    final keptHeld = [
      for (final l in held)
        if (fits(l.text)) l,
    ];
    final keptWatch = [
      for (final l in watch)
        if (fits(l.text)) l,
    ];
    final keptMarket = [
      for (final c in market)
        if (fits(c.connection!)) c,
    ];
    if (tooLong) {
      issues.add(
        t(
          'el brief es demasiado largo (máx. $maxWords palabras en total): '
              'acortá las líneas o dejá afuera las menos importantes',
          'the brief is too long (max $maxWords words in total): shorten the '
              'lines or leave out the least important',
        ),
      );
    }

    final result = DailyBriefDraft(
      why: keptWhy,
      held: keptHeld,
      watch: keptWatch,
      market: keptMarket,
    );
    return DailyBriefReview(
      draft: result,
      issues: issues,
      removed: draft.itemCount - result.itemCount,
    );
  }

  static int _words(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}
