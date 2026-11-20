// Propiedades del validador del brief: con cualquier borrador del modelo, lo
// que queda es siempre mostrable. Correr:
//   flutter test test/features/daily_brief/validator/daily_brief_validator_properties_test.dart
// Si falla: PROPERTY_SEED=<n> flutter test <archivo>.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_draft.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_validator.dart';

import '../../../helpers/property.dart';
import 'brief_prose_fixtures.dart';

const _texts = [
  'Subió bastante el día que la empresa presentó resultados.',
  'Anunció una inversión en centros de datos.',
  'Es buen momento para comprar más.',
  'Subió por los buenos resultados.',
  'Informó que abre un nuevo centro, aunque no tenés MELI.',
  'Habla de tu cartera y de lo que tenés.',
  'Dijo "un gran año" en su informe.',
  'Subió 17 por ciento ese día.',
  'No hay resultados todavía.',
  'Tiene mucha exposición a esa empresa.',
  'Shares and its stock with the news.',
  'se dio a conocer lo que se dijo de la firma en el acto de ese día en la bolsa',
  'Tenés bonos o ETF de renta fija, que se mueven con las tasas.',
  '',
];

const _ids = ['h1', 'h2', 'h3', 'h4', 'h5', 'zz'];
const _topics = ['bonds_rates', 'fed_rates', 'crypto'];

DailyBriefDraft _randomDraft(Random r) {
  String text() => _texts[r.nextInt(_texts.length)];
  List<DraftBriefLine> lines() => [
    for (var i = 0; i < r.nextInt(6); i++)
      DraftBriefLine(newsId: _ids[r.nextInt(_ids.length)], text: text()),
  ];
  return DailyBriefDraft(
    why: lines(),
    held: lines(),
    watch: lines(),
    market: [
      for (var i = 0; i < r.nextInt(4); i++)
        DraftConnection(
          topicId: _topics[r.nextInt(_topics.length)],
          connection: r.nextBool() ? null : text(),
        ),
    ],
  );
}

int _words(Iterable<String> texts) => texts
    .map(
      (t) => t.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
    )
    .fold(0, (a, b) => a + b);

void main() {
  final input = fixtureInput(withWatch: true, withExtraHeld: true);
  final heldIds = input.held.map((h) => h.id).toSet();
  final watchIds = input.watch.map((h) => h.id).toSet();
  final tickerById = {
    for (final h in [...input.held, ...input.watch]) h.id: h.ticker,
  };

  property<DailyBriefDraft>(
    'what the validator keeps is always showable',
    generate: _randomDraft,
    check: (draft) {
      final r = DailyBriefValidator.review(draft, input);
      final kept = r.draft;
      // Ids del tipo correcto.
      expect(kept.why.every((l) => heldIds.contains(l.newsId)), isTrue);
      expect(kept.held.every((l) => heldIds.contains(l.newsId)), isTrue);
      expect(kept.watch.every((l) => watchIds.contains(l.newsId)), isTrue);
      // Un por qué solo de quien lo necesita, una línea por ticker.
      final why = {for (final m in input.whyMovers) m.ticker};
      final whyTickers = kept.why.map((l) => tickerById[l.newsId]!).toList();
      expect(whyTickers.every(why.contains), isTrue);
      expect(whyTickers.toSet(), hasLength(whyTickers.length));
      final heldTickers = kept.held.map((l) => tickerById[l.newsId]!).toList();
      expect(heldTickers.toSet(), hasLength(heldTickers.length));
      expect(heldTickers.toSet().intersection(whyTickers.toSet()), isEmpty);
      expect(kept.held.length, lessThanOrEqualTo(DailyBriefInput.maxHeld));
      expect(kept.watch.length, lessThanOrEqualTo(DailyBriefInput.maxWatch));
      // Conexión solo de temas posibles y nunca vacía.
      final topics = input.connectable.map((f) => f.topicId).toSet();
      expect(
        kept.market.every(
          (m) => topics.contains(m.topicId) && m.connection != null,
        ),
        isTrue,
      );
      // Tope de palabras.
      expect(
        _words([
          ...kept.why.map((l) => l.text),
          ...kept.held.map((l) => l.text),
          ...kept.watch.map((l) => l.text),
          ...kept.market.map((m) => m.connection!),
        ]),
        lessThanOrEqualTo(DailyBriefValidator.maxWords),
      );
      // Contabilidad de lo sacado.
      expect(r.removed, draft.itemCount - kept.itemCount);
      expect(r.removed, greaterThanOrEqualTo(0));
    },
  );

  property<DailyBriefDraft>(
    'reviewing what was kept again finds nothing to fix and changes nothing',
    generate: _randomDraft,
    check: (draft) {
      final first = DailyBriefValidator.review(draft, input).draft;
      final again = DailyBriefValidator.review(first, input);
      expect(again.issues, isEmpty);
      expect(again.removed, 0);
      expect(again.draft.toJson(), first.toJson());
    },
  );
}
