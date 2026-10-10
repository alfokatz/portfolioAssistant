import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_price_on_date_use_case.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/close_position_screen.dart';

class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      const Right(716.85);
  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => Right([
    PriceCandle(
      date: DateTime.now().subtract(const Duration(days: 1)),
      close: 716.85,
    ),
  ]);
  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => [];
}

class _Closer implements ClosedPositionRepository {
  @override
  Future<Either<HttpError, List<ClosedPosition>>> getClosedPositions() async =>
      const Right([]);

  @override
  Future<Either<HttpError, ClosedPosition>> closePosition({
    required String positionId,
    required double quantity,
    required double closePrice,
    required DateTime closeDate,
  }) async => Right(
    ClosedPosition(
      id: 'c1',
      ticker: 'VOO',
      quantity: quantity,
      avgPurchasePrice: 509.84,
      closePrice: closePrice,
      closeDate: closeDate,
      closedAt: closeDate,
    ),
  );
}

/// Sin easy_localization cargado, `.tr()` devuelve la key.
Widget _app() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        name: HomeRouter.homeRouteName,
        path: '/',
        // Como en la app: el cierre se abre encima de otras pantallas.
        builder:
            (context, __) => Scaffold(
              body: Column(
                children: [
                  const Text('HOME'),
                  TextButton(
                    onPressed: () => context.push('/close'),
                    child: const Text('open close'),
                  ),
                ],
              ),
            ),
      ),
      GoRoute(
        path: '/close',
        builder:
            (_, __) => const ClosePositionScreen(
              positionId: 'a',
              ticker: 'VOO',
              quantity: 1,
              avgPurchasePrice: 509.84,
            ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      getPriceOnDateUseCaseProvider.overrideWithValue(
        GetPriceOnDateUseCase(quoteRepository: _Quotes()),
      ),
      closePositionUseCaseProvider.overrideWithValue(
        ClosePositionUseCase(repository: _Closer()),
      ),
    ],
    child: MaterialApp.router(
      theme: ProviderContainer().read(themeDataLightProvider),
      routerConfig: router,
    ),
  );
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.tap(find.text('open close'));
  await tester.pumpAndSettle();
  expect(find.text('HOME'), findsNothing);
  await tester.scrollUntilVisible(
    find.text('close_position_confirm'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('close_position_confirm'));
  // Porty respira en la confirmación (animación continua): sin
  // pumpAndSettle, el tiempo se avanza a mano.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('after closing, a confirmation with the result instead of '
      'going back to a position that no longer exists', (tester) async {
    await _close(tester);
    expect(find.text('close_position_success_all'), findsOneWidget);
    expect(find.text('+\$207.01'), findsOneWidget);
  });

  testWidgets('the button goes home', (tester) async {
    await _close(tester);
    await tester.scrollUntilVisible(
      find.text('close_position_success_done'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('close_position_success_done'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('"back" goes home too', (tester) async {
    await _close(tester);
    // El "atrás" del sistema (gesto o botón de Android).
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('HOME'), findsOneWidget);
  });
}
