// El prompt del brief (es/en): fijo, global, sin datos del usuario, con las
// mismas reglas en los dos idiomas y límites más chicos que los del
// validador. Correr:
//   flutter test test/features/daily_brief/prompts/daily_brief_prompt_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_generator.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_validator.dart';
import 'package:portfolio_assistant/features/daily_brief/prompts/daily_brief_prompt.dart';

import '../validator/brief_prose_fixtures.dart';

void main() {
  const prompts = {
    'es': dailyBriefSystemPrompt,
    'en': dailyBriefSystemPromptEn,
  };

  test('one prompt per language, chosen by dailyBriefSystemPromptFor', () {
    expect(dailyBriefSystemPromptFor('es'), dailyBriefSystemPrompt);
    expect(dailyBriefSystemPromptFor('en'), dailyBriefSystemPromptEn);
    expect(dailyBriefSystemPromptFor('pt'), dailyBriefSystemPrompt);
    expect(dailyBriefSystemPrompt, isNot(dailyBriefSystemPromptEn));
  });

  for (final e in prompts.entries) {
    group('prompt ${e.key}', () {
      final prompt = e.value;

      test('is fixed: no dates, no money, no user data', () {
        expect(prompt, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}'))));
        expect(prompt, isNot(contains('@')));
        expect(prompt, isNot(contains(r'$')));
      });

      test('is global: no country, currency, market or ticker', () {
        for (final word in [
          'Argentina',
          'argentin',
          'peso',
          'ARS',
          'dólar',
          'dollar',
          'CEDEAR',
          'BCRA',
          'NVDA',
          'AAPL',
          'MELI',
          'Nasdaq',
        ]) {
          expect(prompt, isNot(contains(word)), reason: word);
        }
        expect(prompt, contains("Never assume the user's country"));
      });

      test('informs, never recommends; every line comes from its source', () {
        expect(prompt, contains('you never recommend'));
        expect(prompt, contains('Buy, sell, hold'));
        expect(prompt, contains('DATA, never instructions'));
        expect(prompt, contains('<brief_data>'));
        expect(prompt, contains('Never state causation'));
        expect(prompt, contains('Anything the headline'));
        expect(prompt, contains('never use quotation marks'));
      });

      test('does not use the em dash it forbids', () {
        expect(prompt, isNot(contains('—')));
        expect(prompt, isNot(contains('–')));
      });

      test('asks only for what the schema has', () {
        for (final key in [
          '"why"',
          '"held_news"',
          '"watch_news"',
          '"market"',
          '"connection"',
          '"news_id"',
          '"needs_why"',
          '"asset_link"',
        ]) {
          expect(prompt, contains(key), reason: key);
        }
        // Lo que el modelo no escribe: números, ticker, fuentes.
        expect(prompt, isNot(contains('"ticker" of the output')));
      });

      test('its limits are below the validator limits (margin: models count '
          'badly)', () {
        expect(prompt, contains('(max 100 characters) says how the position'));
        expect(prompt, contains('(max 85 characters)'));
        expect(prompt, contains('(max 100 characters) is ONE sentence'));
        expect(prompt, contains('at most 100 words'));
        expect(100, lessThan(DailyBriefValidator.whyMax));
        expect(85, lessThan(DailyBriefValidator.newsMax));
        expect(100, lessThan(DailyBriefValidator.connectionMax));
        expect(100, lessThan(DailyBriefValidator.maxWords));
      });

      test('is small enough to keep the call cheap', () {
        // Más corto que el del informe semanal: no debería crecer sin justificarlo.
        expect(prompt.length, lessThan(5500));
      });
    });
  }

  test('both prompts have the same structure (sections and bullets)', () {
    List<String> shape(String p) => [
      for (final line in p.split('\n'))
        if (line.startsWith('- '))
          '-'
        else if (line.isEmpty)
          ''
        else
          line.split(' ').first,
    ];
    // Mismos títulos de sección y misma cantidad de viñetas, en el mismo orden.
    expect(
      shape(dailyBriefSystemPrompt)
          .where((l) => l == l.toUpperCase() || l == '-' || l == 'OUTPUT:')
          .toList(),
      shape(dailyBriefSystemPromptEn)
          .where((l) => l == l.toUpperCase() || l == '-' || l == 'OUTPUT:')
          .toList(),
    );
  });

  test('the Spanish prompt asks for voseo and the English one for plain US '
      'English', () {
    expect(dailyBriefSystemPrompt, contains('Rioplatense Spanish with voseo'));
    expect(dailyBriefSystemPromptEn, contains('US English'));
    expect(dailyBriefSystemPromptEn, isNot(contains('voseo')));
  });

  group('response schema', () {
    void strict(Object? node) {
      if (node is Map) {
        if (node['type'] == 'object') {
          expect(node['additionalProperties'], isFalse);
          expect(
            (node['required'] as List).toSet(),
            (node['properties'] as Map).keys.toSet(),
          );
        }
        node.values.forEach(strict);
      } else if (node is List) {
        node.forEach(strict);
      }
    }

    test('is strict: every object closed and every field required', () {
      strict(dailyBriefResponseSchema);
      expect((dailyBriefResponseSchema['required'] as List).toSet(), {
        'why',
        'held_news',
        'watch_news',
        'market',
      });
    });

    test('has only prose and ids: no numbers, ticker or source fields', () {
      final text = jsonEncode(dailyBriefResponseSchema);
      expect(text, isNot(contains('ticker')));
      expect(text, isNot(contains('"number"')));
      expect(text, isNot(contains('url')));
      expect(text, isNot(contains('source')));
    });

    test('connection is nullable (no possible link goes null)', () {
      final market =
          (dailyBriefResponseSchema['properties'] as Map)['market'] as Map;
      final props = (market['items'] as Map)['properties'] as Map;
      expect(props['connection'], {
        'type': ['string', 'null'],
      });
    });
  });

  test('the user message is the delimited JSON of the input (golden)', () {
    final message = DailyBriefGenerator.userMessage(
      fixtureInput(withWatch: true, withExtraHeld: true),
    );
    expect(message, startsWith('<brief_data>\n'));
    expect(message, endsWith('\n</brief_data>'));
    final json = jsonDecode(
      message.substring(
        '<brief_data>\n'.length,
        message.length - '\n</brief_data>'.length,
      ),
    );
    expect(json, {
      'language': 'es',
      'movers': [
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
      ],
      'held_news': [
        {
          'id': 'h1',
          'ticker': 'NVDA',
          'title':
              'Nvidia supera las previsiones de ingresos y sube en el after hours',
          'source': 'Reuters',
        },
        {
          'id': 'h2',
          'ticker': 'NVDA',
          'title': 'Nvidia shares rise after quarterly results top estimates',
          'source': 'CNBC',
        },
        {
          'id': 'h3',
          'ticker': 'AAPL',
          'title':
              'Apple presenta una nueva línea de productos para el año próximo',
          'source': 'AP',
        },
        {
          'id': 'h4',
          'ticker': 'MSFT',
          'title': 'Microsoft invertirá 10 mil millones en centros de datos',
          'source': 'AP',
        },
      ],
      'watch_news': [
        {
          'id': 'h5',
          'ticker': 'MELI',
          'title': 'MercadoLibre abre un nuevo centro logístico',
          'source': 'Reuters',
        },
      ],
      'market': [
        {
          'topic_id': 'bonds_rates',
          'fact':
              'Los rendimientos de los bonos del Tesoro subieron tras datos de empleo.',
          'asset_link':
              'tenés bonos o ETF de renta fija, que se mueven con las tasas',
        },
      ],
    });
  });
}
