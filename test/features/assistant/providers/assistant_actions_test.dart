import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes/assistant_fakes.dart';

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _UnusedRevenueCat extends _Unused implements RevenueCatService {}

class _UnusedSummary extends _Unused implements GetPortfolioSummaryUseCase {}

class _UnusedHistory extends _Unused implements GetPortfolioHistoryUseCase {}

class _UnusedBenchmark extends _Unused
    implements GetBenchmarkComparisonUseCase {}

class _UnusedDeleteByTicker extends _Unused
    implements DeletePositionsByTickerUseCase {}

class _UnusedClosed extends _Unused implements GetClosedPositionsUseCase {}

class _UnusedPositions extends _Unused implements PositionRepository {}

class _UnusedClosedRepository extends _Unused
    implements ClosedPositionRepository {}

class _Subscriptions implements SubscriptionRepository {
  _Subscriptions(this.tier);

  SubscriptionTier tier;

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: tier,
    queriesUsed: 0,
    queriesLimit: 500,
    month: '2026-10',
  );

  @override
  Future<bool> consumeQuota(int weight) async => true;
}

class _Session implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: const User(
      id: 'user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Home cargada que cuenta los refresh (después de guardar, la cartera se
/// vuelve a traer).
class _Home extends HomeProvider {
  _Home(Ref ref)
    : super(
        ref: ref,
        getPortfolioSummaryUseCase: _UnusedSummary(),
        getPortfolioHistoryUseCase: _UnusedHistory(),
        getBenchmarkComparisonUseCase: _UnusedBenchmark(),
        deletePositionsByTickerUseCase: _UnusedDeleteByTicker(),
        getClosedPositionsUseCase: _UnusedClosed(),
      ) {
    state = HomeState(summary: heldSummary);
  }

  int refreshes = 0;

  @override
  Future<void> refresh({bool silent = false}) async => refreshes++;
}

class _Add extends AddPositionUseCase {
  _Add() : super(repository: _UnusedPositions());

  final calls = <AddPositionParams>[];
  Completer<void>? gate;
  HttpError? error;

  @override
  Future<Either<HttpError, Position>> call({
    required AddPositionParams params,
  }) async {
    calls.add(params);
    await gate?.future;
    final error = this.error;
    if (error != null) return Left(error);
    return Right(
      Position(
        id: 'new',
        ticker: params.ticker,
        quantity: params.quantity,
        purchasePrice: params.purchasePrice,
        purchaseDate: params.purchaseDate,
      ),
    );
  }
}

class _Close extends ClosePositionUseCase {
  _Close() : super(repository: _UnusedClosedRepository());

  final calls = <ClosePositionParams>[];

  @override
  Future<Either<HttpError, ClosedPosition>> call({
    required ClosePositionParams params,
  }) async {
    calls.add(params);
    return Right(
      ClosedPosition(
        id: 'c',
        ticker: params.positionId,
        quantity: params.quantity,
        avgPurchasePrice: 100,
        closePrice: params.closePrice,
        closeDate: params.closeDate,
        closedAt: DateTime(2026, 10, 8),
      ),
    );
  }
}

class _Delete extends DeletePositionUseCase {
  _Delete() : super(repository: _UnusedPositions());

  final calls = <String>[];

  @override
  Future<Either<HttpError, void>> call({required String params}) async {
    calls.add(params);
    return const Right(null);
  }
}

class _Harness {
  _Harness({SubscriptionTier tier = SubscriptionTier.premium})
    : subscriptions = _Subscriptions(tier) {
    final tracker = AiUsageTracker(repository: subscriptions);
    container = ProviderContainer(
      overrides: [
        homeProvider.overrideWith((ref) => home = _Home(ref)),
        aiUsageTrackerProvider.overrideWithValue(tracker),
        revenueCatServiceProvider.overrideWithValue(_UnusedRevenueCat()),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: tracker,
            authService: _Session(),
            revenueCat: _UnusedRevenueCat(),
          ),
        ),
        addPositionUseCaseProvider.overrideWithValue(add),
        closePositionUseCaseProvider.overrideWithValue(close),
        deletePositionUseCaseProvider.overrideWithValue(delete),
        assistantDepsProvider.overrideWithValue(
          AssistantDeps(
            createService: () => throw StateError('no model in these tests'),
            createData: () => fakeDataSources(),
          ),
        ),
      ],
    );
    container.listen(assistantProvider(args), (_, _) {});
    container.read(homeProvider);
  }

  static const args = AssistantArgs();
  final _Subscriptions subscriptions;
  final add = _Add();
  final close = _Close();
  final delete = _Delete();
  late _Home home;
  late final ProviderContainer container;

  AssistantProvider get notifier =>
      container.read(assistantProvider(args).notifier);
  AssistantState get state => container.read(assistantProvider(args));
  ActionProposalProgress progress(String id) => state.actionProgress(id);

  void dispose() => container.dispose();
}

final _buy = ActionDraft(
  proposalId: 'p1',
  kind: ActionKind.buy,
  ticker: 'AAPL',
  shares: 10,
  price: 210,
  date: DateTime(2026, 9, 28),
);

