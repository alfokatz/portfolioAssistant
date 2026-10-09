import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/use_cases/get_position_lots_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_connection_screen.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_import_result_screen.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_disconnect_sheet.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_home_widgets.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/position_detail_screen.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

ThemeData get _light => ProviderContainer().read(themeDataLightProvider);
ThemeData get _dark => ProviderContainer().read(themeDataDarkProvider);

PositionValuation _lot(
  String id,
  double qty,
  PositionSource source, {
  DateTime? syncedAt,
}) => PortfolioCalculator.valuate(
  position: Position(
    id: id,
    ticker: 'AMZN',
    quantity: qty,
    purchasePrice: 150,
    purchaseDate: DateTime(2026, 3, 1),
    source: source,
    syncedAt: syncedAt,
  ),
  currentPrice: 200,
);

/// El detalle no espera la red: los lotes vienen de la Home.
class _NeverLots implements GetPositionLotsByTickerUseCase {
  @override
  Future<Either<HttpError, List<PositionValuation>>> call({
    required String params,
  }) => Completer<Either<HttpError, List<PositionValuation>>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements EtoroConnectionRepository {
  _Repo(this.connection);
  EtoroConnection connection;
  Completer<void>? syncGate;

  @override
  Future<EtoroConnection> load() async => connection;

  @override
  Future<({EtoroImportResult result, bool throttled})> sync() async {
    await syncGate?.future;
    return (result: connection.lastResult!, throttled: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoBrowser implements EtoroAuthLauncher {
  @override
  Future<Uri?> authenticate(Uri url) async => null;
}

EtoroImportResult _result() => EtoroImportResult.fromJson({
  'imported': 25,
  'closedImported': 4,
  'notImported': [
    {'ticker': 'AAPL', 'name': 'Apple', 'reason': 'leveraged', 'count': 2},
    {'ticker': 'BTC', 'name': 'Bitcoin', 'reason': 'crypto', 'count': 1},
  ],
  'closedNotImported': [],
  'possibleDuplicates': ['VOO'],
  'syncedAt': '2026-10-09T12:00:00Z',
});

Widget _app(Widget child, {List<Override> overrides = const [], ThemeData? theme}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: theme ?? _light, home: child),
    );

List<Override> _etoro(EtoroConnection connection, {_Repo? repo}) => [
  etoroConnectionRepositoryProvider.overrideWithValue(repo ?? _Repo(connection)),
  etoroAuthLauncherProvider.overrideWithValue(_NoBrowser()),
];

void main() {
  setUp(() => PortyAvatar.ambientMotion = false);
  tearDown(() => PortyAvatar.ambientMotion = true);

  group('marca de origen en la Home', () {
    testWidgets('una posición de eToro lleva la marca; una manual no', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Column(
              children: [
                PositionRowWidget(valuation: _lot('e', 1, PositionSource.etoro)),
                PositionRowWidget(valuation: _lot('m', 1, PositionSource.manual)),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(EtoroSourceBadge), findsOneWidget);
      expect(find.bySemanticsLabel('etoro_badge_semantics'), findsOneWidget);
    });

    testWidgets('lo importado no se borra deslizando; lo manual sí', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: PositionsSection(
                valuations: [
                  _lot('e', 1, PositionSource.etoro),
                  _lot('m', 1, PositionSource.manual).position.ticker == 'AMZN'
                      ? PortfolioCalculator.valuate(
                        position: _lot('m', 1, PositionSource.manual).position
                            .copyWith(ticker: 'MSFT'),
                        currentPrice: 200,
                      )
                      : _lot('m', 1, PositionSource.manual),
                ],
                onDeletePosition: (_) async => true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Dismissible), findsOneWidget);
      expect(
        find.ancestor(of: find.text('MSFT'), matching: find.byType(Dismissible)),
        findsOneWidget,
      );
    });

    testWidgets('sin posiciones: "Conectar eToro" como alternativa', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: PositionsSection(valuations: [], showConnectEtoro: true),
          ),
        ),
      );
      expect(find.byType(EtoroConnectButton), findsOneWidget);
      expect(find.text('etoro_connect_cta'), findsOneWidget);
    });
  });

  group('detalle de una posición de eToro', () {
    Widget detail(List<PositionValuation> lots) => _app(
      PositionDetailScreen(ticker: 'AMZN', seed: PositionDetailSeed.fromLots(lots)),
      overrides: [getPositionLotsByTickerUseCaseProvider.overrideWithValue(_NeverLots())],
    );

    testWidgets('"Se actualiza desde eToro" con la fecha, y nada para cerrar', (tester) async {
      await tester.pumpWidget(
        detail([
          _lot('a', 2, PositionSource.etoro, syncedAt: DateTime.now().subtract(const Duration(minutes: 5))),
          _lot('b', 1, PositionSource.etoro),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(EtoroSyncNote), 200);
      expect(find.text('etoro_detail_note'), findsOneWidget);
      expect(find.text('etoro_last_sync'), findsOneWidget);
      expect(find.text('position_detail_close_all'), findsNothing);
      expect(find.text('position_detail_close_lot'), findsNothing);
      expect(find.byType(EtoroSourceBadge), findsNWidgets(2));
    });

    testWidgets('compras mixtas: se cierra solo la manual, y lo dice', (tester) async {
      await tester.pumpWidget(
        detail([_lot('a', 2, PositionSource.etoro), _lot('b', 1, PositionSource.manual)]),
      );
      await tester.pumpAndSettle();
      expect(find.text('position_detail_close_lot'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(EtoroSyncNote), 200);
      expect(find.text('etoro_detail_partial_note'), findsOneWidget);
      expect(find.text('position_detail_close_all'), findsNothing);
    });

    testWidgets('una posición manual no cambia: cerrar todo sigue ahí', (tester) async {
      await tester.pumpWidget(detail([_lot('a', 2, PositionSource.manual)]));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('position_detail_close_all'), 200);
      expect(find.byType(EtoroSyncNote), findsNothing);
    });
  });

  group('pantalla de eToro', () {
    for (final (name, theme) in [('light', _light), ('dark', _dark)]) {
      testWidgets('sin conectar ($name): explica qué hace y ofrece conectar', (tester) async {
        await tester.pumpWidget(
          _app(
            const EtoroConnectionScreen(),
            overrides: _etoro(EtoroConnection.notConnected),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('etoro_intro_title'), findsOneWidget);
        expect(find.text('etoro_point_read_only_title'), findsOneWidget);
        expect(find.text('etoro_connect_cta'), findsOneWidget);
        expect(find.text('etoro_disconnect'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('conectada: última actualización, importadas y desconectar', (tester) async {
      await tester.pumpWidget(
        _app(
          const EtoroConnectionScreen(),
          overrides: _etoro(
            EtoroConnection(
              status: EtoroConnectionStatus.connected,
              lastSyncAt: DateTime.now().subtract(const Duration(minutes: 3)),
              lastResult: _result(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('etoro_connected_title'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // no importadas: 2 + 1
      expect(find.text('etoro_sync_now'), findsOneWidget);
      expect(find.text('etoro_disconnect'), findsOneWidget);
    });

    testWidgets('sincronizando: skeleton en los valores, nunca un spinner', (tester) async {
      final repo = _Repo(
        EtoroConnection(
          status: EtoroConnectionStatus.connected,
          lastSyncAt: DateTime.now().subtract(const Duration(hours: 1)),
          lastResult: _result(),
        ),
      )..syncGate = Completer<void>();
      await tester.pumpWidget(
        _app(const EtoroConnectionScreen(), overrides: _etoro(repo.connection, repo: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('etoro_sync_now'));
      await tester.pump();
      expect(find.text('etoro_syncing'), findsOneWidget);
      expect(find.byType(SkeletonScope), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repo.syncGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('etoro_sync_now'), findsOneWidget);
    });

    testWidgets('token vencido: "Reconectá tu cuenta" con lo importado intacto', (tester) async {
      await tester.pumpWidget(
        _app(
          const EtoroConnectionScreen(),
          overrides: _etoro(
            EtoroConnection(
              status: EtoroConnectionStatus.reconnectRequired,
              lastSyncAt: DateTime(2026, 10, 1, 10),
              lastResult: _result(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('etoro_reconnect_title'), findsOneWidget);
      expect(find.text('etoro_reconnect_cta'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      // Sin "Actualizar ahora" mientras la sesión está muerta.
      expect(find.text('etoro_sync_now'), findsNothing);
    });

    testWidgets('banner de la Home para reconectar', (tester) async {
      await tester.pumpWidget(_app(const Scaffold(body: EtoroReconnectBanner())));
      expect(find.text('etoro_reconnect_title'), findsOneWidget);
      expect(find.text('etoro_reconnect_short'), findsOneWidget);
    });
  });

  group('desconectar', () {
    testWidgets('por defecto conserva las posiciones como manuales', (tester) async {
      bool? choice = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    choice = await EtoroDisconnectSheet.show(context, importedCount: 25);
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('etoro_disconnect_keep_title'), findsOneWidget);
      await tester.tap(find.text('etoro_disconnect_confirm'));
      await tester.pumpAndSettle();
      expect(choice, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('etoro_disconnect_delete_title'));
      await tester.pump();
      await tester.tap(find.text('etoro_disconnect_confirm'));
      await tester.pumpAndSettle();
      expect(choice, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(choice, isNull);
    });
  });

  group('resultado de la importación', () {
    testWidgets('importadas, lo que no y por qué, y posibles duplicados', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          ..._etoro(
            EtoroConnection(
              status: EtoroConnectionStatus.connected,
              lastSyncAt: DateTime.now(),
              lastResult: _result(),
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      await container.read(etoroConnectionProvider.notifier).load();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: _light, home: const EtoroImportResultScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('etoro_result_title'), findsOneWidget);
      expect(find.text('etoro_result_subtitle_closed'), findsOneWidget);
      expect(find.text('etoro_skip_title_leveraged'), findsOneWidget);
      expect(find.text('etoro_skip_leveraged'), findsOneWidget);
      expect(find.text('AAPL ×2'), findsOneWidget);
      expect(find.text('BTC'), findsOneWidget);
      expect(find.text('etoro_result_duplicates_title'), findsOneWidget);
      expect(find.text('VOO'), findsOneWidget);

      // "Son distintas": no se vuelve a preguntar.
      await tester.tap(find.text('etoro_result_duplicates_keep'));
      await tester.pumpAndSettle();
      expect(find.text('etoro_result_duplicates_title'), findsNothing);
      expect(prefs.getStringList(etoroDismissedDuplicatesKey), ['VOO']);
    });
  });

  group('pantalla chica y letra grande (iPhone SE, texto ×2)', () {
    Future<void> pumpSmall(WidgetTester tester, Widget screen, List<Override> overrides) async {
      tester.view.physicalSize = const Size(320 * 2, 568 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: _light,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: child!,
                ),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final status in EtoroConnectionStatus.values) {
      testWidgets('pantalla de eToro (${status.name}) sin desbordes', (tester) async {
        await pumpSmall(
          tester,
          const EtoroConnectionScreen(),
          _etoro(
            EtoroConnection(
              status: status,
              lastSyncAt: DateTime.now().subtract(const Duration(hours: 3)),
              lastResult: _result(),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('resultado de la importación sin desbordes', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _Repo(
        EtoroConnection(
          status: EtoroConnectionStatus.connected,
          lastSyncAt: DateTime.now(),
          lastResult: _result(),
        ),
      );
      await pumpSmall(tester, const _LoadThen(child: EtoroImportResultScreen()), [
        ..._etoro(repo.connection, repo: repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('etoro_result_duplicates_title'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('etoro_result_duplicates_keep'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Carga la conexión antes de mostrar [child] (como al volver de conectar).
class _LoadThen extends ConsumerStatefulWidget {
  const _LoadThen({required this.child});
  final Widget child;

  @override
  ConsumerState<_LoadThen> createState() => _LoadThenState();
}

class _LoadThenState extends ConsumerState<_LoadThen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(etoroConnectionProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
