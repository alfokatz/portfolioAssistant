// compare_sources y get_daily_brief (spec 2026-11-20 §3.10, §5, §6, §9.19):
// gating por plan antes de llamar, tope de una búsqueda por turno, interruptor
// apagado y brief de hoy. Correr: flutter test test/features/assistant/tools/compare_sources_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/data/web/source_compare_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/report_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/web_tools.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

import '../data/market/commercial_sources_test.dart' show FakeEdgeClient;
import '../fakes/assistant_fakes.dart';

final _ok = EdgeResponse(
  200,
  jsonDecode(
        File('test/fixtures/daily_brief/compare_ok.json').readAsStringSync(),
      )
      as Map<String, Object?>,
);

/// AAPL y NVDA en cartera.
({AssistantToolContext ctx, FakeEdgeClient edge}) _world(
  SubscriptionTier tier, {
  EdgeResponse? response,
  Map<String, Object?>? screen,
  String? turnId,
}) {
  final edge = FakeEdgeClient((_, __) => response ?? _ok);
  final ctx = AssistantToolContext(
    tier: tier,
    summary: heldSummary,
    screenContext: screen,
    turnId: () => turnId,
    data: AssistantDataSources(
      quoteRepository: CountingQuoteRepository(),
      preferences: FakePreferences(),
      sourceCompare: SourceCompareFetcher(client: edge),
    ),
  );
  return (ctx: ctx, edge: edge);
}

Future<Map<String, Object?>> _run(
  AssistantToolContext ctx,
  Map<String, Object?> args,
) => CompareSourcesTool(ctx).run(args);

