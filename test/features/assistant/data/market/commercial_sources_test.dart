import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_context_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/market/sec_market_fetchers.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_sources.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/gdelt_headlines_repository_impl.dart';

import '../../fakes/assistant_fakes.dart';

class _NoBrands implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

/// Edge functions falsas: responde por ruta y guarda cada pedido.
class FakeEdgeClient extends PortyEdgeClient {
  FakeEdgeClient(this.respond)
    : super(baseUrl: 'http://edge', accessToken: () async => 'jwt');

  final EdgeResponse Function(String path, Map<String, Object?> args) respond;
  final calls = <({String path, Map<String, Object?> args})>[];

  @override
  Future<EdgeResponse> get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    calls.add((path: path, args: query));
    return respond(path, query);
  }

  @override
  Future<EdgeResponse> post(
    String path,
    Map<String, Object?> body, {
    String? turnId,
  }) async {
    calls.add((path: path, args: body));
    return respond(path, body);
  }
}

const _secEarnings = {
  'status': 'ok',
  'ticker': 'AAPL',
  'company_name': 'Apple Inc.',
  'filer': 'domestic',
  'currency': 'USD',
  'latest_release': {
    'form': '8-K',
    'filed': '2026-07-30',
    'url': 'https://www.sec.gov/Archives/edgar/data/320193/x/ex991.htm',
    'text': 'Apple reports third quarter results...',
    'truncated': true,
  },
  'quarters': [
    {'label': 'T2 FY26', 'end': '2026-03-28', 'revenue': 111184000000, 'eps_diluted': 2.01, 'eps_yoy_pct': 22.6, 'revenue_yoy_pct': 16.6},
    {'label': 'T3 FY26', 'end': '2026-06-27', 'revenue': 109417000000, 'eps_diluted': 2.02, 'eps_year_ago': 1.57, 'eps_yoy_pct': 28.7, 'revenue_yoy_pct': 16.0},
  ],
  'years': [],
  'next_report': {'date': '2026-10-29', 'estimated': true, 'basis': 'same_quarter_last_year'},
  'source': {'name': 'SEC EDGAR', 'url': 'https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=0000320193'},
};

Map<String, Object?> _secFundamentals(String currency) => {
  'status': 'ok',
  'ticker': 'AAPL',
  'company_name': 'Apple Inc.',
  'industry': 'Electronic Computers',
  'currency': currency,
  'ttm_basis': '4q',
  'ttm_end': '2026-06-27',
  'revenue_ttm': 400e9,
  'net_income_ttm': 100e9,
  'eps_diluted_ttm': 7.5,
  'ebitda_ttm': 150e9,
  'dividends_per_share_ttm': 1.5,
  'net_margin_pct': 25.0,
  'equity': 100e9,
  'long_term_debt': 80e9,
  'cash': 30e9,
  'shares_outstanding': 15e9,
  'source': {'name': 'SEC EDGAR', 'url': 'https://www.sec.gov/x'},
};

