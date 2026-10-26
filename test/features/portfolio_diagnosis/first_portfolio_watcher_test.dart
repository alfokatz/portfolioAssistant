import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/nav/portfolio_diagnosis_router.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/first_portfolio_watcher.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seen extends DiagnosisSeenNotifier {
  _Seen(bool seen) : super(null, null) {
    state = seen;
  }
}

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

HomeState _home(int positions, {bool loading = false, bool cache = false}) =>
    HomeState(
      loading: loading,
      fromCache: cache,
      summary: PortfolioSummary(
        totalValue: 100.0 * positions,
        totalCostBasis: 100.0 * positions,
        totalPnlAbsolute: 0,
        totalPnlPercent: 0,
        valuations: [
          for (var i = 0; i < positions; i++)
            PortfolioCalculator.valuate(
              position: Position(
                id: '$i',
                ticker: 'T$i',
                quantity: 1,
                purchasePrice: 100,
                purchaseDate: DateTime(2025),
              ),
              currentPrice: 100,
            ),
        ],
      ),
    );

void main() {
  late _Home home;
  late _Events events;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    bool seen = false,
    bool isHome = true,
  }) async {
    home = _Home(_home(0));
    events = _Events();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, __) => FirstPortfolioWatcher(
                isHome: isHome,
                child: const Text('home'),
              ),
        ),
        GoRoute(
          name: PortfolioDiagnosisRouter.routeName,
          path: PortfolioDiagnosisRouter.path,
          builder: (_, __) => const Text('diagnosis'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith((ref) => home),
          diagnosisSeenProvider.overrideWith((ref) => _Seen(seen)),
          productEventsProvider.overrideWithValue(events),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('vacía → con posiciones: registra el método y abre el '
      'diagnóstico', (tester) async {
    await pump(tester);
    container.read(portfolioLoadMethodProvider.notifier).state =
        PortfolioLoadMethod.file;
    home.state = _home(4);
    await tester.pumpAndSettle();

    expect(find.text('diagnosis'), findsOneWidget);
    expect(events.logged.single.$1, ProductEvent.portfolioLoaded);
    expect(events.logged.single.$2, {'method': 'file', 'count': 4});
    // El método se usa una vez.
    expect(container.read(portfolioLoadMethodProvider), isNull);
  });

  testWidgets('ya lo vio: registra la carga pero no lo abre', (tester) async {
    await pump(tester, seen: true);
    home.state = _home(2);
    await tester.pumpAndSettle();
    expect(find.text('diagnosis'), findsNothing);
    expect(events.logged.single.$2['method'], PortfolioLoadMethod.manual);
  });

  testWidgets('en otra pestaña espera a que vuelva a la Home', (tester) async {
    await pump(tester, isHome: false);
    home.state = _home(1);
    await tester.pumpAndSettle();
    expect(find.text('diagnosis'), findsNothing);
  });

  testWidgets('de la caché o cargando a con posiciones no es "primera '
      'carga"', (tester) async {
    await pump(tester);
    home.state = _home(0, cache: true);
    await tester.pumpAndSettle();
    home.state = _home(3);
    await tester.pumpAndSettle();
    expect(find.text('diagnosis'), findsNothing);
    expect(events.logged, isEmpty);
  });
}