void main() {
  late _Harness h;
  tearDown(() => h.dispose());

  group('executeAction', () {
    test('a buy is saved with the edited data and refreshes Home', () async {
      h = _Harness();
      await h.notifier.executeAction(_buy);

      final params = h.add.calls.single;
      expect(params.ticker, 'AAPL');
      expect(params.quantity, 10);
      expect(params.purchasePrice, 210);
      expect(params.purchaseDate, DateTime(2026, 9, 28));
      expect(h.progress('p1').status, ActionProposalStatus.done);
      expect(h.progress('p1').draft, same(_buy));
      expect(h.home.refreshes, 1);
    });

    test('a sell closes by ticker (FIFO in the repository)', () async {
      h = _Harness();
      await h.notifier.executeAction(
        ActionDraft(
          proposalId: 'p2',
          kind: ActionKind.sell,
          ticker: 'NVDA',
          shares: 1.5,
          price: 180,
          date: DateTime(2026, 10, 1),
        ),
      );
      final params = h.close.calls.single;
      expect(params.positionId, 'NVDA');
      expect(params.quantity, 1.5);
      expect(params.closePrice, 180);
      expect(h.progress('p2').status, ActionProposalStatus.done);
    });

    test('a delete removes exactly the chosen purchases', () async {
      h = _Harness();
      await h.notifier.executeAction(
        const ActionDraft(
          proposalId: 'p3',
          kind: ActionKind.delete,
          ticker: 'TSLA',
          shares: 5,
          lotIds: ['lot-a', 'lot-b'],
        ),
      );
      expect(h.delete.calls, ['lot-a', 'lot-b']);
      expect(h.progress('p3').status, ActionProposalStatus.done);
    });

    test('a double tap saves once: saving is set before any await', () async {
      h = _Harness();
      h.add.gate = Completer<void>();
      final first = h.notifier.executeAction(_buy);
      expect(h.progress('p1').status, ActionProposalStatus.saving);
      final second = h.notifier.executeAction(_buy);
      h.add.gate!.complete();
      await Future.wait([first, second]);

      expect(h.add.calls, hasLength(1));
      expect(h.progress('p1').status, ActionProposalStatus.done);
    });

    test('once saved, confirming again does nothing', () async {
      h = _Harness();
      await h.notifier.executeAction(_buy);
      await h.notifier.executeAction(_buy);
      expect(h.add.calls, hasLength(1));
    });

    test('a failure keeps the message and can be retried', () async {
      h = _Harness();
      h.add.error = HttpError(code: 'x', message: 'Sin conexión');
      await h.notifier.executeAction(_buy);
      expect(h.progress('p1').status, ActionProposalStatus.failed);
      expect(h.progress('p1').errorMessage, 'Sin conexión');
      expect(h.home.refreshes, 0);

      h.add.error = null;
      await h.notifier.executeAction(_buy);
      expect(h.progress('p1').status, ActionProposalStatus.done);
      expect(h.add.calls, hasLength(2));
    });

    test('an error without a message gets a generic one', () async {
      h = _Harness();
      h.add.error = HttpError(code: 'x');
      await h.notifier.executeAction(_buy);
      expect(
        h.progress('p1').errorMessage,
        'No se pudo guardar. Probá de nuevo.',
      );
    });

    test('an invalid draft is not saved', () async {
      h = _Harness();
      await h.notifier.executeAction(
        ActionDraft(
          proposalId: 'p4',
          kind: ActionKind.buy,
          ticker: 'AAPL',
          shares: 0,
          price: 210,
          date: DateTime(2026, 9, 28),
        ),
      );
      expect(h.add.calls, isEmpty);
      expect(h.progress('p4').status, ActionProposalStatus.failed);
    });

    test('if the plan no longer includes it: nothing saved, paywall', () async {
      h = _Harness(tier: SubscriptionTier.free);
      await h.notifier.executeAction(_buy);
      expect(h.add.calls, isEmpty);
      expect(h.progress('p1').status, ActionProposalStatus.pending);
      expect(h.state.paywallReason, PaywallReason.modeLocked);
    });
  });

  group('cancelAction', () {
    test('marks it cancelled with what the card had', () {
      h = _Harness();
      h.notifier.cancelAction(_buy);
      expect(h.progress('p1').status, ActionProposalStatus.cancelled);
      expect(h.progress('p1').draft, same(_buy));
    });

    test('a saved operation cannot be cancelled', () async {
      h = _Harness();
      await h.notifier.executeAction(_buy);
      h.notifier.cancelAction(_buy);
      expect(h.progress('p1').status, ActionProposalStatus.done);
    });
  });

  group('card edits', () {
    test('are kept per proposal without emitting state', () {
      h = _Harness();
      final before = h.state;
      const form = ActionForm(
        amountText: '900',
        unit: AmountUnit.usd,
        priceText: '180',
        priceEdited: true,
      );
      h.notifier.saveActionForm('p1', form);

      expect(identical(h.state, before), isTrue);
      expect(h.notifier.actionFormOf('p1'), same(form));
      expect(h.notifier.actionFormOf('p2'), isNull);
    });
  });

  group('actionPriceOn', () {
    test('the close of that day, from the assistant data sources', () async {
      h = _Harness();
      // CountingQuoteRepository: 400 cierres hasta el 25/9/2026, de a 0,1.
      expect(
        await h.notifier.actionPriceOn('AAPL', DateTime(2026, 9, 25)),
        closeTo(139.9, 1e-9),
      );
    });

    test('before all history → null (the card asks for it)', () async {
      h = _Harness();
      expect(await h.notifier.actionPriceOn('AAPL', DateTime(2001)), isNull);
    });
  });
}