void main() {
  group('SecEarningsFetcher', () {
    test('maps SEC earnings: estimated next report, EPS vs. a year earlier, '
        'press release, no consensus', () async {
      final edge = FakeEdgeClient(
        (path, args) => switch (args['ticker']) {
          'AAPL' => const EdgeResponse(200, _secEarnings),
          'ZZZZ' => const EdgeResponse(200, {'status': 'not_found'}),
          _ => const EdgeResponse(403, {
            'error': {'type': 'plan_required'},
          }),
        },
      );
      final result = await SecEarningsFetcher(
        client: edge,
      ).fetch(['AAPL', 'ZZZZ']);

      expect(result['status'], 'ok');
      expect(result['not_in_sec'], ['ZZZZ']);
      final aapl = (result['earnings'] as Map)['AAPL'] as Map;
      expect(aapl['source'], 'SEC EDGAR');
      expect(aapl['next_report'], {
        'date': '2026-10-29',
        'date_label': '29 oct 2026',
        'estimated': true,
      });
      final latest = aapl['latest_result'] as Map;
      expect(latest['eps_actual'], 2.02);
      expect(latest['eps_yoy_pct'], 28.7);
      expect(latest['eps_year_ago'], 1.57);
      expect(latest['revenue_millions'], 109417.0);
      expect(latest['report_date_label'], '30 jul 2026');
      expect(latest.containsKey('eps_estimate'), isFalse);
      expect((aapl['history'] as List).length, 2);
      expect((aapl['press_release'] as Map)['text'], contains('third quarter'));
      expect(edge.calls.first.path, 'sec/earnings');
    });

    test('server says Gold is required → locked', () async {
      final edge = FakeEdgeClient(
        (_, _) => const EdgeResponse(403, {
          'error': {'type': 'plan_required'},
        }),
      );
      final result = await SecEarningsFetcher(client: edge).fetch(['AAPL']);
      expect(result['status'], 'locked');
      expect(result['required_plan'], 'gold');
    });
  });

  group('SecFundamentalsFetcher', () {
    test('USD filer: price ratios computed with the current price', () async {
      final edge = FakeEdgeClient(
        (_, _) => EdgeResponse(200, _secFundamentals('USD')),
      );
      final result = await SecFundamentalsFetcher(
        quotes: CountingQuoteRepository(),
        client: edge,
      ).fetch(['AAPL']);
      final f = (result['fundamentals'] as Map)['AAPL'] as Map;
      // Precio 150 (fake): P/E = 150 / 7,5; valor de mercado = 150 × 15.000 M.
      expect(f['pe_ttm'], 20.0);
      expect(f['market_capitalization'], 2250000.0);
      expect(f['ps_ttm'], 5.6);
      expect(f['dividend_yield_indicated_annual'], 1.0);
      expect(f['payout_ratio_ttm'], 20.0);
      expect(f['net_margin_ttm'], 25.0);
      expect(f.containsKey('forward_pe'), isFalse);
      expect(f.containsKey('beta'), isFalse);
      expect(f['week_52_high'], isNotNull);
    });

    test('non-USD filer (ADR): no ratios mixing currencies', () async {
      final edge = FakeEdgeClient(
        (_, _) => EdgeResponse(200, _secFundamentals('CNY')),
      );
      final result = await SecFundamentalsFetcher(
        quotes: CountingQuoteRepository(),
        client: edge,
      ).fetch(['AAPL']);
      final f = (result['fundamentals'] as Map)['AAPL'] as Map;
      expect(f['currency'], 'CNY');
      expect(f.containsKey('pe_ttm'), isFalse);
      expect(f.containsKey('market_capitalization'), isFalse);
      expect(f['net_margin_ttm'], 25.0);
    });
  });

  group('GdeltHeadlinesRepositoryImpl', () {
    test('tickers asked together go in ONE call (GDELT: 1 request / 5 s)', () async {
      final edge = FakeEdgeClient(
        (_, _) => const EdgeResponse(200, {
          'status': 'ok',
          'by_ticker': {
            'NVDA': [
              {
                'title': 'Nvidia unveils a chip',
                'url': 'https://www.reuters.com/a',
                'source': 'Reuters',
                'domain': 'reuters.com',
                'published_at': '2026-10-10T14:00:00Z',
              },
            ],
            'AAPL': [],
          },
        }),
      );
      final repo = GdeltHeadlinesRepositoryImpl(
        client: edge,
        batchWindow: const Duration(milliseconds: 10),
      );
      final results = await Future.wait([
        repo.getRecentNews('NVDA'),
        repo.getRecentNews('AAPL'),
      ]);
      expect(edge.calls.length, 1);
      expect(edge.calls.single.args['tickers'], 'NVDA,AAPL');
      final nvda = results[0].getOrElse(() => const []);
      expect(nvda.single.headline, 'Nvidia unveils a chip');
      expect(nvda.single.sourceDomain, 'reuters.com');
      expect(nvda.single.imageUrl, isNull);
      expect(results[1].getOrElse(() => const []), isEmpty);
    });

    test('a closed week sends from/to', () async {
      final edge = FakeEdgeClient(
        (_, _) => const EdgeResponse(200, {'status': 'empty', 'by_ticker': {}}),
      );
      await GdeltHeadlinesRepositoryImpl(
        client: edge,
        batchWindow: Duration.zero,
      ).getRecentNews(
        'KO',
        from: DateTime.utc(2026, 10, 5),
        to: DateTime.utc(2026, 10, 10),
      );
      expect(edge.calls.single.args['from'], '2026-10-05');
      expect(edge.calls.single.args['to'], '2026-10-10');
    });
  });

  group('NewsContextClient', () {
    test('summary + clickable sources; limits are not failures', () async {
      var limited = false;
      final edge = FakeEdgeClient(
        (_, _) =>
            limited
                ? const EdgeResponse(429, {
                  'error': {'type': 'daily_limit'},
                })
                : const EdgeResponse(200, {
                  'status': 'ok',
                  'summary': ['Nvidia presentó un chip.', 'Subió 4%.'],
                  'citations': [
                    {
                      'title': 'Nvidia unveils a chip',
                      'url': 'https://www.reuters.com/a',
                      'source': 'Reuters',
                    },
                  ],
                  'as_of': '2026-10-11T12:00:00Z',
                }),
      );
      final client = NewsContextClient(client: edge);
      final ok = await client.fetch(['NVDA'], names: {'NVDA': 'Nvidia'});
      expect(ok['status'], 'ok');
      expect(ok['summary'], hasLength(2));
      expect((ok['sources'] as List).single, {
        'title': 'Nvidia unveils a chip',
        'url': 'https://www.reuters.com/a',
        'source': 'Reuters',
      });
      // Misma consulta en la conversación: no vuelve al servidor.
      await client.fetch(['NVDA']);
      expect(edge.calls.length, 1);

      limited = true;
      final limit = await client.fetch(['AMD']);
      expect(limit, {'status': 'limit', 'reason': 'daily_limit'});
    });

    test('empty: no sources (they showed under "no news")', () async {
      final client = NewsContextClient(
        client: FakeEdgeClient(
          (_, _) => const EdgeResponse(200, {
            'status': 'empty',
            'summary': <String>[],
            'citations': [
              {'title': 'T', 'url': 'https://www.reuters.com/a', 'source': 'R'},
            ],
          }),
        ),
      );
      expect(await client.fetch(['NVDA']), {'status': 'empty'});
    });
  });

  group('get_news v2', () {
    test('headlines + cited context; one web search per turn', () async {
      final edge = FakeEdgeClient(
        (path, _) =>
            path == 'news-context'
                ? const EdgeResponse(200, {
                  'status': 'ok',
                  'summary': ['Nvidia presentó un chip.'],
                  'citations': [
                    {'title': 'T', 'url': 'https://www.reuters.com/a', 'source': 'Reuters'},
                  ],
                })
                : const EdgeResponse(200, {'status': 'empty', 'by_ticker': {}}),
      );
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.gold,
        newsProvider: NewsProvider.v2,
        data: AssistantDataSources(
          quoteRepository: CountingQuoteRepository(),
          preferences: FakePreferences(),
          newsProvider: NewsProvider.v2,
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
      final tool = GetNewsTool(ctx);
      expect(
        (tool.parameters['properties'] as Map).containsKey('question'),
        isTrue,
      );
      expect(tool.description, contains('context'));

      final first = await tool.run({
        'tickers': ['NVDA'],
      });
      expect(first['status'], 'ok');
      expect((first['context'] as Map)['summary'], ['Nvidia presentó un chip.']);

      final second = await tool.run({
        'tickers': ['AMD'],
        'question': '¿Cuándo presenta resultados?',
      });
      expect((second['context'] as Map)['status'], 'limit');
      expect(edge.calls.where((c) => c.path == 'news-context').length, 1);
      expect(ctx.secData, isTrue);
    });

    test('the whole portfolio: up to 5 tickers in one web search', () async {
      final edge = FakeEdgeClient(
        (path, _) => const EdgeResponse(200, {'status': 'empty', 'by_ticker': {}}),
      );
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.gold,
        newsProvider: NewsProvider.v2,
        data: AssistantDataSources(
          quoteRepository: CountingQuoteRepository(),
          preferences: FakePreferences(),
          newsProvider: NewsProvider.v2,
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
      await GetNewsTool(ctx).run({
        'tickers': ['AAPL', 'MSFT', 'GOOGL', 'DUOL', 'VOO', 'SGOV'],
      });
      final sent = edge.calls.singleWhere((c) => c.path == 'news-context');
      expect(sent.args['tickers'], ['AAPL', 'MSFT', 'GOOGL', 'DUOL', 'VOO']);
    });

    test('legacy keeps the old description and parameters', () {
      final tool = GetNewsTool(
        AssistantToolContext(tier: SubscriptionTier.gold, data: fakeDataSources()),
      );
      expect(
        (tool.parameters['properties'] as Map).containsKey('question'),
        isFalse,
      );
    });
  });

  group('AnswerSources', () {
    test('web citations and SEC filings of the turn, without repeats', () {
      final sources = AnswerSources.of([
        ToolCallRecord(
          name: 'get_news',
          args: const {},
          result: const {
            'status': 'ok',
            'context': {
              'sources': [
                {'title': 'A', 'url': 'https://www.reuters.com/a', 'source': 'Reuters'},
                {'title': 'A again', 'url': 'https://www.reuters.com/a', 'source': 'Reuters'},
              ],
            },
          },
        ),
        ToolCallRecord(
          name: 'get_earnings',
          args: const {},
          result: {
            'status': 'ok',
            'earnings': {
              'AAPL': {
                'source': 'SEC EDGAR',
                'press_release': {
                  'form': '8-K',
                  'url': 'https://www.sec.gov/x/ex991.htm',
                },
              },
            },
          },
        ),
        ToolCallRecord(
          name: 'search_web',
          args: const {},
          result: const {
            'status': 'ok',
            'sources': [
              {'title': 'MacBook', 'url': 'https://www.apple.com/macbook/'},
            ],
          },
        ),
      ]);
      expect(sources.map((s) => s.url), [
        'https://www.reuters.com/a',
        'https://www.sec.gov/x/ex991.htm',
        'https://www.apple.com/macbook/',
      ]);
      expect(sources[1].title, 'Comunicado de resultados de AAPL (8-K)');
      expect(sources[2].source, 'apple.com');
    });
  });
}
