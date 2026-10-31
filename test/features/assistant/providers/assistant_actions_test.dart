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
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:portfolio_assistant/features/porty_memory/data/user_memory_repository.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portfolio_assistant/features/allocation/data/allocation_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';

import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';

import 'package:portfolio_assistant/features/assistant/models/manage_action.dart';
import 'package:portfolio_assistant/features/notifications/data/price_alerts_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';

import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/domain/watchlist_item.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';

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

/// La lista de seguimiento en memoria (seguir desde Porty).
class _WatchRepo implements WatchlistRepository {
  final items = <WatchlistItem>[];
  final notify = <String, bool>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<WatchlistItem>> list() async => List.of(items);

  @override
  Future<WatchlistItem> add(String symbol, {double? price}) async {
    final item = WatchlistItem(
      id: 'w${items.length}',
      symbol: symbol,
      addedPrice: price,
      createdAt: DateTime(2026, 10, 22),
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> setNotify(String id, {required bool notify}) async =>
      this.notify[id] = notify;

  @override
  Future<void> remove(String id) async => items.removeWhere((i) => i.id == id);
}

/// Las alertas de precio en memoria (gestionarlas desde Porty).
class _AlertRepo implements PriceAlertsRepository {
  final alerts = <PriceAlert>[
    PriceAlert(
      id: 'a1',
      symbol: 'VOO',
      condition: PriceAlertCondition.above,
      target: 750,
      status: PriceAlertStatus.active,
      createdAt: DateTime(2026, 10, 1),
    ),
  ];
  final activeCalls = <String, bool>{};
  final deleted = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<PriceAlert>> list() async => List.of(alerts);

  @override
  Future<void> setActive(String id, {required bool active}) async =>
      activeCalls[id] = active;

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    alerts.removeWhere((a) => a.id == id);
  }
}

class _WatchQuotes implements QuoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      t == 'ZZZZ' ? Left(HttpError(code: 'x')) : const Right(90);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => const Right([]);
}

