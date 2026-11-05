// get_news según el plan (spec 2026-11-05 §3.4): Gold todo, Premium solo lo
// que tiene en cartera, Free nada; y el tope mensual de búsquedas.
// Correr: flutter test test/features/assistant/tools/get_news_plan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_context_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/web/web_search_client.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/web_tools.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/gdelt_headlines_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';

import '../data/market/commercial_sources_test.dart' show FakeEdgeClient;
import '../fakes/assistant_fakes.dart';

class _NoBrands implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

const _contextOk = EdgeResponse(200, {
  'status': 'ok',
  'summary': ['AAPL presentó un producto.'],
  'citations': [
    {'title': 'T', 'url': 'https://www.reuters.com/a', 'source': 'Reuters'},
  ],
});

/// AAPL y NVDA en cartera (`heldSummary`).
({AssistantToolContext ctx, FakeEdgeClient edge}) _world(
  SubscriptionTier tier, {
  NewsProvider provider = NewsProvider.v2,
  EdgeResponse context = _contextOk,
}) {
  final edge = FakeEdgeClient(
    (path, _) =>
        path == 'news-context'
            ? context
            : const EdgeResponse(200, {'status': 'empty', 'by_ticker': {}}),
  );
  final ctx = AssistantToolContext(
    tier: tier,
    newsProvider: provider,
    summary: heldSummary,
    data: AssistantDataSources(
      quoteRepository: CountingQuoteRepository(),
      preferences: FakePreferences(),
      newsProvider: provider,
      news: NewsFetcher(
        headlines: GdeltHeadlinesRepositoryImpl(
          client: edge,
          batchWindow: Duration.zero,
        ),
        brandRepository: _NoBrands(),
      ),
      newsContext: NewsContextClient(client: edge),
    ),
  );
  return (ctx: ctx, edge: edge);
}

Future<Map<String, Object?>> _run(
  AssistantToolContext ctx,
  List<String> tickers,
) => GetNewsTool(ctx).run({'tickers': tickers});