void main() {
  group('compare_sources por plan', () {
    test('Free: locked (premium si el ticker es suyo, gold si no), sin '
        'llamar al servidor', () async {
      final held = _world(SubscriptionTier.free);
      final r = await _run(held.ctx, {'ticker': 'AAPL'});
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'premium');
      expect(held.ctx.lockedReasons, {PaywallReason.heldNews});
      expect(held.edge.calls, isEmpty);

      final other = _world(SubscriptionTier.free);
      final o = await _run(other.ctx, {'ticker': 'TSLA'});
      expect(o['required_plan'], 'gold');
      expect(other.edge.calls, isEmpty);
    });

    test('Premium: su ticker pasa; uno que no tiene → locked gold (no corta '
        'el turno)', () async {
      final w = _world(SubscriptionTier.premium);
      expect((await _run(w.ctx, {'ticker': 'nvda'}))['status'], 'ok');
      expect(w.edge.calls.single.args['ticker'], 'NVDA');

      final other = _world(SubscriptionTier.premium);
      final r = await _run(other.ctx, {'ticker': 'TSLA'});
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'gold');
      expect(r['reason'], GetNewsTool.notHeldReason);
      expect(other.ctx.lockedReasons, {PaywallReason.goldRequired});
      expect(other.ctx.lockedFeatures, {PlanFeature.news});
      expect(other.edge.calls, isEmpty);
    });

    test('Premium con un tema: locked gold; Gold con un tema: ok', () async {
      final p = _world(SubscriptionTier.premium);
      final r = await _run(p.ctx, {'topic': 'fed_rates'});
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'gold');
      expect(p.edge.calls, isEmpty);

      final g = _world(SubscriptionTier.gold);
      final ok = await _run(g.ctx, {'topic': 'fed_rates'});
      expect(ok['status'], 'ok');
      expect(g.edge.calls.single.args['topic_id'], 'fed_rates');
    });
  });

  group('compare_sources resultado', () {
    test('ok: puntos con medio y link, as_of y la guía de la card', () async {
      final w = _world(SubscriptionTier.gold);
      final r = await _run(w.ctx, {'ticker': 'AAPL'});
      expect(r['status'], 'ok');
      expect(r['as_of'], isNotNull);
      expect(r['searched_at'], '2026-12-02T08:05:00Z');
      expect(r[AnswerGuide.key], contains('QaSourceComparison'));
      expect(r['outlets'], contains('Reuters'));
    });

    test('argumentos inválidos: ninguno, los dos o un tema mal escrito',
        () async {
      final w = _world(SubscriptionTier.gold);
      for (final args in <Map<String, Object?>>[
        {},
        {'ticker': 'AAPL', 'topic': 'fed_rates'},
        {'topic': 'Fed Rates!'},
        {'ticker': 'no es ticker'},
      ]) {
        expect((await _run(w.ctx, args))['reason'], 'invalid_arguments');
      }
      expect(w.edge.calls, isEmpty);
    });

    test('una sola búsqueda por turno, compartida con get_news', () async {
      final w = _world(SubscriptionTier.gold);
      expect((await _run(w.ctx, {'ticker': 'AAPL'}))['status'], 'ok');
      final second = await _run(w.ctx, {'ticker': 'NVDA'});
      expect(second['status'], 'limit');
      expect(second['reason'], 'turn_limit');
      expect(second['as_of'], isNotNull);
      expect(w.edge.calls, hasLength(1));

      final news = _world(SubscriptionTier.gold)..ctx.newsContextCalls = 1;
      expect((await _run(news.ctx, {'ticker': 'AAPL'}))['status'], 'limit');
    });

    test('interruptor apagado: failed disabled y la guía manda a get_news',
        () async {
      final w = _world(
        SubscriptionTier.gold,
        response: const EdgeResponse(403, {
          'error': {'type': 'disabled'},
        }),
      );
      final r = await _run(w.ctx, {'ticker': 'AAPL'});
      expect(r['status'], 'failed');
      expect(r['reason'], 'disabled');
      expect(r[AnswerGuide.key], contains('get_news'));
    });

    test('insufficient_sources y empty: sin card, ofrece los titulares',
        () async {
      final w = _world(
        SubscriptionTier.gold,
        response: EdgeResponse(
          200,
          jsonDecode(
                File(
                  'test/fixtures/daily_brief/compare_insufficient.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>,
        ),
      );
      final r = await _run(w.ctx, {'ticker': 'AAPL'});
      expect(r['status'], 'insufficient_sources');
      expect(r[AnswerGuide.key], isNot(contains('QaSourceComparison (')));
    });

    test('tope mensual: la misma guía que get_news', () async {
      final w = _world(
        SubscriptionTier.gold,
        response: const EdgeResponse(429, {
          'error': {'type': 'monthly_limit'},
        }),
      );
      final r = await _run(w.ctx, {'ticker': 'AAPL'});
      expect(r['status'], 'limit');
      expect(r[AnswerGuide.key], GetNewsTool.monthlyLimitGuide);
    });

    test('la noticia abierta (screen_context.news) enfoca la búsqueda solo '
        'si es del mismo ticker', () async {
      final screen = {
        'screen': 'news_item',
        'news': {
          'title': 't',
          'ticker': 'NVDA',
          'url': 'https://www.reuters.com/a',
        },
      };
      final same = _world(SubscriptionTier.gold, screen: screen);
      await _run(same.ctx, {'ticker': 'NVDA'});
      expect(same.edge.calls.single.args['story_url'],
          'https://www.reuters.com/a');
      final other = _world(SubscriptionTier.gold, screen: screen);
      await _run(other.ctx, {'ticker': 'AAPL'});
      expect(other.edge.calls.single.args.containsKey('story_url'), isFalse);
    });
  });

  group('get_daily_brief', () {
    AssistantToolContext ctx(Future<Map<String, Object?>?> Function()? load) =>
        AssistantToolContext(
          tier: SubscriptionTier.free,
          data: fakeDataSources(),
          loadDailyBrief: load,
        );

    test('ok / not_ready / failed, siempre con as_of cuando responde', () async {
      final ok = await GetDailyBriefTool(
        ctx(() async => {'day': '2026-11-20', 'variant': 'numbers'}),
      ).run({});
      expect(ok['status'], 'ok');
      expect((ok['brief']! as Map)['day'], '2026-11-20');
      expect(ok['as_of'], isNotNull);
      expect(ok[AnswerGuide.key], contains('QaAnswerText'));

      final notReady = await GetDailyBriefTool(ctx(() async => null)).run({});
      expect(notReady['status'], 'not_ready');

      expect(
        (await GetDailyBriefTool(ctx(() async => throw StateError('x'))).run(
          {},
        ))['status'],
        'failed',
      );
      expect((await GetDailyBriefTool(ctx(null)).run({}))['status'], 'failed');
    });
  });
}
