// Brókers conectados por SnapTrade: el dominio (fila de la conexión, origen
// de las posiciones), el notifier con un repositorio y un portal falsos, y
// la pantalla en sus estados (claro y oscuro, a 320 de ancho).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_source_badge.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/features/snaptrade/view/snaptrade_screen.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_source_badge.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Repo implements SnaptradeRepository {
  _Repo(this.connection);

  SnaptradeConnection connection;

  /// Lo que queda conectado después de volver del portal.
  SnaptradeConnection? afterPortal;
  SnaptradeException? failPortal;
  SnaptradeException? failSync;
  SnaptradeException? failRefresh;
  final syncs = <bool>[];
  String? reconnected;
  String? removed;
  bool? disconnectedKeeping;

  @override
  Future<SnaptradeConnection> load() async => connection;

  @override
  Future<Uri> portalUrl({required bool darkMode, String? reconnect}) async {
    if (failPortal != null) throw failPortal!;
    reconnected = reconnect;
    return Uri.parse('https://app.snaptrade.com/portal');
  }

  @override
  Future<({SnaptradeSyncResult? result, bool throttled})> sync({
    bool force = false,
  }) async {
    syncs.add(force);
    if (failSync != null) throw failSync!;
    if (afterPortal != null) connection = afterPortal!;
    return (result: const SnaptradeSyncResult(imported: 1), throttled: false);
  }

  @override
  Future<int> refresh() async {
    if (failRefresh != null) throw failRefresh!;
    return 1;
  }

  @override
  Future<void> remove(String brokerageId) async => removed = brokerageId;

  @override
  Future<void> disconnect({required bool keepAsManual}) async {
    disconnectedKeeping = keepAsManual;
    connection = const SnaptradeConnection();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Portal implements SnaptradePortalLauncher {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _ibkr = SnaptradeBrokerage(id: 'auth-ibkr', name: 'Interactive Brokers');

SnaptradeConnection _connected({
  List<SnaptradeBrokerage> brokerages = const [_ibkr],
}) => SnaptradeConnection(
  status: SnaptradeStatus.connected,
  brokerages: brokerages,
  lastSyncAt: DateTime.now(),
  lastResult: const SnaptradeSyncResult(
    imported: 3,
    notImported: [
      SnaptradeSkipped('USD', 'Interactive Brokers', 'cash'),
      SnaptradeSkipped('AAPL 261120C', 'Interactive Brokers', 'unsupported'),
    ],
    estimatedCost: ['VOO'],
  ),
);

void main() {
  group('SnaptradeConnection', () {
    test('row with brokerages, skipped and estimated cost', () {
      final c = SnaptradeConnection.fromRow({
        'status': 'connected',
        'brokerages': [
          {
            'id': 'auth-ibkr',
            'name': 'Interactive Brokers',
            'disabled': true,
            'imported': true,
          },
          {
            'id': 'auth-schwab',
            'name': 'Schwab',
            'imported': false,
            'reason': 'plan_limit',
          },
          {'name': 'sin id'},
        ],
        'last_sync_at': '2026-10-31T12:00:00Z',
        'last_result': {
          'imported': 2,
          'notImported': [
            {
              'ticker': 'USD',
              'broker': 'Interactive Brokers',
              'reason': 'cash',
            },
            {'ticker': 7},
          ],
          'estimatedCost': ['VOO'],
        },
      });
      expect(c.status, SnaptradeStatus.connected);
      expect(c.isConnected, isTrue);
      expect(c.brokerages.map((b) => b.id), ['auth-ibkr', 'auth-schwab']);
      expect(c.imported.single.disabled, isTrue);
      expect(c.overPlanLimit.single.name, 'Schwab');
      expect(c.lastResult!.notImported.single.reason, 'cash');
      expect(c.lastResult!.estimatedCost, ['VOO']);
    });

    test('pending (opened the portal, connected nothing) is not connected', () {
      expect(
        SnaptradeConnection.fromRow({'status': 'pending'}).isConnected,
        isFalse,
      );
      expect(SnaptradeConnection.fromRow(null).isConnected, isFalse);
    });

    test('position source: snaptrade and mixes', () {
      expect(PositionSource.fromWire('snaptrade'), PositionSource.snaptrade);
      expect(PositionSource.snaptrade.hasImported, isTrue);
      expect(
        PositionSource.combine({
          PositionSource.manual,
          PositionSource.snaptrade,
        }),
        PositionSource.mixedSnaptrade,
      );
      // Lo de antes no cambia.
      expect(
        PositionSource.combine({PositionSource.manual, PositionSource.binance}),
        PositionSource.mixedBinance,
      );
      expect(
        PositionSource.combine({
          PositionSource.etoro,
          PositionSource.snaptrade,
        }),
        PositionSource.mixed,
      );
      expect(PositionSource.mixedSnaptrade.isSnaptrade, isTrue);
      expect(PositionSource.mixedSnaptrade.isBinance, isFalse);
    });

    testWidgets('the badge follows the broker', (tester) async {
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Row(
            children: [
              BrokerSourceBadge(source: PositionSource.mixedSnaptrade),
              BrokerSourceBadge(source: PositionSource.binance),
            ],
          ),
        ),
      );
      expect(find.byType(SnaptradeSourceBadge), findsOneWidget);
      expect(find.byType(BinanceSourceBadge), findsOneWidget);
    });
  });

  group('SnaptradeNotifier', () {
    test(
      'connect opens the portal, then a forced sync and a Home reload',
      () async {
        final repo = _Repo(const SnaptradeConnection())
          ..afterPortal = _connected();
        final portal = _Portal();
        var refreshed = 0;
        final n = SnaptradeNotifier(
          repo,
          portal,
          onImported: () async => refreshed++,
        );
        await n.load();
        expect(await n.connect(darkMode: true), isTrue);
        expect(portal.opened.single.host, 'app.snaptrade.com');
        expect(repo.syncs, [true]);
        expect(refreshed, 1);
        expect(n.state.connection.imported.single.name, 'Interactive Brokers');
        expect(n.state.busy, isFalse);
      },
    );

    test('closing the portal without connecting is not a success', () async {
      final repo = _Repo(
        const SnaptradeConnection(status: SnaptradeStatus.pending),
      );
      final n = SnaptradeNotifier(repo, _Portal());
      expect(await n.connect(darkMode: false), isFalse);
      expect(n.state.errorType, isNull);
    });

    test('plan limit stays as the error to show', () async {
      final repo = _Repo(_connected())
        ..failPortal = const SnaptradeException('snaptrade_connection_limit');
      final portal = _Portal();
      final n = SnaptradeNotifier(repo, portal);
      expect(await n.connect(darkMode: false), isFalse);
      expect(n.state.errorType, 'snaptrade_connection_limit');
      expect(portal.opened, isEmpty);
    });

    test('reconnect passes the broken brokerage id', () async {
      final repo = _Repo(_connected())..afterPortal = _connected();
      final n = SnaptradeNotifier(repo, _Portal());
      await n.connect(darkMode: false, reconnect: 'auth-ibkr');
      expect(repo.reconnected, 'auth-ibkr');
    });

    test('on open: syncs only when connected and stale', () async {
      final now = DateTime(2026, 10, 31, 12);
      final repo = _Repo(
        SnaptradeConnection(
          status: SnaptradeStatus.connected,
          lastSyncAt: now.subtract(const Duration(minutes: 20)),
        ),
      );
      final n = SnaptradeNotifier(repo, _Portal());
      await n.syncIfStale(now: now);
      expect(repo.syncs, isEmpty);
      await n.syncIfStale(now: now.add(const Duration(hours: 2)));
      expect(repo.syncs, [false]);

      final pending = _Repo(
        const SnaptradeConnection(status: SnaptradeStatus.pending),
      );
      await SnaptradeNotifier(pending, _Portal()).syncIfStale(now: now);
      expect(pending.syncs, isEmpty);
    });

    test('refresh, remove and disconnect', () async {
      final repo = _Repo(_connected());
      final n = SnaptradeNotifier(repo, _Portal());
      await n.load();
      expect(await n.refresh(), isTrue);
      repo.failRefresh = const SnaptradeException('snaptrade_refresh_limit');
      expect(await n.refresh(), isFalse);
      expect(n.state.errorType, 'snaptrade_refresh_limit');

      expect(await n.remove('auth-ibkr'), isTrue);
      expect(repo.removed, 'auth-ibkr');

      expect(await n.disconnect(keepAsManual: true), isTrue);
      expect(repo.disconnectedKeeping, isTrue);
      expect(n.state.connection.isConnected, isFalse);
    });
  });

  group('SnaptradeScreen', () {
    Future<void> pump(
      WidgetTester tester, {
      required SubscriptionTier tier,
      required SnaptradeConnection connection,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ProviderContainer().read(
        brightness == Brightness.light
            ? themeDataLightProvider
            : themeDataDarkProvider,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            snaptradeRepositoryProvider.overrideWithValue(_Repo(connection)),
            snaptradePortalLauncherProvider.overrideWithValue(_Portal()),
            subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
            snaptradeProvider.overrideWith(
              (ref) => SnaptradeNotifier(
                ref.watch(snaptradeRepositoryProvider),
                ref.watch(snaptradePortalLauncherProvider),
              ),
            ),
          ],
          child: MaterialApp(theme: theme, home: const SnaptradeScreen()),
        ),
      );
      // Porty respira (animación sin fin): avanzar el tiempo a mano.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    for (final brightness in Brightness.values) {
      testWidgets('Premium not connected: promises and one-broker note '
          '(${brightness.name})', (tester) async {
        await pump(
          tester,
          tier: SubscriptionTier.premium,
          connection: const SnaptradeConnection(),
          brightness: brightness,
        );
        expect(find.text('snaptrade_intro_title'), findsOneWidget);
        expect(find.text('snaptrade_point_read_only_title'), findsOneWidget);
        expect(find.text('snaptrade_connect_cta'), findsOneWidget);
        expect(
          find.textContaining('snaptrade_plan_note', findRichText: true),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('connected: brokers, skipped, estimated cost and actions '
          '(${brightness.name})', (tester) async {
        await pump(
          tester,
          tier: SubscriptionTier.premium,
          connection: _connected(
            brokerages: const [
              _ibkr,
              SnaptradeBrokerage(
                id: 'auth-schwab',
                name: 'Schwab',
                imported: false,
                reason: 'plan_limit',
              ),
            ],
          ),
          brightness: brightness,
        );
        expect(find.text('Interactive Brokers'), findsOneWidget);
        expect(find.text('snaptrade_broker_imported'), findsOneWidget);
        expect(find.text('snaptrade_broker_plan_limit'), findsOneWidget);
        expect(find.text('snaptrade_status_not_imported'), findsOneWidget);
        expect(find.text('snaptrade_estimated_cost'), findsOneWidget);
        expect(find.text('snaptrade_sync_now'), findsOneWidget);
        expect(find.text('snaptrade_add_another'), findsOneWidget);
        // Premium: el aviso de Gold para sumar otro.
        expect(
          find.textContaining('snaptrade_add_another_gold', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('snaptrade_disconnect'), findsOneWidget);
        // Hasta que SnapTrade confirme el costo, no hay "actualizar ahora".
        expect(find.text('snaptrade_refresh_now'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Free: paywall instead of the connect button', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.free,
        connection: const SnaptradeConnection(),
      );
      expect(find.text('snaptrade_see_plans'), findsOneWidget);
      expect(find.text('snaptrade_connect_cta'), findsNothing);
    });

    testWidgets('Gold: all brokers, no Gold upsell', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.gold,
        connection: const SnaptradeConnection(),
      );
      expect(
        find.textContaining('snaptrade_plan_note_gold', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a broken broker asks to reconnect it', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        connection: _connected(
          brokerages: const [
            SnaptradeBrokerage(
              id: 'auth-ibkr',
              name: 'Interactive Brokers',
              disabled: true,
            ),
          ],
        ),
      );
      expect(find.text('snaptrade_reconnect_title'), findsOneWidget);
      expect(find.text('snaptrade_broker_broken'), findsOneWidget);
      expect(find.text('snaptrade_reconnect_cta'), findsOneWidget);
      expect(find.text('snaptrade_status_reconnect'), findsOneWidget);
    });
  });
}
