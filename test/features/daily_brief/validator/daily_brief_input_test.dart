// Lo que ve el modelo del brief: sin cifras, solo lo que cuelga de un titular
// y la conexión de mercado solo con la clase de activo que el usuario tiene.
// Correr: flutter test test/features/daily_brief/validator/daily_brief_input_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_prose_rules.dart';

import 'brief_prose_fixtures.dart';

void main() {
  group('DailyBriefInput', () {
    test('the prompt JSON has no figures: words for move, size and weight', () {
      final json = fixtureInput(withWatch: true).toPromptJson();
      expect(ReportProseRules.numbersIn(json), isEmpty);
      expect(json['language'], 'es');
      expect(json['movers'], [
        {
          'ticker': 'NVDA',
          'direction': 'up',
          'size': 'large',
          'weight': 'medium',
          'needs_why': true,
        },
        {
          'ticker': 'AAPL',
          'direction': 'down',
          'size': 'moderate',
          'weight': 'medium',
          'needs_why': true,
        },
        {
          'ticker': 'VOO',
          'direction': 'flat',
          'size': 'small',
          'weight': 'large',
          'needs_why': false,
        },
      ]);
      expect((json['held_news'] as List).map((h) => (h as Map)['id']), [
        'h1',
        'h2',
        'h3',
      ]);
      expect((json['watch_news'] as List).single, {
        'id': 'h5',
        'ticker': 'MELI',
        'title': 'MercadoLibre abre un nuevo centro logístico',
        'source': 'Reuters',
      });
    });

    test('only movers with a held headline need a why', () {
      final input = fixtureInput();
      expect(input.whyMovers.map((m) => m.ticker), ['NVDA', 'AAPL']);
    });

    test('a watch headline never makes a mover need a why', () {
      final input = fixtureInput(withWatch: true);
      expect(input.whyMovers.map((m) => m.ticker), ['NVDA', 'AAPL']);
    });

    test('the connection is offered only for a held asset class, with the '
        'fixed asset_link of the topic', () {
      final held = fixtureInput();
      expect(held.connectable.map((f) => f.topicId), ['bonds_rates']);
      final market = (held.toPromptJson()['market'] as List).single as Map;
      expect(market['topic_id'], 'bonds_rates');
      expect(market['asset_link'], contains('renta fija'));

      final noBonds = fixtureInput(assetClasses: const {'equity'});
      expect(noBonds.connectable, isEmpty);
      expect(noBonds.toPromptJson()['market'], isEmpty);
    });

    test('a fact without topic or without link is never connectable', () {
      final input = fixtureInput(bundle: fixtureBundle('bundle_brief_numbers'));
      expect(input.connectable, isEmpty);
    });

    test('with nothing to write there is no work (no LLM call)', () {
      final free = fixtureInput(bundle: fixtureBundle('bundle_brief_numbers'));
      // Free: sin titulares y sin conexión posible.
      expect(
        DailyBriefInput(
          language: 'es',
          numbers: free.numbers,
          market: free.market,
          assetClasses: const {'equity'},
        ).hasWork,
        isFalse,
      );
      expect(fixtureInput().hasWork, isTrue);
      // Solo conexión de mercado también es trabajo.
      expect(
        DailyBriefInput(
          language: 'es',
          numbers: free.numbers,
          market: fixtureInput().market,
          assetClasses: const {'bond'},
        ).hasWork,
        isTrue,
      );
    });

    test('fromRequest keeps the language (anything but en is es)', () {
      expect(DailyBriefInput.fromRequest(fixtureRequest()).language, 'es');
      expect(
        DailyBriefInput.fromRequest(fixtureRequest(language: 'en')).language,
        'en',
      );
    });

    test('bands', () {
      expect(DailyBriefInput.direction(0.04), 'flat');
      expect(DailyBriefInput.direction(-0.5), 'down');
      expect(DailyBriefInput.size(0.99), 'small');
      expect(DailyBriefInput.size(1), 'moderate');
      expect(DailyBriefInput.size(-3), 'large');
      expect(DailyBriefInput.weight(4.9), 'small');
      expect(DailyBriefInput.weight(20), 'large');
    });
  });
}
