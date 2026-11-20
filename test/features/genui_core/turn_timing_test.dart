import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_timing.dart';

void main() {
  test('parses Server-Timing and ignores what does not fit the format', () {
    expect(
      TurnTiming.parseServerTiming('auth;dur=12.6, begin;dur=40, oai;dur=790'),
      {'auth': 13, 'begin': 40, 'oai': 790},
    );
    expect(
      TurnTiming.parseServerTiming('auth;desc="x", ;dur=4, BAD;dur=1, x'),
      isEmpty,
    );
    expect(TurnTiming.parseServerTiming(''), isEmpty);
  });

  test('pre_ms is the time until the first request; server timing goes to '
      'the round in course', () {
    final clock = _FakeClock();
    final timing = TurnTiming(clock: clock);
    clock.ms = 300;
    final first = timing.startRound();
    timing.serverTiming('auth;dur=5', 'sa-east-1');
    clock.ms = 1500;
    timing.endRound(first, 'tools');
    clock.ms = 2100;
    timing.tools.add(const TimedTool('get_quote', 580, 'ok'));
    final second = timing.startRound();
    clock.ms = 2400;
    timing.textSeen();
    clock.ms = 3000;
    timing.textSeen(); // solo cuenta el primero
    clock.ms = 7000;
    timing.endRound(second, 'answer');
    timing.ready();

    final props = timing.toProps(result: 'answered');
    expect(props['pre_ms'], 300);
    expect(props['first_text_ms'], 2400);
    expect(props['ready_ms'], 7000);
    expect(props['region'], 'sa-east-1');
    expect(props['rounds'], [
      {
        'kind': 'tools',
        'start_ms': 300,
        'ms': 1200,
        'server': {'auth': 5},
      },
      {'kind': 'answer', 'start_ms': 2100, 'ms': 4900},
    ]);
    expect(props['tools'], [
      {'name': 'get_quote', 'ms': 580, 'status': 'ok'},
    ]);
  });

  test('a turn whose jsonb would not fit in product_events (2 KB) drops the proxy '
      'details, not the event', () {
    final timing = TurnTiming();
    for (var i = 0; i < 12; i++) {
      final r = timing.startRound();
      timing.serverTiming(
        [
          for (final name in [
            'authentication',
            'preparation',
            'begin_request',
            'upstream_header',
            'upstream_bodies',
            'openai_process',
            'record_rounds',
          ])
            '$name;dur=1234',
        ].join(', '),
        'us-east-1',
      );
      timing.endRound(r, 'tools');
    }
    for (var i = 0; i < 12; i++) {
      timing.tools.add(TimedTool('get_something_long_$i', 100, 'ok'));
    }
    // Con los tramos del proxy no entraría.
    expect(
      jsonEncode([
        for (final r in timing.rounds.take(8)) r.toJson(),
        for (final t in timing.tools.take(8)) t.toJson(),
      ]).length,
      greaterThan(1150),
    );
    final props = timing.toProps(result: 'answered');
    expect(jsonEncode(props).length, lessThan(1150));
    expect(props['round_count'], 12);
    expect((props['rounds'] as List), hasLength(8));
    expect((props['rounds'] as List).first, isNot(contains('server')));
  });
}

class _FakeClock implements Stopwatch {
  int ms = 0;

  @override
  int get elapsedMilliseconds => ms;

  @override
  void start() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