void main() {
  group('get_news por plan', () {
    test('Free con un ticker que tiene: locked heldNews (Premium) y corta '
        'el turno', () async {
      final w = _world(SubscriptionTier.free);
      final r = await _run(w.ctx, ['AAPL']);
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'premium');
      expect(w.ctx.lockedReasons, {PaywallReason.heldNews});
      expect(w.ctx.lockedFeatures, {PlanFeature.heldNews});
      expect(w.edge.calls, isEmpty);
    });

    test('Free con un ticker ajeno: locked de Gold', () async {
      final w = _world(SubscriptionTier.free);
      final r = await _run(w.ctx, ['TSLA']);
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'gold');
      expect(w.ctx.lockedReasons, {PaywallReason.goldRequired});
      expect(w.ctx.lockedFeatures, {PlanFeature.news});
    });

    test('Free mixto: alcanza con que haya uno que tiene para ofrecer '
        'Premium', () async {
      final w = _world(SubscriptionTier.free);
      final r = await _run(w.ctx, ['TSLA', 'aapl']);
      expect(r['required_plan'], 'premium');
      expect(w.ctx.lockedReasons, {PaywallReason.heldNews});
    });

    test('Premium con un ticker que tiene: se sirve', () async {
      final w = _world(SubscriptionTier.premium);
      final r = await _run(w.ctx, ['AAPL']);
      expect(r['status'], 'ok');
      expect(r.containsKey('locked_tickers'), isFalse);
      expect(w.ctx.lockedReasons, isEmpty);
      expect(w.ctx.lockedFeatures, isEmpty);
      expect(w.edge.calls.any((c) => c.path == 'news-context'), isTrue);
    });

    test('Premium con un ticker ajeno: locked not_held de Gold, sin cortar '
        'el turno y sin gastar búsquedas', () async {
      final w = _world(SubscriptionTier.premium);
      final r = await _run(w.ctx, ['TSLA']);
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'gold');
      expect(r['reason'], 'not_held');
      expect(r['as_of'], isA<String>());
      expect(w.ctx.lockedReasons, {PaywallReason.goldRequired});
      expect(w.ctx.lockedFeatures, {PlanFeature.news});
      expect(w.edge.calls, isEmpty);
      expect(w.ctx.newsContextCalls, 0);
    });

    test('Premium mixto: se sirve lo que tiene y lo ajeno queda en '
        'locked_tickers con su guía', () async {
      final w = _world(SubscriptionTier.premium);
      final r = await _run(w.ctx, ['AAPL', 'TSLA']);
      expect(r['status'], 'ok');
      expect(r['locked_tickers'], ['TSLA']);
      expect(r['required_plan'], 'gold');
      expect(r[AnswerGuide.key], GetNewsTool.lockedTickersGuide);
      expect(w.ctx.lockedFeatures, contains(PlanFeature.news));
      final sent = w.edge.calls.singleWhere((c) => c.path == 'news-context');
      expect(sent.args['tickers'], ['AAPL']);
    });

    test('Gold: todo se sirve, sin locked_tickers', () async {
      final w = _world(SubscriptionTier.gold);
      final r = await _run(w.ctx, ['AAPL', 'TSLA']);
      expect(r['status'], 'ok');
      expect(r.containsKey('locked_tickers'), isFalse);
      expect(w.ctx.lockedFeatures, isEmpty);
    });

    test('con el camino legacy, Premium no tiene noticias (ni de lo suyo)',
        () async {
      final w = _world(SubscriptionTier.premium, provider: NewsProvider.legacy);
      final r = await _run(w.ctx, ['AAPL']);
      expect(r['status'], 'locked');
      expect(r['required_plan'], 'gold');
      expect(r.containsKey('reason'), isFalse);
      expect(w.ctx.lockedReasons, {PaywallReason.goldRequired});
    });

    test('tope mensual de búsquedas: responde con los titulares y la guía '
        'sin hablar de planes', () async {
      final w = _world(
        SubscriptionTier.premium,
        context: const EdgeResponse(429, {
          'error': {'type': 'monthly_limit'},
        }),
      );
      final r = await _run(w.ctx, ['AAPL']);
      expect((r['context'] as Map)['status'], 'limit');
      expect((r['context'] as Map)['reason'], 'monthly_limit');
      expect(r[AnswerGuide.key], GetNewsTool.monthlyLimitGuide);
      expect(r[AnswerGuide.key], contains('do not mention plans'));
      // Sin paywall: es un tope de costo.
      expect(w.ctx.lockedReasons, isEmpty);
    });

    test('el tope diario no lleva la guía del mensual', () async {
      final w = _world(
        SubscriptionTier.gold,
        context: const EdgeResponse(429, {
          'error': {'type': 'daily_limit'},
        }),
      );
      final r = await _run(w.ctx, ['AAPL']);
      expect((r['context'] as Map)['reason'], 'daily_limit');
      expect(r.containsKey(AnswerGuide.key), isFalse);
    });
  });

  group('search_web: tope mensual', () {
    test('monthly_limit llega como limit con su guía', () async {
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 600));
      dio.httpClientAdapter = _Adapter(
        429,
        '{"error":{"type":"monthly_limit"}}',
      );
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(
          webSearch: WebSearchClient(
            dio: dio,
            url: 'http://x/web-search',
            accessToken: () async => 't',
            anonKey: 'k',
          ),
        ),
      );
      final r = await SearchWebTool(ctx).run({'query': 'precio macbook'});
      expect(r['status'], 'limit');
      expect(r['reason'], 'monthly_limit');
      expect(r[AnswerGuide.key], SearchWebTool.monthlyLimitGuide);
      expect(ctx.lockedReasons, isEmpty);
    });
  });

  group('NewsContextClient', () {
    test('monthly_limit se mapea a limit/monthly_limit', () async {
      final client = NewsContextClient(
        client: FakeEdgeClient(
          (_, _) => const EdgeResponse(429, {
            'error': {'type': 'monthly_limit'},
          }),
        ),
      );
      expect(await client.fetch(['AAPL']), {
        'status': 'limit',
        'reason': 'monthly_limit',
      });
    });
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}
