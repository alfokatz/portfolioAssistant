import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/etoro/data/etoro_connection_repository.dart';
import 'package:portfolio_assistant/features/etoro/domain/etoro_connection.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_extras_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

ThemeData get _light => ProviderContainer().read(themeDataLightProvider);
ThemeData get _dark => ProviderContainer().read(themeDataDarkProvider);

class _Repo implements EtoroConnectionRepository {
  _Repo(this.connection);
  final EtoroConnection connection;

  @override
  Future<EtoroConnection> load() async => connection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoBrowser implements EtoroAuthLauncher {
  @override
  Future<Uri?> authenticate(Uri url) async => null;
}

Map<String, Object> _holding(
  String ticker,
  String reason,
  double value,
  double pnl,
) => {
  'ticker': ticker,
  'name': '$ticker Inc',
  'reason': reason,
  'count': 1,
  'units': 1,
  'investedUsd': value - pnl,
  'valueUsd': value,
  'pnlUsd': pnl,
};

EtoroImportResult _result({double? cash = 1250.5, int holdings = 2}) =>
    EtoroImportResult.fromJson({
      'imported': 3,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      if (cash != null) 'cashUsd': cash,
      'otherHoldings':
          [
            _holding('BTC', 'crypto', 1900, -50),
            _holding('BP.L', 'non_us', 650, 50),
            _holding('GOLD', 'unsupported_type', 300, 10),
            _holding('TSLA', 'short', 200, -20),
            _holding('EURUSD', 'unsupported_type', 100, 5),
            _holding('ETH', 'crypto', 90, 1),
          ].take(holdings).toList(),
    });

Widget _view(
  EtoroImportResult result, {
  ThemeData? theme,
  double textScale = 1,
}) => MaterialApp(
  theme: theme ?? _light,
  builder:
      (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
  home: Scaffold(
    body: SingleChildScrollView(child: EtoroExtrasCardView(result: result)),
  ),
);

void main() {
  testWidgets('muestra efectivo y otros activos con su valor y P&L de eToro', (
    tester,
  ) async {
    await tester.pumpWidget(_view(_result()));
    expect(find.text('etoro_extras_title'), findsOneWidget);
    expect(find.text('etoro_extras_cash'), findsOneWidget);
    expect(find.textContaining('1,250.50'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('BP.L'), findsOneWidget);
    expect(find.textContaining('1,900.00'), findsOneWidget);
    // −50 sobre 1950 invertidos.
    expect(find.textContaining('2.6%'), findsOneWidget);
    // Sin más de 4 filas no hay "Ver más".
    expect(find.text('etoro_extras_show_more'), findsNothing);
  });

  testWidgets('sin efectivo: solo los activos', (tester) async {
    await tester.pumpWidget(_view(_result(cash: null)));
    expect(find.text('etoro_extras_cash'), findsNothing);
    expect(find.text('BTC'), findsOneWidget);
  });

  testWidgets('con muchas filas: muestra 4 y "Ver más" despliega el resto', (
    tester,
  ) async {
    await tester.pumpWidget(_view(_result(holdings: 6)));
    expect(find.text('ETH'), findsNothing);
    expect(find.text('etoro_extras_show_more'), findsOneWidget);
    await tester.tap(find.text('etoro_extras_show_more'));
    await tester.pumpAndSettle();
    expect(find.text('ETH'), findsOneWidget);
    expect(find.text('etoro_extras_show_less'), findsOneWidget);
  });

  testWidgets('sin conectar no ocupa lugar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          etoroConnectionRepositoryProvider.overrideWithValue(
            _Repo(EtoroConnection.notConnected),
          ),
          etoroAuthLauncherProvider.overrideWithValue(_NoBrowser()),
        ],
        child: MaterialApp(
          theme: _light,
          home: const Scaffold(body: EtoroExtrasCard()),
        ),
      ),
    );
    expect(find.text('etoro_extras_title'), findsNothing);
  });

  testWidgets('conectada con extras: aparece; sin extras: no', (tester) async {
    Future<void> pumpWith(EtoroImportResult result) async {
      final container = ProviderContainer(
        overrides: [
          etoroConnectionRepositoryProvider.overrideWithValue(
            _Repo(
              EtoroConnection(
                status: EtoroConnectionStatus.connected,
                lastResult: result,
              ),
            ),
          ),
          etoroAuthLauncherProvider.overrideWithValue(_NoBrowser()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(etoroConnectionProvider.notifier).load();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: _light,
            home: const Scaffold(body: EtoroExtrasCard()),
          ),
        ),
      );
    }

    await pumpWith(_result());
    expect(find.text('etoro_extras_title'), findsOneWidget);
    await pumpWith(EtoroImportResult.fromJson({'imported': 3}));
    expect(find.text('etoro_extras_title'), findsNothing);
  });

  testWidgets('tema oscuro, pantalla chica y letra ×2 sin desbordes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 2, 568 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _view(_result(holdings: 6), theme: _dark, textScale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
