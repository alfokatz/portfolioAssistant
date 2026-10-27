// TurnOutcomeReporter: qué manda a la RPC `ai_report_turn_outcome` y que
// nunca rompa el chat (sin red, error del servidor).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/features/assistant/data/turn_outcome_reporter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );

const _report = TurnOutcomeReport(
  turnId: 'turn_12345678',
  outcome: TurnOutcomeKind.fallback,
  reason: 'timeout',
  latency: Duration(milliseconds: 4321),
  answerRejected: true,
  finalRetried: false,
);

void main() {
  group('TurnOutcomeReporter', () {
    test(
      'calls ai_report_turn_outcome with the turn and its outcome',
      () async {
        final requests = <http.Request>[];
        final reporter = TurnOutcomeReporter(
          client: _client((request) async {
            requests.add(request);
            return http.Response('true', 200);
          }),
        );

        await reporter.report(_report);

        final request = requests.single;
        expect(request.url.path, '/rest/v1/rpc/ai_report_turn_outcome');
        expect(jsonDecode(request.body), {
          'p_turn_id': 'turn_12345678',
          'p_outcome': 'fallback',
          'p_reason': 'timeout',
          'p_latency_ms': 4321,
          'p_answer_rejected': true,
          'p_final_retried': false,
        });
      },
    );

    test('a server error or no network never throws', () async {
      final failing = TurnOutcomeReporter(
        client: _client((_) async => http.Response('{"message":"x"}', 500)),
      );
      final offline = TurnOutcomeReporter(
        client: _client((_) async => throw http.ClientException('offline')),
      );

      await expectLater(failing.report(_report), completes);
      await expectLater(offline.report(_report), completes);
    });
  });

  group('TurnOutcomeReport', () {
    test('latency is capped to what the column accepts', () {
      const slow = TurnOutcomeReport(
        turnId: 'turn_12345678',
        outcome: TurnOutcomeKind.answered,
        latency: Duration(minutes: 20),
        answerRejected: false,
        finalRetried: false,
      );

      expect(slow.toParams()['p_latency_ms'], 600000);
    });

    test('outcome values match the SQL check constraint', () {
      expect(TurnOutcomeKind.values.map((k) => k.value), [
        'answered',
        'fallback',
        'paywall',
        'connection_error',
      ]);
    });
  });
}
