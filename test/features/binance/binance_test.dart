import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/binance/view/binance_screen.dart';
import 'package:portfolio_assistant/features/binance/view/widgets/binance_source_badge.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Repo implements BinanceRepository {
  _Repo(this.connection);

  BinanceConnection connection;
  BinanceException? failConnect;
  BinanceException? failSync;
  int syncs = 0;
  bool? disconnectedKeeping;

  @override
  Future<BinanceConnection> load() async => connection;

  @override
  Future<BinanceSyncResult?> connect({
    required String apiKey,
    required String apiSecret,
  }) async {
    if (failConnect != null) throw failConnect!;
    connection = BinanceConnection(
      status: BinanceStatus.connected,
      apiKeyHint: apiKey.substring(apiKey.length - 4),
      lastSyncAt: DateTime.now(),
      lastResult: const BinanceSyncResult(imported: 2),
    );
    return connection.lastResult;
  }

  @override
  Future<({BinanceSyncResult? result, bool throttled})> sync() async {
    syncs++;
    if (failSync != null) throw failSync!;
    return (result: const BinanceSyncResult(imported: 1), throttled: false);
  }

  @override
  Future<void> disconnect({required bool keepAsManual}) async {
    disconnectedKeeping = keepAsManual;
    connection = const BinanceConnection();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('dominio', () {
    test('fila de la conexión y resultado', () {
      final c = BinanceConnection.fromRow({
        'status': 'reconnect_required',
        'api_key_hint': 'ab12',
        'last_sync_at': '2026-10-16T12:00:00Z',
        'last_result': {
          'imported': 3,
          'notImported': [
            {'asset': 'USDT', 'reason': 'cash'},
            {'asset': 7, 'reason': 'x'},
          ],
          'estimatedCost': ['SOL-USD'],
        },
      });
      expect(c.status, BinanceStatus.reconnectRequired);
      expect(c.isConnected, isTrue);
      expect(c.lastResult!.imported, 3);
      expect(c.lastResult!.notImported.single.asset, 'USDT');
      expect(c.lastResult!.estimatedCost, ['SOL-USD']);
      expect(BinanceConnection.fromRow(null).isConnected, isFalse);
    });

    test('origen de la posición: binance y las mezclas', () {
      expect(PositionSource.fromWire('binance'), PositionSource.binance);
      expect(PositionSource.binance.hasImported, isTrue);
      expect(
        PositionSource.combine({PositionSource.manual, PositionSource.binance}),
        PositionSource.mixedBinance,
      );
      expect(
        PositionSource.combine({PositionSource.manual, PositionSource.etoro}),
        PositionSource.mixed,
      );
      expect(PositionSource.mixedBinance.isBinance, isTrue);
      expect(PositionSource.mixed.isBinance, isFalse);
    });

    testWidgets('la marca según el bróker', (tester) async {
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Row(
            children: [
              BrokerSourceBadge(source: PositionSource.mixedBinance),
              BrokerSourceBadge(source: PositionSource.etoro),
            ],
          ),
        ),
      );
      expect(find.byType(BinanceSourceBadge), findsOneWidget);
      expect(find.byType(EtoroSourceBadge), findsOneWidget);
    });
  });

  group('BinanceNotifier', () {
    test('conectar recarga la Home; un error queda para mostrar', () async {
      final repo = _Repo(const BinanceConnection());
      var refreshed = 0;
      final n = BinanceNotifier(repo, onImported: () async => refreshed++);
      await n.load();
      expect(
        await n.connect(apiKey: 'k' * 60 + 'ab12', apiSecret: 's' * 64),
        isTrue,
      );
      expect(n.state.connection.apiKeyHint, 'ab12');
      expect(refreshed, 1);

      final bad = _Repo(const BinanceConnection())
        ..failConnect = const BinanceException('binance_write_permissions');
      final m = BinanceNotifier(bad);
      expect(await m.connect(apiKey: 'k', apiSecret: 's'), isFalse);
      expect(m.state.errorType, 'binance_write_permissions');
      expect(m.state.busy, isFalse);
    });

    test('al abrir: sincroniza solo si está conectada y es viejo', () async {
      final now = DateTime(2026, 10, 16, 12);
      final repo = _Repo(
        BinanceConnection(
          status: BinanceStatus.connected,
          lastSyncAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      final n = BinanceNotifier(repo);
      await n.syncIfStale(now: now);
      expect(repo.syncs, 0);
      await n.syncIfStale(now: now.add(const Duration(hours: 1)));
      expect(repo.syncs, 1);

      final off = _Repo(const BinanceConnection());
      await BinanceNotifier(off).syncIfStale(now: now);
      expect(off.syncs, 0);
    });

    test('desconectar con la decisión del usuario', () async {
      final repo = _Repo(
        const BinanceConnection(status: BinanceStatus.connected),
      );
      final n = BinanceNotifier(repo);
      await n.load();
      expect(await n.disconnect(keepAsManual: false), isTrue);
      expect(repo.disconnectedKeeping, isFalse);
      expect(n.state.connection.isConnected, isFalse);
    });
  });

  group('pantalla', () {
    Future<void> pump(
      WidgetTester tester, {
      required SubscriptionTier tier,
      required BinanceConnection connection,
    }) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            binanceRepositoryProvider.overrideWithValue(_Repo(connection)),
            subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
            binanceProvider.overrideWith(
              (ref) => BinanceNotifier(ref.watch(binanceRepositoryProvider)),
            ),
          ],
          child: MaterialApp(theme: theme, home: const BinanceScreen()),
        ),
      );
      // Porty respira (animación sin fin): avanzar el tiempo a mano.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('Premium sin conectar: pasos y formulario', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        connection: const BinanceConnection(),
      );
      expect(find.text('binance_steps_title'), findsOneWidget);
      expect(find.text('binance_connect_cta'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Free: paywall en vez del formulario', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.free,
        connection: const BinanceConnection(),
      );
      expect(find.text('binance_see_plans'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('conectada: resultado, costo estimado y acciones', (
      tester,
    ) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        connection: BinanceConnection(
          status: BinanceStatus.connected,
          apiKeyHint: 'ab12',
          lastSyncAt: DateTime.now(),
          lastResult: const BinanceSyncResult(
            imported: 2,
            notImported: [BinanceSkipped('USDT', 'cash')],
            estimatedCost: ['SOL-USD'],
          ),
        ),
      );
      expect(find.text('binance_status_imported'), findsOneWidget);
      expect(find.text('binance_estimated_cost'), findsOneWidget);
      expect(find.text('binance_sync_now'), findsOneWidget);
      expect(find.text('binance_disconnect'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hay que reconectar: vuelve el formulario', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        connection: const BinanceConnection(
          status: BinanceStatus.reconnectRequired,
        ),
      );
      expect(find.text('binance_reconnect_body'), findsOneWidget);
      expect(find.text('binance_reconnect_cta'), findsOneWidget);
    });
  });
}