/// Las metas en memoria (gestionarlas desde Porty).
class _GoalRepo implements GoalsRepository {
  _GoalRepo() {
    goals.add(
      UserGoal(
        id: 'goal-1',
        label: 'MacBook',
        type: GoalType.purchase,
        targetAmount: 1200,
        targetDate: DateTime(2027, 1, 1),
        snapshot: GoalPlanSnapshot(
          inputs: SavingsPlanInputs(
            targetAmount: 1200,
            months: 12,
            currentAmount: 0,
            risk: RiskTolerance.moderate,
            startDate: DateTime(2026, 1, 1),
            shortTerm: true,
          ),
        ),
        status: GoalStatus.active,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
  }

  final goals = <UserGoal>[];
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<UserGoal>> list() async => List.of(goals);

  @override
  Future<void> setStatus(String id, GoalStatus status) async =>
      calls.add('status:$id:${status.name}');

  @override
  Future<void> delete(String id) async {
    calls.add('delete:$id');
    goals.removeWhere((g) => g.id == id);
  }

  @override
  Future<void> setLinkedTickers(String id, Set<String> tickers) async =>
      calls.add('linked:$id:${(tickers.toList()..sort()).join(',')}');

  @override
  Future<void> setExternalSavings(String id, double amount) async =>
      calls.add('outside:$id:$amount');
}

class _AllocationRepo implements AllocationRepository {
  AllocationPlan? stored;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AllocationPlan?> load() async => stored;

  @override
  Future<void> save(AllocationPlan plan) async => stored = plan;
}

class _NotifRepo implements NotificationsRepository {
  NotificationPreferences saved = const NotificationPreferences();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<NotificationPreferences> loadPreferences() async => saved;

  @override
  Future<void> savePreferences(NotificationPreferences prefs) async =>
      saved = prefs;
}

class _MemoryRepo implements UserMemoryRepository {
  var cleared = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> deleteAll() async => cleared++;
}

class _BinanceRepo implements BinanceRepository {
  var connection = const BinanceConnection(status: BinanceStatus.connected);
  var syncs = 0;
  bool? disconnectedKeeping;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<BinanceConnection> load() async => connection;

  @override
  Future<({BinanceSyncResult? result, bool throttled})> sync() async {
    syncs++;
    return (result: null, throttled: false);
  }

  @override
  Future<void> disconnect({required bool keepAsManual}) async {
    disconnectedKeeping = keepAsManual;
    connection = const BinanceConnection();
  }
}

class _SnaptradeRepo implements SnaptradeRepository {
  var connection = const SnaptradeConnection();
  var syncs = 0;
  var portals = 0;
  bool? disconnectedKeeping;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SnaptradeConnection> load() async => connection;

  @override
  Future<Uri> portalUrl({required bool darkMode, String? reconnect}) async {
    portals++;
    return Uri.parse('https://app.snaptrade.com/portal');
  }

  @override
  Future<({SnaptradeSyncResult? result, bool throttled})> sync({
    bool force = false,
  }) async {
    syncs++;
    // Volvió del portal con un bróker conectado.
    connection = const SnaptradeConnection(
      status: SnaptradeStatus.connected,
      brokerages: [SnaptradeBrokerage(id: 'a1', name: 'Interactive Brokers')],
    );
    return (result: null, throttled: false);
  }

  @override
  Future<void> disconnect({required bool keepAsManual}) async {
    disconnectedKeeping = keepAsManual;
    connection = const SnaptradeConnection();
  }
}

class _Portal implements SnaptradePortalLauncher {
  var opened = 0;

  @override
  Future<bool> open(Uri url) async {
    opened++;
    return true;
  }
}

class _Harness {
  _Harness({SubscriptionTier tier = SubscriptionTier.premium, this.prefs})
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
        priceAlertsRepositoryProvider.overrideWithValue(alerts),
        goalsProvider.overrideWith((ref) => GoalsNotifier(goals)),
        allocationRepositoryProvider.overrideWithValue(allocation),
        notificationsRepositoryProvider.overrideWithValue(notif),
        binanceRepositoryProvider.overrideWithValue(binance),
        snaptradeRepositoryProvider.overrideWithValue(snaptrade),
        snaptradePortalLauncherProvider.overrideWithValue(portal),
        userMemoryRepositoryProvider.overrideWithValue(memory),
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs!),
        watchlistProvider.overrideWith(
          (ref) => WatchlistNotifier(watch, () => _WatchQuotes()),
        ),
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
  final watch = _WatchRepo();
  final alerts = _AlertRepo();
  final goals = _GoalRepo();
  final allocation = _AllocationRepo();
  final notif = _NotifRepo();
  final memory = _MemoryRepo();
  final binance = _BinanceRepo();
  final snaptrade = _SnaptradeRepo();
  final portal = _Portal();
  final SharedPreferences? prefs;
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
      // La venta registrada, para "Ver posición cerrada" en la card.
      expect(h.progress('p2').closedPosition?.id, 'c');
      expect(h.progress('p2').closedPosition?.quantity, 1.5);
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

  group('seguir un ticker', () {
    ActionDraft follow(String id, String ticker, {bool notify = true}) =>
        ActionDraft(
          proposalId: id,
          kind: ActionKind.watch,
          ticker: ticker,
          price: 90,
          watchNotify: notify,
        );

    test('confirmar lo suma a la lista, sin tocar la cartera', () async {
      h = _Harness();
      await h.notifier.executeAction(follow('w1', 'NFLX'));
      expect(h.watch.items.single.symbol, 'NFLX');
      expect(h.watch.notify, isEmpty);
      expect(h.progress('w1').status, ActionProposalStatus.done);
      expect(h.home.refreshes, 0);
    });

    test('con los avisos apagados, se suma sin avisos', () async {
      h = _Harness();
      await h.notifier.executeAction(follow('w2', 'NFLX', notify: false));
      expect(h.watch.notify.values.single, isFalse);
    });

    test('si ya la sigue o no tiene cotización, queda el error', () async {
      h = _Harness();
      await h.notifier.executeAction(follow('w3', 'NFLX'));
      await h.notifier.executeAction(follow('w4', 'NFLX'));
      expect(h.progress('w4').status, ActionProposalStatus.failed);
      expect(h.progress('w4').errorMessage, 'Ya seguís NFLX.');
      await h.notifier.executeAction(follow('w5', 'ZZZZ'));
      expect(
        h.progress('w5').errorMessage,
        'No encontré cotización para ZZZZ.',
      );
    });

    test('Free: no se suma y abre los planes', () async {
      h = _Harness(tier: SubscriptionTier.free);
      await h.notifier.executeAction(follow('w6', 'NFLX'));
      expect(h.watch.items, isEmpty);
      expect(h.state.paywallReason, PaywallReason.marketDataLocked);
    });
  });

  group('gestionar (lista y alertas)', () {
    ActionDraft manage(
      String id,
      ManageOp op,
      String ticker, {
      String? target,
    }) => ActionDraft(
      proposalId: id,
      kind: ActionKind.manage,
      ticker: ticker,
      manageOp: op,
      targetId: target,
      targetLabel: 'VOO sube a \$750',
    );

    test('dejar de seguir y apagar avisos', () async {
      h = _Harness();
      await h.notifier.executeAction(
        ActionDraft(proposalId: 'f', kind: ActionKind.watch, ticker: 'AMZN'),
      );
      await h.notifier.executeAction(
        manage('m1', ManageOp.watchNotifyOff, 'AMZN'),
      );
      expect(h.watch.notify.values.single, isFalse);
      await h.notifier.executeAction(manage('m2', ManageOp.unwatch, 'AMZN'));
      expect(h.watch.items, isEmpty);
      expect(h.progress('m2').status, ActionProposalStatus.done);
      // Lo que ya no sigue: error claro, nada escrito.
      await h.notifier.executeAction(manage('m3', ManageOp.unwatch, 'AMZN'));
      expect(h.progress('m3').errorMessage, 'Ya no seguís AMZN.');
    });

    test('pausar y borrar una alerta (también en Free)', () async {
      h = _Harness(tier: SubscriptionTier.free);
      await h.notifier.executeAction(
        manage('m4', ManageOp.alertPause, 'VOO', target: 'a1'),
      );
      expect(h.alerts.activeCalls, {'a1': false});
      await h.notifier.executeAction(
        manage('m5', ManageOp.alertDelete, 'VOO', target: 'a1'),
      );
      expect(h.alerts.deleted, ['a1']);
      await h.notifier.executeAction(
        manage('m6', ManageOp.alertDelete, 'VOO', target: 'a1'),
      );
      expect(h.progress('m6').errorMessage, 'Esa alerta ya no existe.');
    });
  });

  group('gestionar metas', () {
    ActionDraft goal(String id, ManageOp op, {Map<String, Object?>? params}) =>
        ActionDraft(
          proposalId: id,
          kind: ActionKind.manage,
          ticker: '',
          manageOp: op,
          targetId: 'goal-1',
          targetLabel: 'MacBook',
          params: params ?? const {},
        );

    test('cumplida, inversiones, ahorro afuera y borrar', () async {
      h = _Harness();
      await h.notifier.executeAction(goal('g1', ManageOp.goalAchieved));
      await h.notifier.executeAction(
        goal(
          'g2',
          ManageOp.goalHoldings,
          params: {
            'tickers': ['VOO', 'BND'],
          },
        ),
      );
      await h.notifier.executeAction(
        goal('g3', ManageOp.goalOutsideSavings, params: {'amount': 1500}),
      );
      await h.notifier.executeAction(goal('g4', ManageOp.goalDelete));
      expect(h.goals.calls, [
        'status:goal-1:achieved',
        'linked:goal-1:BND,VOO',
        'outside:goal-1:1500.0',
        'delete:goal-1',
      ]);
      expect(h.progress('g4').status, ActionProposalStatus.done);
      await h.notifier.executeAction(goal('g5', ManageOp.goalDelete));
      expect(h.progress('g5').errorMessage, 'Esa meta ya no existe.');
    });
  });

  group('plan de cartera', () {
    ActionDraft plan(String id, Map<String, Object?> params) => ActionDraft(
      proposalId: id,
      kind: ActionKind.manage,
      ticker: '',
      manageOp: ManageOp.allocationSave,
      params: params,
    );

    test('guarda el plan y después solo cambia los avisos', () async {
      h = _Harness();
      await h.notifier.executeAction(
        plan('p1', {
          'targets': {'VOO': 60, 'BND': 40},
          'frequency': 'monthly',
        }),
      );
      expect(h.allocation.stored!.targets, {'VOO': 60.0, 'BND': 40.0});
      expect(h.allocation.stored!.frequency, AllocationAlertFrequency.monthly);
      await h.notifier.executeAction(plan('p2', {'notify': false}));
      expect(h.allocation.stored!.notify, isFalse);
      expect(h.allocation.stored!.targets, {'VOO': 60.0, 'BND': 40.0});
    });

    test('Free: no se guarda y abre los planes', () async {
      h = _Harness(tier: SubscriptionTier.free);
      await h.notifier.executeAction(
        plan('p3', {
          'targets': {'VOO': 100},
        }),
      );
      expect(h.allocation.stored, isNull);
      expect(h.state.paywallReason, PaywallReason.modeLocked);
    });
  });

  group('ajustes y memoria', () {
    ActionDraft settings(String id, Map<String, Object?> changes) =>
        ActionDraft(
          proposalId: id,
          kind: ActionKind.manage,
          ticker: '',
          manageOp: ManageOp.settingsChange,
          params: {'changes': changes},
        );

    test('notificaciones, silencio, moneda, tema y vibración', () async {
      SharedPreferences.setMockInitialValues({});
      h = _Harness(prefs: await SharedPreferences.getInstance());
      await h.notifier.executeAction(
        settings('s1', {
          AppSettingKeys.earnings: false,
          AppSettingKeys.sensitivity: 'low',
          AppSettingKeys.quietHours: '23:00-07:30',
          AppSettingKeys.currency: 'UYU',
          AppSettingKeys.theme: 'dark',
          AppSettingKeys.haptics: false,
        }),
      );
      expect(h.progress('s1').status, ActionProposalStatus.done);
      expect(h.notif.saved.earnings, isFalse);
      expect(h.notif.saved.bigMoveSensitivity, BigMoveSensitivity.low);
      expect(h.notif.saved.quietStartMinutes, 23 * 60);
      expect(h.notif.saved.quietEndMinutes, 7 * 60 + 30);
      expect(h.container.read(displayCurrencyProvider), DisplayCurrency.uyu);
      expect(h.container.read(themeModeProvider), ThemeMode.dark);
      expect(h.container.read(hapticsEnabledProvider), isFalse);
    });

    test('borrar todo lo que Porty recuerda', () async {
      h = _Harness();
      await h.notifier.executeAction(
        const ActionDraft(
          proposalId: 'mc',
          kind: ActionKind.manage,
          ticker: '',
          manageOp: ManageOp.memoryClear,
        ),
      );
      expect(h.memory.cleared, 1);
      expect(h.progress('mc').status, ActionProposalStatus.done);
    });
  });

  group('cuentas conectadas', () {
    ActionDraft broker(String id, ManageOp op, Map<String, Object?> params) =>
        ActionDraft(
          proposalId: id,
          kind: ActionKind.manage,
          ticker: '',
          manageOp: op,
          params: params,
        );

    test('actualizar y desconectar Binance conservando lo importado', () async {
      h = _Harness();
      await h.notifier.executeAction(
        broker('b1', ManageOp.brokerSync, {'broker': 'binance'}),
      );
      expect(h.binance.syncs, 1);
      expect(h.progress('b1').status, ActionProposalStatus.done);
      await h.notifier.executeAction(
        broker('b2', ManageOp.brokerDisconnect, {
          'broker': 'binance',
          'keep': true,
        }),
      );
      expect(h.binance.disconnectedKeeping, isTrue);
      await h.notifier.executeAction(
        broker('b3', ManageOp.brokerSync, {'broker': 'binance'}),
      );
      expect(h.progress('b3').errorMessage, 'Binance no está conectada.');
    });

    test('otros brókers: conectar abre el portal y desconectar', () async {
      h = _Harness();
      await h.notifier.executeAction(
        broker('s1', ManageOp.brokerConnect, {'broker': 'snaptrade'}),
      );
      expect(h.portal.opened, 1);
      expect(h.snaptrade.syncs, 1);
      expect(h.progress('s1').status, ActionProposalStatus.done);
      await h.notifier.executeAction(
        broker('s2', ManageOp.brokerDisconnect, {
          'broker': 'snaptrade',
          'keep': false,
        }),
      );
      expect(h.snaptrade.disconnectedKeeping, isFalse);
      await h.notifier.executeAction(
        broker('s3', ManageOp.brokerSync, {'broker': 'snaptrade'}),
      );
      expect(
        h.progress('s3').errorMessage,
        'No tenés otros brókers conectados.',
      );
    });

    test(
      'Premium con un bróker: sumar otro abre Gold sin abrir el portal',
      () async {
        h = _Harness();
        h.snaptrade.connection = const SnaptradeConnection(
          status: SnaptradeStatus.connected,
          brokerages: [
            SnaptradeBrokerage(id: 'a1', name: 'Interactive Brokers'),
          ],
        );
        await h.notifier.executeAction(
          broker('s4', ManageOp.brokerConnect, {'broker': 'snaptrade'}),
        );
        expect(h.portal.opened, 0);
        expect(h.state.paywallReason, PaywallReason.goldRequired);
      },
    );

    test('Free: no toca nada y abre los planes', () async {
      h = _Harness(tier: SubscriptionTier.free);
      await h.notifier.executeAction(
        broker('b4', ManageOp.brokerSync, {'broker': 'binance'}),
      );
      expect(h.binance.syncs, 0);
      expect(h.state.paywallReason, PaywallReason.brokerSync);
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
