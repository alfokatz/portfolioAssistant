// Generador del brief con un modelo falso: una llamada en modo brief, una
// reescritura con los problemas concretos, nada de llamar sin trabajo, y la
// prosa que consume el controlador. Correr:
//   flutter test test/features/daily_brief/prompts/daily_brief_generator_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_generator.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/daily_brief/prompts/daily_brief_prompt.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

import '../validator/brief_prose_fixtures.dart';

http.Response _completion(Map<String, Object?> content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': jsonEncode(content)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

DailyBriefGenerator _generator(MockClient client) => DailyBriefGenerator(
  config: AiProxyConfig.fixed(
    Uri.parse('https://x.supabase.co/functions/v1/ai-chat'),
    'jwt',
    anonKey: 'anon',
  ),
  client: client,
  model: 'gpt-4.1-mini',
);

Map<String, Object?> _withWhy(String text) {
  final j = goodDraftJson();
  (j['why']! as List)[0] = {'news_id': 'h1', 'text': text};
  return j;
}

void main() {
  test(
    'one call in brief mode, with the fixed prompt and delimited data',
    () async {
      final requests = <http.Request>[];
      final g = _generator(
        MockClient((req) async {
          requests.add(req);
          return _completion(goodDraftJson());
        }),
      );
      final result = await g.generate(day: '2026-12-02', input: fixtureInput());

      expect(result.rounds, 1);
      expect(result.error, isNull);
      expect(result.remainingIssues, isEmpty);
      expect(result.draft.why.map((l) => l.newsId), ['h1', 'h3']);
      final req = requests.single;
      expect(req.headers['x-porty-purpose'], 'daily_brief');
      expect(req.headers['x-porty-brief-day'], '2026-12-02');
      expect(req.headers['Authorization'], 'Bearer jwt');
      expect(
        req.headers['x-porty-turn-id'],
        matches(RegExp(r'^db-[a-z0-9]{20}$')),
      );
      final body = jsonDecode(req.body) as Map;
      final messages = body['messages'] as List;
      expect(messages.first['content'], dailyBriefSystemPrompt);
      expect(messages.last['content'], startsWith('<brief_data>'));
      expect(messages.last['content'], endsWith('</brief_data>'));
      expect(messages.where((m) => m['role'] == 'system'), hasLength(1));
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('stream'), isFalse);
      expect(body['response_format']['type'], 'json_schema');
      expect(body['response_format']['json_schema']['strict'], isTrue);
      // El tope del servidor (maxBriefOutputTokens): no se pide más.
      expect(body['max_completion_tokens'], 900);
    },
  );

  test('the English prompt is used for an English brief', () async {
    String? system;
    final g = _generator(
      MockClient((req) async {
        system =
            ((jsonDecode(req.body) as Map)['messages'] as List).first['content']
                as String;
        return _completion(goodDraftJson());
      }),
    );
    await g.generate(
      day: '2026-12-02',
      input: fixtureInput(language: 'en'),
      language: 'en',
    );
    expect(system, dailyBriefSystemPromptEn);
  });

  test(
    'a draft with problems gets one rewrite with the concrete issues',
    () async {
      final bodies = <Map>[];
      var n = 0;
      final g = _generator(
        MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map);
          n++;
          return _completion(
            n == 1
                ? _withWhy('Es buen momento para comprar NVDA.')
                : goodDraftJson(),
          );
        }),
      );
      final result = await g.generate(day: '2026-12-02', input: fixtureInput());

      expect(result.rounds, 2);
      expect(result.remainingIssues, isEmpty);
      expect(result.rewriteReasons, hasLength(1));
      expect(result.draft.why, hasLength(2));
      final second = bodies.last['messages'] as List;
      expect(second[second.length - 2]['role'], 'assistant');
      expect(second.last['content'], contains('consejo'));
      expect(second.last['content'], contains('why h1'));
    },
  );

  test('the rewrite request speaks English for an English brief', () async {
    var n = 0;
    String? last;
    final g = _generator(
      MockClient((req) async {
        n++;
        final messages = (jsonDecode(req.body) as Map)['messages'] as List;
        last = messages.last['content'] as String;
        return _completion(
          n == 1 ? _withWhy('Rose due to the results.') : goodDraftJson(),
        );
      }),
    );
    await g.generate(
      day: '2026-12-02',
      input: fixtureInput(language: 'en'),
      language: 'en',
    );
    expect(last, startsWith('I reviewed your answer'));
    expect(last, contains('states a cause'));
  });

  test(
    'if the rewrite still fails, the bad parts are dropped and the rest stays',
    () async {
      final g = _generator(
        MockClient((_) async => _completion(_withWhy('Comprá más NVDA ya.'))),
      );
      final result = await g.generate(day: '2026-12-02', input: fixtureInput());
      expect(result.rounds, 2);
      expect(result.draft.why.map((l) => l.newsId), ['h3']);
      expect(result.draft.market, hasLength(1));
      expect(result.remainingIssues, isNotEmpty);
      expect(result.removed, 1);
      expect(result.failed, isFalse);
    },
  );

  test('invalid JSON twice is a failure (nothing to show)', () async {
    var calls = 0;
    final g = _generator(
      MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'no es json'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final result = await g.generate(day: '2026-12-02', input: fixtureInput());
    expect(calls, 2);
    expect(result.error, 'invalid_json');
    expect(result.failed, isTrue);
  });

  test(
    'a proxy rejection is reported with its type, without a second call',
    () async {
      var calls = 0;
      final g = _generator(
        MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'type': 'not_claimed', 'message': 'x'},
            }),
            409,
          );
        }),
      );
      final result = await g.generate(day: '2026-12-02', input: fixtureInput());
      expect(calls, 1);
      expect(result.error, 'not_claimed');
      expect(result.failed, isTrue);
      expect(result.rounds, 1);
    },
  );

  test('a network failure never throws', () async {
    final g = _generator(MockClient((_) async => throw Exception('boom')));
    final result = await g.generate(day: '2026-12-02', input: fixtureInput());
    expect(result.error, 'network');
    expect(result.failed, isTrue);
  });

  test('without a session it does not call the proxy', () async {
    var called = false;
    final g = DailyBriefGenerator(
      config: AiProxyConfig(
        endpoint: Uri.parse('https://x.supabase.co/functions/v1/ai-chat'),
        accessToken: () async => null,
      ),
      client: MockClient((_) async {
        called = true;
        return _completion(goodDraftJson());
      }),
      model: 'm',
    );
    final result = await g.generate(day: '2026-12-02', input: fixtureInput());
    expect(called, isFalse);
    expect(result.error, 'unauthorized');
  });

  group('nothing to write: the model is never called', () {
    test(
      'Free numbers bundle (no headlines, no possible connection)',
      () async {
        var called = false;
        final g = _generator(
          MockClient((_) async {
            called = true;
            return _completion(goodDraftJson());
          }),
        );
        final free = fixtureBundle('bundle_brief_numbers');
        final result = await g.write(
          DailyBriefWritingRequest(
            day: '2026-12-02',
            language: 'es',
            numbers: fixtureNumbers(),
            held: free.held,
            watch: free.watch,
            market: free.market,
            assetClasses: free.assetClasses,
          ),
        );
        expect(called, isFalse);
        expect(result.rounds, 0);
        expect(result.error, isNull);
        expect(result.failed, isFalse);
        expect(result.prose.isEmpty, isTrue);
      },
    );

    test('an empty portfolio (no numbers)', () async {
      var called = false;
      final g = _generator(
        MockClient((_) async {
          called = true;
          return _completion(goodDraftJson());
        }),
      );
      final input = fixtureInput();
      final result = await g.generate(
        day: '2026-12-02',
        input: DailyBriefInput(
          language: 'es',
          numbers: DailyBriefNumbers.empty,
          held: input.held,
        ),
      );
      expect(called, isFalse);
      expect(result.draft.isEmpty, isTrue);
    });
  });

  group('DailyBriefWriter', () {
    test('write returns the prose the controller composes, with the ticker '
        'taken from the headline', () async {
      final g = _generator(
        MockClient((_) async => _completion(goodDraftJson())),
      );
      final writing = await g.write(fixtureRequest());
      expect(writing.failed, isFalse);
      expect(writing.rounds, 1);
      expect(writing.removedItems, 0);
      expect(writing.prose.why.map((l) => (l.ticker, l.newsId)), [
        ('NVDA', 'h1'),
        ('AAPL', 'h3'),
      ]);
      expect(writing.prose.connections.keys, ['bonds_rates']);
    });

    test('the prose composes into a full brief with outlet and link on every '
        'line (end to end with the fixture)', () async {
      final g = _generator(
        MockClient((_) async => _completion(goodDraftJson())),
      );
      final bundle = fixtureBundle();
      final writing = await g.write(fixtureRequest(bundle: bundle));
      final brief = DailyBrief.compose(
        day: '2026-12-02',
        lang: 'es',
        now: DateTime.utc(2026, 12, 2, 8),
        numbers: fixtureNumbers(),
        bundle: bundle,
        variant: DailyBriefVariant.full,
        prose: writing.prose,
      );
      expect(brief.why, hasLength(2));
      for (final line in brief.why) {
        final source = brief.sourceOf(line.newsId);
        expect(source, isNotNull);
        expect(source!.source, isNotEmpty);
        expect(source.url, startsWith('https://'));
      }
      expect(brief.market, hasLength(3));
      final withConnection = brief.market.where((m) => m.connection != null);
      expect(withConnection.single.topicId, 'bonds_rates');
      // Cada hecho de mercado tiene medio y link.
      for (final m in brief.market) {
        expect(
          m.sourceIds.every((id) => brief.sources[id]?.url != null),
          isTrue,
        );
      }
    });

    test(
      'a failed call is a failed writing (the controller falls back to numbers)',
      () async {
        final g = _generator(MockClient((_) async => http.Response('{}', 500)));
        final writing = await g.write(fixtureRequest());
        expect(writing.failed, isTrue);
        expect(writing.error, 'http_500');
        expect(writing.rounds, 1);
      },
    );

    test('the removed items are reported', () async {
      final g = _generator(
        MockClient((_) async => _completion(_withWhy('Comprá más NVDA ya.'))),
      );
      final writing = await g.write(fixtureRequest());
      expect(writing.removedItems, 1);
      expect(writing.rounds, 2);
      expect(writing.failed, isFalse);
    });
  });
}
