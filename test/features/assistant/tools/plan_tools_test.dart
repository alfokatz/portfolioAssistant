import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/plan_tools.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';

import '../fakes/assistant_fakes.dart';

class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      const Right(100);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => const [];
}

AssistantToolContext _ctx({
  SubscriptionTier tier = SubscriptionTier.premium,
  AllocationPlan? plan,
  List<Map<String, Object?>> watchlist = const [],
  Future<void> Function(String)? add,
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(quotes: _Quotes()),
  // AAPL y NVDA, USD 300 cada una.
  summary: heldSummary,
  loadAllocationPlan: () async => plan,
  loadWatchlist: () async => watchlist,
  addToWatchlist: add,
  now: DateTime(2026, 10, 16),
);

void main() {
  test('las tres tools van en el toolset', () {
    final names = {for (final t in AssistantToolset.build(_ctx())) t.name};
    expect(names.containsAll(PlanTools.names), isTrue);
  });

  group('get_allocation_plan', () {
    const plan = AllocationPlan(
      targets: {'AAPL': 70, 'NVDA': 20, 'VOO': 10},
      driftThreshold: 5,
    );

    test('filas con desvío y lo que está fuera del plan', () async {
      final r = await GetAllocationPlanTool(_ctx(plan: plan)).run({});
      expect(r['status'], 'ok');
      final rows = r['rows'] as List;
      expect(rows.first, {
        'ticker': 'AAPL',
        'current_pct': 50.0,
        'target_pct': 70.0,
        'drift_pts': -20.0,
      });
      expect(r['off_plan'], ['AAPL', 'NVDA', 'VOO']);
      expect(r['max_drift_pts'], 30.0);
      expect(r.containsKey('contribution'), isFalse);
    });

    test('reparto de un aporte, solo compras', () async {
      final r = await GetAllocationPlanTool(
        _ctx(plan: plan),
      ).run({'contribution_usd': 400});
      final split = (r['contribution'] as Map)['split'] as List;
      // Total después: 1000. AAPL objetivo 700 (faltan 400), NVDA 200 (le
      // sobra), VOO 100 (faltan 100): 400 × 4/5 y 400 × 1/5.
      expect(split, [
        {'ticker': 'AAPL', 'amount_usd': 320.0},
        {'ticker': 'VOO', 'amount_usd': 80.0},
      ]);
    });

    test('sin plan, Free y sin la app', () async {
      expect((await GetAllocationPlanTool(_ctx()).run({}))['status'], 'empty');
      final ctx = _ctx(tier: SubscriptionTier.free, plan: plan);
      final locked = await GetAllocationPlanTool(ctx).run({});
      expect(locked['status'], 'locked');
      expect(locked['required_plan'], 'premium');
      expect(ctx.lockedReasons, contains(PaywallReason.modeLocked));
      final outside = AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(quotes: _Quotes()),
      );
      expect(
        (await GetAllocationPlanTool(outside).run({}))['status'],
        'failed',
      );
    });
  });

  group('get_watchlist', () {
    test('devuelve los items; vacía; Free bloqueada', () async {
      final ok = await GetWatchlistTool(
        _ctx(
          watchlist: [
            {'ticker': 'AMZN', 'price': 180.0, 'day_change_pct': -2.1},
          ],
        ),
      ).run({});
      expect(ok['status'], 'ok');
      expect((ok['items'] as List).single, containsPair('ticker', 'AMZN'));
      expect((await GetWatchlistTool(_ctx()).run({}))['status'], 'empty');
      final ctx = _ctx(tier: SubscriptionTier.free);
      expect((await GetWatchlistTool(ctx).run({}))['status'], 'locked');
      expect(ctx.lockedReasons, contains(PaywallReason.marketDataLocked));
    });
  });

  group('add_to_watchlist', () {
    test('agrega en mayúsculas', () async {
      final added = <String>[];
      final r = await AddToWatchlistTool(
        _ctx(add: (t) async => added.add(t)),
      ).run({'ticker': 'amzn'});
      expect(r['status'], 'ok');
      expect(added, ['AMZN']);
    });

    test('lo que ya tiene en cartera no va a la lista', () async {
      final added = <String>[];
      final r = await AddToWatchlistTool(
        _ctx(add: (t) async => added.add(t)),
      ).run({'ticker': 'NVDA'});
      expect(r['status'], 'held');
      expect(added, isEmpty);
    });

    test('errores del repositorio a estados', () async {
      Future<String?> statusFor(Object error) async =>
          (await AddToWatchlistTool(
                _ctx(add: (_) async => throw error),
              ).run({'ticker': 'AMZN'}))['status']
              as String?;
      expect(await statusFor(const WatchlistUnknownSymbol()), 'unknown_symbol');
      expect(await statusFor(const WatchlistDuplicate()), 'already_there');
      expect(await statusFor(const WatchlistLimitReached()), 'limit_reached');
      expect(await statusFor(const WatchlistUnavailable()), 'failed');
    });

    test('Free bloqueada y sin ticker pide el dato', () async {
      expect(
        (await AddToWatchlistTool(
          _ctx(tier: SubscriptionTier.free),
        ).run({'ticker': 'AMZN'}))['status'],
        'locked',
      );
      expect(
        (await AddToWatchlistTool(_ctx()).run({}))['status'],
        'needs_input',
      );
    });
  });

  group('answer_guide (instrucciones justo a tiempo)', () {
    String? guideOf(Map<String, Object?> r) => r[AnswerGuide.key] as String?;

    test('cada resultado útil trae su guía; locked y failed no', () async {
      const plan = AllocationPlan(targets: {'AAPL': 50, 'NVDA': 50});
      expect(
        guideOf(await GetAllocationPlanTool(_ctx(plan: plan)).run({})),
        PlanGuides.planOk,
      );
      expect(
        guideOf(await GetAllocationPlanTool(_ctx()).run({})),
        PlanGuides.planEmpty,
      );
      expect(
        guideOf(await GetWatchlistTool(_ctx()).run({})),
        PlanGuides.watchlistEmpty,
      );
      expect(
        guideOf(
          await AddToWatchlistTool(
            _ctx(add: (_) async {}),
          ).run({'ticker': 'AMZN'}),
        ),
        PlanGuides.addOk,
      );
      expect(
        guideOf(
          await AddToWatchlistTool(
            _ctx(add: (_) async {}),
          ).run({'ticker': 'AAPL'}),
        ),
        PlanGuides.addHeld,
      );
      // Lo general (locked, failed) lo resuelve el prompt.
      expect(
        guideOf(
          await GetWatchlistTool(_ctx(tier: SubscriptionTier.free)).run({}),
        ),
        isNull,
      );
    });

    test('la guía del plan no deja recomendar', () {
      expect(PlanGuides.planOk, contains('para acercarte a tu plan'));
      expect(PlanGuides.planOk, contains('never "te conviene"'));
    });
  });
}
