import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

import '../fakes/assistant_fakes.dart';

AssistantToolContext _ctx(
  SubscriptionTier tier, {
  CountingQuoteRepository? quotes,
  FakePreferences? prefs,
  FakeProfileClient? profiles,
  FakeCompanyFundamentalsRepository? fundamentals,
  InvestorProfile? investorProfile,
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(
    quotes: quotes,
    preferences: prefs,
    profiles: profiles,
    fundamentals: fundamentals,
  ),
  summary: heldSummary,
  loadInvestorProfile: () async => investorProfile,
  now: DateTime.utc(2026, 9, 29),
);

ToolCallRecord _record(String name, Map<String, Object?> result) =>
    ToolCallRecord(name: name, args: const {}, result: result);

void main() {
  group('get_quote gating is per ticker', () {
    test(
      'free: held tickers are fetched, others locked without a request',
      () async {
        final quotes = CountingQuoteRepository();
        final ctx = _ctx(SubscriptionTier.free, quotes: quotes);

        final result = await GetQuoteTool(ctx).run({
          'tickers': ['aapl', 'AMZN'],
        });

        final tickers = result['tickers'] as Map;
        expect(tickers['AAPL']['fetch_ok'], isTrue);
        expect(tickers['AAPL']['held'], isTrue);
        expect(tickers['AAPL']['weight_pct'], 50.0);
        expect(tickers['AMZN']['status'], 'locked');
        expect(quotes.priceCalls, ['AAPL']);
        expect(result['status'], 'ok');
        expect(ctx.lockedReasons, {PaywallReason.marketDataLocked});
      },
    );

    test('premium: any ticker of any market is fetched', () async {
      final quotes = CountingQuoteRepository();
      final result = await GetQuoteTool(
        _ctx(SubscriptionTier.premium, quotes: quotes),
      ).run({
        'tickers': [r'$MELI', 'brk.b'],
      });
      expect((result['tickers'] as Map).keys, ['MELI', 'BRK.B']);
      expect(quotes.priceCalls, ['MELI', 'BRK.B']);
    });

    test('bad arguments are a result, not an exception', () async {
      final result = await GetQuoteTool(
        _ctx(SubscriptionTier.gold),
      ).run({'tickers': 'AAPL'});
      expect(result['reason'], 'invalid_arguments');
    });
  });

  group('premium data (gold)', () {
    test('fundamentals / earnings / news are locked below gold, all with '
        'the same Gold reason and required_plan', () async {
      final ctx = _ctx(SubscriptionTier.premium);
      final args = {
        'tickers': ['AAPL'],
      };
      for (final tool in [
        GetFundamentalsTool(ctx),
        GetEarningsTool(ctx),
        GetNewsTool(ctx),
      ]) {
        final result = await tool.run(args);
        expect(result['status'], 'locked');
        expect(result['required_plan'], 'gold');
      }
      expect(ctx.lockedReasons, {PaywallReason.goldRequired});
    });

    test('gold fundamentals come back with their status', () async {
      final result = await GetFundamentalsTool(
        _ctx(
          SubscriptionTier.gold,
          fundamentals: FakeCompanyFundamentalsRepository(
            data: const CompanyFundamentals(ticker: 'AAPL', peTTM: 38.6),
          ),
        ),
      ).run({
        'tickers': ['AAPL'],
      });
      expect(result['status'], 'ok');
      expect((result['fundamentals'] as Map)['AAPL']['pe_ttm'], 38.6);
    });
  });

  group('get_invest_candidates: the model chooses any ticker', () {
    test('real sector, industry and beta-derived risk for tickers outside '
        'any predefined list', () async {
      final profiles = FakeProfileClient({
        'NEE': const YahooCompanyProfile(
          sector: 'Utilities',
          industry: 'Utilities—Renewable',
          beta: 0.6,
        ),
        'ENPH': const YahooCompanyProfile(sector: 'Technology', beta: 1.8),
      });
      final ctx = _ctx(
        SubscriptionTier.gold,
        profiles: profiles,
        investorProfile: InvestorProfile(
          risk: RiskTolerance.conservative,
          horizon: InvestmentHorizon.long,
          objective: InvestmentObjective.growth,
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      final result = await GetInvestCandidatesTool(ctx).run({
        'tickers': ['NEE', 'ENPH', 'XYZW'],
        'budget_usd': 500,
      });

      final byTicker = {
        for (final c in (result['candidates'] as List).cast<Map>())
          c['ticker']: c,
      };
      expect(byTicker.keys, ['NEE', 'ENPH', 'XYZW']);
      expect(byTicker['NEE']!['sector'], 'Servicios públicos');
      expect(byTicker['NEE']!['industry'], 'Utilities—Renewable');
      expect(byTicker['NEE']!['risk_level'], 'defensivo');
      expect(byTicker['NEE']!['matches_profile'], isTrue);
      expect(byTicker['ENPH']!['risk_level'], 'crecimiento');
      expect(byTicker['ENPH']!['matches_profile'], isFalse);
      // Sin perfil en Yahoo: sin clasificar, nunca adivinado.
      expect(byTicker['XYZW']!['sector'], 'Sin clasificar');
      expect(byTicker['XYZW']!['risk_level'], isNull);
      expect(result['budget_usd'], 500.0);
      expect(profiles.requested, containsAll(['AAPL', 'NVDA', 'NEE']));
    });

    test('asks the model to choose again when it sends no candidates or '
        'just copies the current holdings', () async {
      final tool = GetInvestCandidatesTool(_ctx(SubscriptionTier.gold));
      expect(
        (await tool.run({
          'theme': 'energía renovable',
          'tickers': [],
        }))['status'],
        'needs_retry',
      );
      expect(
        (await tool.run({
          'theme': 'energía renovable',
          'tickers': ['AAPL', 'NVDA'],
        }))['status'],
        'needs_retry',
      );
      expect(
        (await tool.run({
          'theme': 'sumar más AAPL',
          'tickers': ['AAPL'],
          'about_current_holdings': true,
        }))['status'],
        'ok',
      );
    });

    test('requires premium (free is locked with the plan paywall)', () async {
      final free = _ctx(SubscriptionTier.free);
      final result = await GetInvestCandidatesTool(free).run({
        'tickers': ['NEE'],
      });
      expect(result['status'], 'locked');
      expect(result['required_plan'], 'premium');
      expect(free.lockedReasons, {PaywallReason.modeLocked});
    });
  });

  group('goals', () {
    test(
      'stated goal is projected; the saved one fills missing fields',
      () async {
        final prefs =
            FakePreferences()
              ..goal = (
                label: 'Casa',
                targetAmount: 100000,
                targetDate: '2036-01-01',
              );
        final tool = GetGoalProjectionTool(
          _ctx(SubscriptionTier.gold, prefs: prefs),
        );

        final saved = await tool.run(const {});
        expect(saved['has_complete_goal'], isTrue);
        expect((saved['active_goal'] as Map)['label'], 'Casa');

        final stated = await tool.run({'target_amount': 250000});
        expect((stated['active_goal'] as Map)['target_amount'], 250000.0);
        expect((stated['active_goal'] as Map)['target_date'], '2036-01-01');
        expect((stated['projection'] as Map)['months_remaining'], isPositive);
      },
    );

    test('an incomplete goal lists what is missing', () async {
      final result = await GetGoalProjectionTool(
        _ctx(SubscriptionTier.gold),
      ).run({'target_amount': 1000000});
      expect(result['has_complete_goal'], isFalse);
      expect(result['missing'], ['target_date']);
    });

    test('save_goal writes the goal only with amount and date', () async {
      final prefs = FakePreferences();
      final tool = SaveGoalTool(_ctx(SubscriptionTier.gold, prefs: prefs));
      expect(
        (await tool.run({'target_amount': 5}))['reason'],
        'invalid_arguments',
      );
      await tool.run({
        'goal_label': 'Auto',
        'target_amount': 20000,
        'target_date': '2028-06',
      });
      expect(prefs.goal, (
        label: 'Auto',
        targetAmount: 20000.0,
        targetDate: '2028-06-01',
      ));
    });
  });

  test('portfolio brief keeps totals and positions, leaves the heavy parts '
      'to get_portfolio_details', () async {
    final ctx = _ctx(SubscriptionTier.free);
    final brief = PortfolioBrief.build(ctx);
    expect(brief['positions'], hasLength(2));
    expect(brief.containsKey('position_periods'), isFalse);
    expect(brief['closed_positions_count'], 0);

    final details = await GetPortfolioDetailsTool(ctx).run({
      'include': ['position_periods'],
      'tickers': ['AAPL'],
    });
    expect((details['position_periods'] as Map).keys, ['AAPL']);
  });

  group('AssistantTurnPolicy', () {
    test('paywall only when everything the model asked for is locked', () {
      final ctx = _ctx(SubscriptionTier.free)
        ..lockedReasons.add(PaywallReason.marketDataLocked);
      expect(
        AssistantTurnPolicy.paywallFor([
          _record('get_quote', {'status': 'locked'}),
        ], ctx),
        PaywallReason.marketDataLocked,
      );
      expect(
        AssistantTurnPolicy.paywallFor([
          _record('get_quote', {'status': 'locked'}),
          _record('search_symbol', {'status': 'resolved'}),
        ], ctx),
        isNull,
      );
    });

    test('a news turn costs the news weight only when news were searched', () {
      expect(
        AssistantTurnPolicy.quotaWeight(
          TurnOutcome([
            _record('get_news', {'status': 'empty'}),
          ]),
        ),
        AiUsageLimits.newsQueryWeight,
      );
      // Todo fuera del plan: la respuesta solo explica qué incluye Gold.
      expect(
        AssistantTurnPolicy.quotaWeight(
          TurnOutcome([
            _record('get_news', {'status': 'locked'}),
          ]),
        ),
        0,
      );
      expect(AssistantTurnPolicy.quotaWeight(const TurnOutcome([])), 1);
    });

    test('disclaimer for a simulation or a complete goal; nudge once', () {
      final invest = TurnOutcome([
        _record(GetInvestCandidatesTool.toolName, {
          'status': 'ok',
          'investor_profile': {'status': 'stale'},
        }),
      ]);
      final first = AssistantTurnPolicy.noticesFor(
        invest,
        profileNudgeAlreadyShown: false,
      );
      expect(first.showsDisclaimer, isTrue);
      expect(first.profileNudge, InvestorProfileNudge.stale);
      expect(
        AssistantTurnPolicy.noticesFor(
          invest,
          profileNudgeAlreadyShown: true,
        ).profileNudge,
        isNull,
      );
      expect(
        AssistantTurnPolicy.noticesFor(
          TurnOutcome([
            _record(GetGoalProjectionTool.toolName, {
              'status': 'ok',
              'has_complete_goal': false,
            }),
          ]),
          profileNudgeAlreadyShown: false,
        ).showsDisclaimer,
        isFalse,
      );
    });
  });

  test('the toolset order is stable (it is part of the cached prefix)', () {
    final names = [
      for (final DataTool t in AssistantToolset.build(
        _ctx(SubscriptionTier.free),
      ))
        t.name,
    ];
    expect(names, [
      'get_quote',
      'search_symbol',
      'get_fundamentals',
      'get_earnings',
      'get_news',
      'get_portfolio_details',
      'get_invest_candidates',
      'get_goal_projection',
      'save_goal',
    ]);
  });
}
