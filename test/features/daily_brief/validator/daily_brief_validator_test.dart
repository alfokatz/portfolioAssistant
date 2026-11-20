// Validador del brief: las reglas del semanal (extraídas a ReportProseRules)
// más las propias, en es y en. Correr:
//   flutter test test/features/daily_brief/validator/daily_brief_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_draft.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_validator.dart';

import 'brief_prose_fixtures.dart';

DailyBriefDraft _draft({
  List<DraftBriefLine> why = const [],
  List<DraftBriefLine> held = const [],
  List<DraftBriefLine> watch = const [],
  List<DraftConnection> market = const [],
}) => DailyBriefDraft(why: why, held: held, watch: watch, market: market);

DraftBriefLine _line(String id, String text) =>
    DraftBriefLine(newsId: id, text: text);

BriefHeadline _headline(
  String id,
  String ticker, {
  bool watch = false,
  String title = 'Titular de prueba sin cifras',
}) => BriefHeadline(
  id: id,
  ticker: ticker,
  watch: watch,
  title: title,
  source: 'Reuters',
  domain: 'reuters.com',
  url: 'https://www.reuters.com/x-$id',
);

void main() {
  group('DailyBriefValidator (es)', () {
    final input = fixtureInput(withWatch: true, withExtraHeld: true);

    DailyBriefReview review(DailyBriefDraft d, {DailyBriefInput? i}) =>
        DailyBriefValidator.review(d, i ?? input);

    test('a good draft passes untouched', () {
      final r = review(
        _draft(
          why: [
            _line(
              'h1',
              'Subió bastante el día que la empresa presentó resultados.',
            ),
            _line('h3', 'Bajó un poco el día que presentó nuevos productos.'),
          ],
          held: [_line('h4', 'Invertirá 10 mil millones en centros de datos.')],
          watch: [_line('h5', 'Abre un nuevo centro logístico.')],
          market: const [
            DraftConnection(
              topicId: 'bonds_rates',
              connection:
                  'Tenés bonos o ETF de renta fija, que se mueven con las tasas.',
            ),
          ],
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.removed, 0);
      expect(r.draft.why, hasLength(2));
      expect(r.draft.held.single.newsId, 'h4');
      expect(r.draft.watch.single.newsId, 'h5');
      expect(r.draft.market.single.connection, contains('renta fija'));
    });

    group('rules shared with the weekly report', () {
      final cases = <String, String>{
        'states a cause': 'Subió por los buenos resultados de la empresa.',
        'gives advice': 'Es buen momento para comprar más acciones.',
        'valuation judgment': 'La acción está barata y sobrevaluada a la vez.',
        'relays a third party advice': 'Un banco recomendó comprar la acción.',
        'claims an absence': 'No hay reportes de resultados todavía.',
        'jargon': 'Tiene mucha exposición a esa empresa.',
        'quotes': 'La empresa dijo "un gran año" en su informe.',
        'a figure that is not in the data': 'Subió 17 por ciento ese día.',
      };
      for (final e in cases.entries) {
        test('why: ${e.key} is dropped with an issue', () {
          final r = review(_draft(why: [_line('h1', e.value)]));
          expect(r.draft.why, isEmpty, reason: e.value);
          expect(r.issues, hasLength(1), reason: e.value);
          expect(r.issues.single, startsWith('why h1 '));
          expect(r.issues.single, contains(e.value));
          expect(r.removed, 1);
        });
      }

      test('the cause message suggests the daily wording', () {
        final r = review(
          _draft(why: [_line('h1', 'Subió por los resultados.')]),
        );
        expect(r.issues.single, contains('el día que'));
      });

      test('held_news and watch_news get the same rules', () {
        final r = review(
          _draft(
            held: [_line('h4', 'Es buen momento para comprar Microsoft.')],
            watch: [_line('h5', 'Subió debido a una nueva alianza.')],
          ),
        );
        expect(r.draft.held, isEmpty);
        expect(r.draft.watch, isEmpty);
        expect(r.issues, hasLength(2));
      });

      test('a figure of the cited headline is backed, others are not', () {
        final ok = review(
          _draft(held: [_line('h4', 'Invertirá 10 mil millones en datos.')]),
        );
        expect(ok.issues, isEmpty);
        final bad = review(
          _draft(held: [_line('h4', 'Invertirá 12 mil millones en datos.')]),
        );
        expect(bad.draft.held, isEmpty);
        expect(bad.issues.single, contains('12'));
      });

      test('a Spanish brief with an English line is rejected', () {
        final r = review(
          _draft(held: [_line('h4', 'Microsoft shares and its data centers.')]),
        );
        expect(r.draft.held, isEmpty);
        expect(r.issues.single, contains('español'));
      });

      test('a link is rejected: the app shows the outlet link', () {
        final r = review(
          _draft(
            held: [_line('h4', 'Mirá https://example.com/nota sobre eso.')],
          ),
        );
        expect(r.draft.held, isEmpty);
        expect(r.issues.single, contains('link'));
      });

      test('too long lines are rejected with the limit', () {
        final r = review(_draft(why: [_line('h1', 'a ' * 70)]));
        expect(r.issues.single, contains('${DailyBriefValidator.whyMax}'));
      });
    });

    group('ids and roles', () {
      test(
        'why: unknown id, watch id and a ticker without need are rejected',
        () {
          final r = review(
            _draft(
              why: [
                _line('zz', 'Subió bastante ese día.'),
                _line('h5', 'Subió bastante ese día.'),
                _line('h4', 'No se movió casi nada ese día.'),
              ],
            ),
          );
          expect(r.draft.why, isEmpty);
          expect(r.issues, hasLength(3));
          expect(r.issues[0], contains('zz'));
          expect(r.issues[1], contains('h5'));
          expect(r.issues[2], contains('MSFT'));
          expect(r.removed, 3);
        },
      );

      test('one why per ticker, the second headline of NVDA is ignored', () {
        final r = review(
          _draft(
            why: [
              _line('h1', 'Subió bastante el día que presentó resultados.'),
              _line('h2', 'Subió bastante tras las cifras del trimestre.'),
            ],
          ),
        );
        expect(r.draft.why.map((l) => l.newsId), ['h1']);
        // Duplicado sin issue: no se pide reescribir por eso.
        expect(r.issues, isEmpty);
        expect(r.removed, 1);
      });

      test('held_news never repeats a ticker that already has a why', () {
        final r = review(
          _draft(
            why: [
              _line('h1', 'Subió bastante el día que presentó resultados.'),
            ],
            held: [
              _line('h2', 'Presenta cifras mejores a las previstas.'),
              _line('h4', 'Anuncia una inversión en centros de datos.'),
            ],
          ),
        );
        expect(r.draft.held.map((l) => l.newsId), ['h4']);
        expect(r.issues, isEmpty);
      });

      test(
        'held_news must be a held headline, watch_news a watch headline',
        () {
          final r = review(
            _draft(
              held: [_line('h5', 'Abre un centro logístico.')],
              watch: [_line('h4', 'Anuncia una inversión.')],
            ),
          );
          expect(r.draft.held, isEmpty);
          expect(r.draft.watch, isEmpty);
          expect(r.issues, hasLength(2));
        },
      );

      test('at most ${DailyBriefInput.maxHeld} held_news, one per ticker', () {
        final many = DailyBriefInput(
          language: 'es',
          numbers: fixtureNumbers(),
          held: [
            for (final t in ['AA', 'BB', 'CC', 'DD', 'EE']) _headline('h$t', t),
          ],
        );
        final r = DailyBriefValidator.review(
          _draft(
            held: [
              for (final t in ['AA', 'BB', 'CC', 'DD', 'EE'])
                _line('h$t', 'Anunció una novedad de $t.'),
              _line('hAA', 'Otra línea de la misma empresa.'),
            ],
          ),
          many,
        );
        expect(r.draft.held, hasLength(DailyBriefInput.maxHeld));
        expect(r.removed, 3);
      });
    });

    group('watchlist', () {
      test(
        'the "no tenés" clause is stripped without asking for a rewrite',
        () {
          final r = review(
            _draft(
              watch: [
                _line('h5', 'Abre un nuevo centro, aunque no tenés MELI.'),
              ],
            ),
          );
          expect(r.issues, isEmpty);
          expect(r.draft.watch.single.text, 'Abre un nuevo centro.');
        },
      );

      test('talking about the user portfolio is rejected', () {
        final r = review(
          _draft(
            watch: [_line('h5', 'Abre un centro y puede tocar tu cartera.')],
          ),
        );
        expect(r.draft.watch, isEmpty);
        expect(r.issues.single, contains('solo sigue'));
      });
    });

    group('connection', () {
      test('null is always fine', () {
        final r = review(
          _draft(
            market: const [
              DraftConnection(topicId: 'bonds_rates'),
              DraftConnection(topicId: 'fed_rates'),
            ],
          ),
        );
        expect(r.issues, isEmpty);
        expect(r.removed, 0);
      });

      test('only for a topic whose asset class the user holds', () {
        final noBonds = fixtureInput(assetClasses: const {'equity'});
        final r = DailyBriefValidator.review(
          _draft(
            market: const [
              DraftConnection(
                topicId: 'bonds_rates',
                connection: 'Tenés bonos que se mueven con las tasas.',
              ),
            ],
          ),
          noBonds,
        );
        expect(r.draft.market, isEmpty);
        expect(r.issues.single, contains('clase de activo'));
        expect(r.removed, 1);
      });

      test('a topic that is not in the input is rejected', () {
        final r = review(
          _draft(
            market: const [
              DraftConnection(
                topicId: 'crypto',
                connection: 'Tenés cripto que reacciona a las tasas.',
              ),
            ],
          ),
        );
        expect(r.draft.market, isEmpty);
        expect(r.issues, hasLength(1));
      });

      test('it gets the general rules too (no advice, no cause)', () {
        final r = review(
          _draft(
            market: const [
              DraftConnection(
                topicId: 'bonds_rates',
                connection: 'Tenés bonos: conviene comprar más ahora.',
              ),
            ],
          ),
        );
        expect(r.draft.market, isEmpty);
        expect(r.issues.single, contains('consejo'));
      });
    });

    group('word budget', () {
      test('what goes over ${DailyBriefValidator.maxWords} words is dropped, '
          'why first', () {
        final heldTickers = ['AA', 'BB', 'CC'];
        final watchTickers = ['XX', 'YY', 'ZZ'];
        final big = DailyBriefInput(
          language: 'es',
          numbers: fixtureNumbers(),
          held: [
            _headline('h1', 'NVDA'),
            _headline('h3', 'AAPL'),
            for (final t in heldTickers) _headline('h$t', t),
          ],
          watch: [
            for (final t in watchTickers) _headline('w$t', t, watch: true),
          ],
        );
        // 19 palabras por línea (entran en el largo máximo): 8 líneas pasan
        // de 120 palabras.
        const body =
            'se dio a conocer lo que se dijo de la firma en el acto de ese '
            'día en la bolsa';
        final r = DailyBriefValidator.review(
          _draft(
            why: [_line('h1', 'Subió $body.'), _line('h3', 'Bajó $body.')],
            held: [for (final t in heldTickers) _line('h$t', 'Informó $body.')],
            watch: [
              for (final t in watchTickers) _line('w$t', 'Presentó $body.'),
            ],
          ),
          big,
        );
        final words = [
          for (final l in [...r.draft.why, ...r.draft.held, ...r.draft.watch])
            l.text.split(' ').length,
        ].fold(0, (a, b) => a + b);
        expect(words, lessThanOrEqualTo(DailyBriefValidator.maxWords));
        expect(r.draft.why, hasLength(2));
        expect(r.draft.watch.length, lessThan(3));
        expect(r.issues, hasLength(1));
        expect(r.issues.single, contains('${DailyBriefValidator.maxWords}'));
        expect(r.removed, greaterThan(0));
      });
    });
  });

  group('DailyBriefValidator (en)', () {
    final input = fixtureInput(
      language: 'en',
      withWatch: true,
      withExtraHeld: true,
    );

    DailyBriefReview review(DailyBriefDraft d) =>
        DailyBriefValidator.review(d, input);

    test('a good draft passes untouched', () {
      final r = review(
        _draft(
          why: [
            _line('h1', 'Rose a lot the day the company reported results.'),
          ],
          held: [_line('h4', 'Will invest 10 billion in data centers.')],
          watch: [_line('h5', 'Opens a new logistics center.')],
          market: const [
            DraftConnection(
              topicId: 'bonds_rates',
              connection:
                  'You hold bonds or fixed-income ETFs, which follow rates.',
            ),
          ],
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.removed, 0);
    });

    final cases = <String, (String, String)>{
      'states a cause': ('Rose due to the strong results.', 'states a cause'),
      'gives advice': ('It is a good time to buy more.', 'advice'),
      'relays advice': ('Analysts recommend buying the stock.', 'third party'),
      'claims an absence': (
        'There are no earnings reports yet.',
        "doesn't exist",
      ),
      'jargon': ('Has a lot of exposure to that company.', 'jargon'),
      'quotes': ('The company said "a great year" in its report.', 'quotation'),
      'an unbacked figure': ('Rose 17 percent that day.', 'the number 17'),
    };
    for (final e in cases.entries) {
      test('why: ${e.key} is dropped, with an English message', () {
        final r = review(_draft(why: [_line('h1', e.value.$1)]));
        expect(r.draft.why, isEmpty, reason: e.value.$1);
        expect(r.issues.single, contains(e.value.$2), reason: e.value.$1);
      });
    }

    test('the cause message suggests the daily wording', () {
      final r = review(_draft(why: [_line('h1', 'Rose due to results.')]));
      expect(r.issues.single, contains('on the day'));
    });

    test('a watch line that says the user holds it is rejected', () {
      final r = review(
        _draft(watch: [_line('h5', 'Opens a center and you hold MELI.')]),
      );
      expect(r.draft.watch, isEmpty);
      expect(r.issues.single, contains('only follow'));
    });

    test('the "you don\'t hold" clause is stripped silently', () {
      final r = review(
        _draft(
          watch: [
            _line('h5', "Opens a new center, although you don't hold it."),
          ],
        ),
      );
      expect(r.issues, isEmpty);
      expect(r.draft.watch.single.text, 'Opens a new center.');
    });

    test(
      'Spanish text in an English brief is not flagged as English-in-es',
      () {
        // El chequeo de "inglés en un brief en español" no aplica a 'en'.
        final r = review(
          _draft(held: [_line('h4', 'Will invest the data and its centers.')]),
        );
        expect(r.issues, isEmpty);
      },
    );
  });
}
