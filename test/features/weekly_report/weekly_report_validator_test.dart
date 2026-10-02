import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_validator.dart';

import 'weekly_report_fixtures.dart';

WeeklyReportDraft _draft({
  String? reading =
      'Una semana tranquila: subiste, más que el mercado, porque AAPL '
          'compensó a MSFT.',
  List<DraftMover> movers = const [],
  List<DraftHeadline> headlines = const [],
  List<DraftInvestor> investors = const [],
  DraftLearn? learn,
}) => WeeklyReportDraft(
  reading: reading,
  movers: movers,
  headlines: headlines,
  investors: investors,
  learn: learn,
);

void main() {
  final input = fixtureInput();

  test('the fixture: AAPL and MSFT need a why, only Ackman (MSFT) is '
      'relevant, the learn topic is earnings', () {
    expect(input.explainTickers, ['AAPL', 'MSFT']);
    expect(input.investors.map((r) => r.item.id), ['i2']);
    expect(input.learnTopic, 'earnings');
  });

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
        investors: const [
          DraftInvestor(
            itemId: 'i2',
            take:
                'Bill Ackman, gestor de Pershing Square, dijo que Microsoft es '
                'su principal apuesta en IA. Tenés MSFT en tu cartera.',
          ),
        ],
        learn: const DraftLearn(
          topic: 'earnings',
          concept: 'Qué es un reporte de resultados',
          text: 'Cada trimestre la empresa cuenta cuánto vendió y ganó.',
        ),
      ),
      input,
    );
    expect(r.issues, isEmpty);
    expect(r.draft.movers, hasLength(2));
    expect(r.draft.investors.single.itemId, 'i2');
  });

  test('prose carries no figures at all', () {
    final r = WeeklyReportValidator.review(
      _draft(reading: 'Tu cartera subió 2,5% en la semana.'),
      input,
    );
    expect(r.draft.reading, isNull);
    expect(r.issues.single, contains('cifras'));
  });

  test('names with a number and figures from the cited headline are fine', () {
    final r = WeeklyReportValidator.review(
      _draft(
        reading: 'Una semana tranquila: subiste menos que el S&P 500.',
        movers: const [
          DraftMover(
            ticker: 'AAPL',
            why: 'Coincidió con buenas reservas del iPhone 18.',
            newsId: 'n1',
          ),
          // n2 no habla de un iPhone 18: ahí el número no está respaldado.
          DraftMover(
            ticker: 'MSFT',
            why: 'Coincidió con 18 investigaciones en la UE.',
            newsId: 'n2',
          ),
        ],
        learn: const DraftLearn(
          topic: 'earnings',
          concept: 'Resultados y el S&P 500',
          text: 'Cada trimestre la empresa cuenta cuánto vendió y ganó.',
        ),
      ),
      input,
    );
    expect(r.draft.reading, isNotNull);
    expect(r.draft.learn, isNotNull);
    expect(r.draft.movers.map((m) => m.ticker), ['AAPL']);
    expect(r.issues.single, contains('MSFT'));
  });

  test('no jargon: "pts", "exposición", "rally"', () {
    for (final text in [
      'Le ganaste al mercado por varios pts.',
      'Tu exposición a tecnología pesó.',
      'Un rally de tecnología te empujó.',
    ]) {
      final r = WeeklyReportValidator.review(_draft(reading: text), input);
      expect(r.draft.reading, isNull, reason: text);
      expect(r.issues.single, contains('jerga'), reason: text);
    }
  });

  test('no empty filler like "liderando el movimiento"', () {
    final r = WeeklyReportValidator.review(
      _draft(reading: 'Tu cartera subió, con AAPL liderando el movimiento.'),
      input,
    );
    expect(r.draft.reading, isNull);
    expect(r.issues.single, contains('vacía'));
  });

  test('a why only for the tickers that need one, without stated causes', () {
    final r = WeeklyReportValidator.review(
      _draft(
        movers: const [
          DraftMover(ticker: 'NVDA', why: 'No la tiene.'),
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
    expect(r.issues, hasLength(2));
  });

  test('headlines: Spanish, no ticker prefix, not repeating a why', () {
    final r = WeeklyReportValidator.review(
      _draft(
        movers: const [
          DraftMover(
            ticker: 'AAPL',
            why: 'Coincidió con las reservas del iPhone.',
            newsId: 'n1',
          ),
        ],
        headlines: const [
          DraftHeadline(newsId: 'n1', title: 'Apple vende más iPhone'),
          DraftHeadline(
            newsId: 'n2',
            title: 'MSFT · La UE investiga a Microsoft',
          ),
          DraftHeadline(newsId: 'n9', title: 'No existe'),
        ],
      ),
      input,
    );
    // n1 ya está en el "por qué" de AAPL: se omite sin queja.
    expect(r.draft.headlines, isEmpty);
    expect(r.issues, hasLength(2)); // prefijo del ticker + id inexistente

    final english = WeeklyReportValidator.review(
      _draft(
        headlines: const [
          DraftHeadline(
            newsId: 'n2',
            title: 'Microsoft faces EU probe over cloud deals',
          ),
        ],
      ),
      input,
    );
    expect(english.draft.headlines, isEmpty);
    expect(english.issues.single, contains('español'));

    final good = WeeklyReportValidator.review(
      _draft(
        headlines: const [
          DraftHeadline(
            newsId: 'n2',
            title: 'La UE investiga los acuerdos de nube de Microsoft',
          ),
        ],
      ),
      input,
    );
    expect(good.issues, isEmpty);
    expect(good.draft.headlines.single.newsId, 'n2');
  });

  test('investors: only the filtered ones; no quotes; the "you don\'t hold '
      'it" clause is dropped', () {
    final r = WeeklyReportValidator.review(
      _draft(
        investors: const [
          DraftInvestor(itemId: 'i1', take: 'Berkshire compró Lennar.'),
          DraftInvestor(
            itemId: 'i2',
            take: 'Ackman dijo: “Microsoft es mi mejor apuesta”.',
          ),
        ],
      ),
      input,
    );
    expect(r.draft.investors, isEmpty);
    expect(r.issues, hasLength(2)); // i1 no está en el informe; comillas
  });

  test('learn: only the topic the app picked, and null when there is none', () {
    final wrong = WeeklyReportValidator.review(
      _draft(
        learn: const DraftLearn(
          topic: 'concentration',
          concept: 'Concentración',
          text: 'Tener mucho en una acción aumenta el riesgo.',
        ),
      ),
      input,
    );
    expect(wrong.draft.learn, isNull);
    expect(wrong.issues.single, contains('earnings'));

    final none = fixtureInput(withEarnings: false);
    expect(none.learnTopic, isNull);
    final extra = WeeklyReportValidator.review(
      _draft(
        learn: const DraftLearn(
          topic: 'earnings',
          concept: 'Resultados',
          text: 'Cada trimestre la empresa cuenta cuánto vendió.',
        ),
      ),
      none,
    );
    expect(extra.draft.learn, isNull);
    expect(extra.issues.single, contains('null'));
  });

  test('no advice, relayed advice, valuation or absence claims', () {
    for (final text in [
      'Es buen momento para comprar más Apple.',
      'Un blog recomendó comprar Apple esta semana.',
      'Microsoft quedó barata después de la baja.',
      'La semana que viene no hay reportes de resultados.',
    ]) {
      final r = WeeklyReportValidator.review(_draft(reading: text), input);
      expect(r.draft.reading, isNull, reason: text);
    }
  });

  test('parses model output with fences and missing fields', () {
    final d =
        WeeklyReportDraft.tryParse(
          '```json\n{"reading":"Semana tranquila","movers":[{"ticker":"aapl",'
          '"why":"x","news_id":null}]}\n```',
        )!;
    expect(d.reading, 'Semana tranquila');
    expect(d.movers.single.ticker, 'AAPL');
    expect(d.headlines, isEmpty);
    expect(WeeklyReportDraft.tryParse('no json'), isNull);
  });
}
