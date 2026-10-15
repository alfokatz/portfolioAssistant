import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_generator.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';
import 'package:portfolio_assistant/features/weekly_report/prompts/weekly_report_prompt.dart';

import 'weekly_report_fixtures.dart';

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

Map<String, Object?> _report({
  String reading = 'Una semana tranquila: AAPL compensó a MSFT.',
}) => {
  'reading': reading,
  'movers': [
    {
      'ticker': 'AAPL',
      'why': 'Coincidió con las buenas reservas del nuevo iPhone.',
      'news_id': 'n1',
    },
  ],
  'headlines': [],
  'investors': [],
  'learn': null,
};

WeeklyReportGenerator _generator(MockClient client) => WeeklyReportGenerator(
  config: AiProxyConfig.fixed(
    Uri.parse('https://x.supabase.co/functions/v1/ai-chat'),
    'jwt',
    anonKey: 'anon',
  ),
  client: client,
  model: 'gpt-4.1-mini',
);

void main() {
  test(
    'one call in report mode, with the fixed prompt and delimited data',
    () async {
      final requests = <http.Request>[];
      final g = _generator(
        MockClient((req) async {
          requests.add(req);
          return _completion(_report());
        }),
      );
      final result = await g.generate(week: fixtureWeek, input: fixtureInput());

      expect(result.rounds, 1);
      expect(result.error, isNull);
      expect(
        result.draft.reading,
        'Una semana tranquila: AAPL compensó a MSFT.',
      );
      final req = requests.single;
      expect(req.headers['x-porty-purpose'], 'weekly_report');
      expect(req.headers['x-porty-report-week'], '2026-09-21');
      expect(req.headers['Authorization'], 'Bearer jwt');
      expect(req.headers['x-porty-turn-id'], startsWith('wr-'));
      final body = jsonDecode(req.body) as Map;
      final messages = body['messages'] as List;
      expect(messages.first['content'], weeklyReportSystemPrompt);
      expect(messages.last['content'], startsWith('<weekly_data>'));
      expect(body.containsKey('tools'), isFalse);
      expect(body['response_format']['type'], 'json_schema');
    },
  );

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
                ? _report(reading: 'Es buen momento para comprar Apple')
                : _report(),
          );
        }),
      );
      final result = await g.generate(week: fixtureWeek, input: fixtureInput());

      expect(result.rounds, 2);
      expect(
        result.draft.reading,
        'Una semana tranquila: AAPL compensó a MSFT.',
      );
      expect(result.remainingIssues, isEmpty);
      final second = bodies.last['messages'] as List;
      expect(second[second.length - 2]['role'], 'assistant');
      expect(second.last['content'], contains('consejo'));
    },
  );

  test(
    'if the rewrite still fails, the bad parts are dropped, the rest stays',
    () async {
      final g = _generator(
        MockClient(
          (_) async => _completion(_report(reading: 'Comprá más Apple ya')),
        ),
      );
      final result = await g.generate(week: fixtureWeek, input: fixtureInput());
      expect(result.rounds, 2);
      expect(result.draft.reading, isNull);
      expect(result.draft.movers, hasLength(1));
      expect(result.remainingIssues, isNotEmpty);
      expect(result.failed, isFalse);
    },
  );

  test('a proxy rejection is reported with its type', () async {
    final g = _generator(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'type': 'not_claimed', 'message': 'x'},
          }),
          409,
        ),
      ),
    );
    final result = await g.generate(week: fixtureWeek, input: fixtureInput());
    expect(result.error, 'not_claimed');
    expect(result.failed, isTrue);
    expect(result.rounds, 1);
  });

  test('an empty portfolio never calls the model', () async {
    var called = false;
    final g = _generator(
      MockClient((_) async {
        called = true;
        return _completion(_report());
      }),
    );
    final result = await g.generate(
      week: fixtureWeek,
      input: WeeklyReportInput(
        numbers: WeeklyPortfolioCalculator.compute(
          week: fixtureWeek,
          lots: const [],
          candles: const {},
        ),
        news: const [],
        upcomingEarnings: const [],
        newsFailed: false,
        earningsFailed: false,
      ),
    );
    expect(called, isFalse);
    expect(result.draft.isEmpty, isTrue);
  });
}
