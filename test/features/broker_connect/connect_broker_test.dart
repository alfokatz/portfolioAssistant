// "Conectá tu bróker": una entrada para todas las conexiones (eToro y
// Binance directo, el resto por SnapTrade), la card destacada de Ajustes y
// el botón de la Home. Claro y oscuro, a 320 de ancho.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/binance/data/binance_repository.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/broker_connect/view/connect_broker_screen.dart';
import 'package:portfolio_assistant/features/broker_connect/view/widgets/connect_broker_card.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_sync_client.dart';
import 'package:portfolio_assistant/features/snaptrade/data/snaptrade_repository.dart';
import 'package:portfolio_assistant/features/snaptrade/domain/snaptrade_connection.dart';
import 'package:portfolio_assistant/features/snaptrade/providers/snaptrade_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Binance implements BinanceRepository {
  _Binance(this.connection);

  final BinanceConnection connection;

  @override
  Future<BinanceConnection> load() async => connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snaptrade implements SnaptradeRepository {
  _Snaptrade(this.connection);

  final SnaptradeConnection connection;

  @override
  Future<SnaptradeConnection> load() async => connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    BinanceConnection binance = const BinanceConnection(),
    SnaptradeConnection snaptrade = const SnaptradeConnection(),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(320, 1600);
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
          // Sin Supabase: eToro sin conectar.
          etoroConnectionRepositoryProvider.overrideWithValue(
            EtoroConnectionRepository(
              client: () => null,
              syncClient: EtoroSyncClient(),
            ),
          ),
          binanceRepositoryProvider.overrideWithValue(_Binance(binance)),
          snaptradeRepositoryProvider.overrideWithValue(_Snaptrade(snaptrade)),
        ],
        child: MaterialApp(theme: theme, home: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('ConnectBrokerScreen', () {
    for (final brightness in Brightness.values) {
      testWidgets('eToro, Binance and another broker (${brightness.name})', (
        tester,
      ) async {
        await pump(tester, const ConnectBrokerScreen(), brightness: brightness);
        expect(find.text('connect_broker_title'), findsOneWidget);
        expect(find.text('eToro'), findsOneWidget);
        expect(find.text('Binance'), findsOneWidget);
        expect(find.text('connect_broker_others_title'), findsOneWidget);
        // Sin conectar: cada fila dice qué trae.
        expect(find.text('connect_broker_etoro_body'), findsOneWidget);
        expect(find.text('connect_broker_others_body'), findsOneWidget);
        expect(find.text('connect_broker_file_cta'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a connected broker shows its status instead', (tester) async {
      await pump(
        tester,
        const ConnectBrokerScreen(),
        binance: const BinanceConnection(status: BinanceStatus.connected),
        snaptrade: const SnaptradeConnection(
          status: SnaptradeStatus.connected,
          brokerages: [SnaptradeBrokerage(id: 'a1', name: 'Schwab')],
        ),
      );
      expect(find.text('connect_broker_binance_body'), findsNothing);
      expect(find.text('binance_settings_connected'), findsOneWidget);
      expect(find.text('Schwab'), findsOneWidget);
    });
  });

  group('ConnectBrokerCard', () {
    testWidgets('nothing connected: invites to connect', (tester) async {
      await pump(tester, const Scaffold(body: ConnectBrokerCard()));
      expect(find.text('connect_broker_card_title'), findsOneWidget);
      expect(find.text('connect_broker_cta'), findsOneWidget);
    });

    testWidgets('connected: lists them and offers to see or add', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: ConnectBrokerCard()),
        binance: const BinanceConnection(status: BinanceStatus.connected),
        snaptrade: const SnaptradeConnection(
          status: SnaptradeStatus.connected,
          brokerages: [SnaptradeBrokerage(id: 'a1', name: 'IBKR')],
        ),
      );
      // Ajustes carga las conexiones al abrir; acá, a mano.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ConnectBrokerCard)),
      );
      await container.read(binanceProvider.notifier).load();
      await container.read(snaptradeProvider.notifier).load();
      await tester.pump();
      expect(find.text('connect_broker_card_connected_title'), findsOneWidget);
      expect(find.text('Binance · IBKR'), findsOneWidget);
      expect(find.text('connect_broker_card_manage'), findsOneWidget);
    });
  });

  testWidgets('home button says "connect your broker"', (tester) async {
    await pump(tester, const Scaffold(body: ConnectBrokerButton()));
    expect(find.text('connect_broker_cta'), findsOneWidget);
  });
}
