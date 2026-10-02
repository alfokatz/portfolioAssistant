import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_validator.dart';

import 'weekly_report_fixtures.dart';

WeeklyReportDraft _draft({
  String? headline = 'Apple empujó tu cartera en una semana tranquila',
  List<DraftMover> movers = const [],
  List<DraftNews> news = const [],
  List<DraftInvestor> investors = const [],
  DraftLearn? learn,
  String? question,
  String? closing,
}) => WeeklyReportDraft(
  headline: headline,
  movers: movers,
  news: news,
  investors: investors,
  learn: learn,
  followUpQuestion: question,
  closing: closing,
);

void main() {
  final input = fixtureInput();

  test('a good draft passes untouched', () {
    final r = WeeklyReportValidator.review(
      _draft(
        movers: const [
          DraftMover(
            ticker: 'AAPL',
            why: 'Coincidió con las buenas reservas del nuevo iPhone.',
            newsId: 'n1',
          ),
          DraftMover(
            ticker: 'MSFT',
            why: 'Bajó en una semana en la que la UE abrió una investigación.',
            newsId: 'n2',
          ),
        ],
        news: const [
          DraftNews(
            newsId: 'n2',
            take: 'Una investigación así suele llevar meses.',
          ),
        ],
        investors: const [
          DraftInvestor(
            itemId: 'i2',
            take:
                'Según CNBC, Bill Ackman ve a Microsoft como su principal apuesta en IA. Tenés MSFT en tu cartera.',
          ),
        ],
        learn: const DraftLearn(
          topic: 'earnings',
          concept: 'Qué son los earnings',
          text: 'Es el reporte trimestral de resultados de una empresa.',
        ),
        question: '¿Qué puede pasar con MSFT cuando presente resultados?',
        closing: 'La semana que viene presenta resultados MSFT.',
      ),
      input,
    );
    expect(r.issues, isEmpty);
    expect(r.draft.movers, hasLength(2));
    expect(r.draft.investors.single.itemId, 'i2');
  });

  test(
    'numbers must come from the data (rounded is fine, invented is not)',
    () {
      final r = WeeklyReportValidator.review(
        _draft(
          headline: 'Tu cartera subió 2,5% en la semana', // está en los datos
          closing: 'Apple ya acumula 37% en el año.', // no está
        ),
        input,
      );
      expect(r.draft.headline, isNotNull);
      expect(r.draft.closing, isNull);
      expect(r.issues.single, contains('37'));
    },
  );

  test('no buy/sell advice and no valuation judgments', () {
    final r = WeeklyReportValidator.review(
      _draft(
        headline: 'Es buen momento para comprar más Apple',
        closing: 'Microsoft quedó barata después de la baja.',
      ),
      input,
    );
    expect(r.draft.headline, isNull);
    expect(r.draft.closing, isNull);
    expect(r.issues, hasLength(2));
  });

  test('no stated causes in movers', () {
    final r = WeeklyReportValidator.review(
      _draft(
        movers: const [
          DraftMover(
            ticker: 'AAPL',
            why: 'Subió por las ventas récord del iPhone.',
            newsId: 'n1',
          ),
        ],
      ),
      input,
    );
    expect(r.draft.movers, isEmpty);
    expect(r.issues.single, contains('causa'));
  });

  test('no quotes in what third parties said', () {
    final r = WeeklyReportValidator.review(
      _draft(
        investors: const [
          DraftInvestor(
            itemId: 'i2',
            take: 'Ackman dijo: “Microsoft es mi mejor apuesta”.',
          ),
        ],
      ),
      input,
    );
    expect(r.draft.investors, isEmpty);
    expect(r.issues.single, contains('comillas'));
  });

  test(
    'ids and tickers must exist; a news id of another ticker is unlinked',
    () {
      final r = WeeklyReportValidator.review(
        _draft(
          movers: const [
            DraftMover(ticker: 'NVDA', why: 'Se movió fuerte.'),
            DraftMover(
              ticker: 'AAPL',
              why: 'Coincidió con una semana de noticias de producto.',
              newsId: 'n2', // es de MSFT
            ),
          ],
          news: const [DraftNews(newsId: 'n9', take: 'Inventada.')],
          investors: const [DraftInvestor(itemId: 'i7', take: 'Inventado.')],
        ),
        input,
      );
      expect(r.draft.movers.single.ticker, 'AAPL');
      expect(r.draft.movers.single.newsId, isNull);
      expect(r.draft.news, isEmpty);
      expect(r.draft.investors, isEmpty);
      expect(r.issues, hasLength(4));
    },
  );

  test('caps and lengths', () {
    final r = WeeklyReportValidator.review(
      _draft(headline: 'x' * 150, question: '¿${'a' * 120}?'),
      input,
    );
    expect(r.draft.headline, isNull);
    expect(r.draft.followUpQuestion, isNull);
  });

  test('shares of a SEC filing count as data', () {
    final r = WeeklyReportValidator.review(
      _draft(
        investors: const [
          DraftInvestor(
            itemId: 'i1',
            take:
                'Berkshire Hathaway informó la compra de 638.813 acciones de Lennar.',
          ),
        ],
      ),
      input,
    );
    expect(r.issues, isEmpty);
  });

  test('parses model output with fences and missing fields', () {
    final d =
        WeeklyReportDraft.tryParse(
          '```json\n{"headline":"Semana tranquila","movers":[{"ticker":"aapl","why":"x","news_id":null}]}\n```',
        )!;
    expect(d.headline, 'Semana tranquila');
    expect(d.movers.single.ticker, 'AAPL');
    expect(d.news, isEmpty);
    expect(WeeklyReportDraft.tryParse('no json'), isNull);
  });

  test('learn topic must be the one the app picked for this week', () {
    final r = WeeklyReportValidator.review(
      _draft(
        learn: const DraftLearn(
          topic: 'concentration', // 2 posiciones: no es notable
          concept: 'Concentración',
          text: 'Tener mucho en una sola acción aumenta el riesgo.',
        ),
      ),
      input,
    );
    expect(r.draft.learn, isNull);
    expect(r.issues.single, contains('earnings'));
  });

  test('an investor item that does not touch the portfolio cannot talk '
      'about it', () {
    final r = WeeklyReportValidator.review(
      _draft(
        investors: const [
          DraftInvestor(
            itemId: 'i1', // LEN: no la tiene
            take:
                'Berkshire Hathaway informó compras de Lennar, aunque no tenés LEN.',
          ),
          DraftInvestor(
            itemId: 'i2', // MSFT: la tiene
            take:
                'Según CNBC, Bill Ackman apuesta por Microsoft. Tenés MSFT en tu cartera.',
          ),
        ],
      ),
      input,
    );
    // La aclaración "aunque no tenés LEN" se saca sola; el resto queda.
    expect(r.draft.investors.map((i) => i.itemId), ['i1', 'i2']);
    expect(
      r.draft.investors.first.take,
      'Berkshire Hathaway informó compras de Lennar.',
    );
    expect(r.issues, isEmpty);
  });

  test('saying that something does not exist is rejected', () {
    final r = WeeklyReportValidator.review(
      _draft(closing: 'La semana que viene no hay reportes de resultados.'),
      input,
    );
    expect(r.draft.closing, isNull);
  });

  test('relaying third-party advice is advice too', () {
    final r = WeeklyReportValidator.review(
      _draft(closing: 'Un blog recomendó comprar NVDA esta semana.'),
      input,
    );
    expect(r.draft.closing, isNull);
  });

  test('the app picks a specific learn topic first, else rotates', () {
    expect(input.learnTopic, 'earnings'); // MSFT presenta la semana que viene
    final quiet = fixtureInput(withNews: false, withInvestors: false);
    expect(quiet.learnTopic, 'earnings');
  });

  test('passive voice is not a stated cause', () {
    final r = WeeklyReportValidator.review(
      _draft(
        movers: const [
          DraftMover(
            ticker: 'MSFT',
            why: 'Bajó, en una semana en la que fue destacada por la prensa.',
          ),
        ],
      ),
      input,
    );
    expect(r.issues, isEmpty);
  });

  test('talking about the portfolio of an unrelated item is still an issue', () {
    final r = WeeklyReportValidator.review(
      _draft(
        investors: const [
          DraftInvestor(
            itemId: 'i1',
            take:
                'Berkshire Hathaway compró Lennar, algo para mirar en tu cartera.',
          ),
        ],
      ),
      input,
    );
    expect(r.draft.investors, isEmpty);
    expect(r.issues.single, contains('i1'));
  });
}
