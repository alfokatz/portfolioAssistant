import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/closed_position_detail_screen.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/closed_positions_screen.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';

class _UseCase implements GetClosedPositionsUseCase {
  _UseCase(this.list);
  final List<ClosedPosition> list;

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      Right(list);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClosedPosition _sale(String ticker, double buy, double sell, int month) =>
    ClosedPosition(
      id: ticker,
      ticker: ticker,
      quantity: 1,
      avgPurchasePrice: buy,
      closePrice: sell,
      closeDate: DateTime(2026, month, 1),
      closedAt: DateTime(2026, month, 1),
    );

/// Sin easy_localization cargado, `.tr()` devuelve la key.
Future<void> _pump(WidgetTester tester, List<ClosedPosition> sales) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        getClosedPositionsUseCaseProvider.overrideWithValue(_UseCase(sales)),
      ],
      child: MaterialApp(
        theme: ProviderContainer().read(themeDataLightProvider),
        home: const ClosedPositionsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the total of every sale on top; the latest sale first', (
    tester,
  ) async {
    await _pump(tester, [
      _sale('TSLA', 250, 165, 5), // -85
      _sale('AAPL', 180, 300, 6), // +120
    ]);
    expect(find.text('+\$35.00'), findsOneWidget); // resultado total
    expect(find.text('\$430.00'), findsOneWidget); // lo que pagaste
    expect(find.text('\$465.00'), findsOneWidget); // lo que recibiste
    expect(find.text('-\$85.00'), findsOneWidget);
    expect(find.text('+\$120.00'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('AAPL')).dy,
      lessThan(tester.getTopLeft(find.text('TSLA')).dy),
    );
  });

  testWidgets('without sales, Porty explains what will show up here', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('closed_positions_empty'), findsOneWidget);
    expect(find.text('closed_positions_empty_body'), findsOneWidget);
    expect(find.text('closed_positions_sales'), findsNothing);
  });

  group('sale detail', () {
    setUp(() => PortyAvatar.ambientMotion = false);
    tearDown(() => PortyAvatar.ambientMotion = true);

    Future<void> pumpRouter(
      WidgetTester tester,
      List<ClosedPosition> sales, {
      String? openId,
    }) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder:
                (context, _) =>
                    openId == null
                        ? const ClosedPositionsScreen()
                        : Scaffold(
                          body: TextButton(
                            onPressed:
                                () => GotoClosedPositionDetail(
                                  id: openId,
                                  ticker: 'AAPL',
                                ).navigate(context: context),
                            child: const Text('open'),
                          ),
                        ),
          ),
          ...PositionRouter.getRoutes(),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            getClosedPositionsUseCaseProvider.overrideWithValue(
              _UseCase(sales),
            ),
          ],
          child: MaterialApp.router(
            theme: ProviderContainer().read(themeDataLightProvider),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a sale opens its detail: result, what was sold and '
        'at what price', (tester) async {
      await pumpRouter(tester, [_sale('AAPL', 180, 300, 6)]);
      await tester.tap(find.text('AAPL'));
      await tester.pumpAndSettle();

      expect(find.byType(ClosedPositionDetailScreen), findsOneWidget);
      expect(find.text('closed_position_detail_result'), findsOneWidget);
      expect(find.text('+\$120.00'), findsOneWidget);
      expect(find.text('\$180.00'), findsWidgets); // compra promedio y pagado
      expect(find.text('\$300.00'), findsWidgets); // venta y recibido
      expect(find.text('closed_position_detail_porty_question'), findsOneWidget);
    });

    testWidgets('without the sale at hand it is loaded by id', (tester) async {
      await pumpRouter(tester, [
        _sale('AAPL', 180, 300, 6),
      ], openId: 'AAPL');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('+\$120.00'), findsOneWidget);
    });

    testWidgets('a sale that no longer exists: Porty says so', (tester) async {
      await pumpRouter(tester, [_sale('TSLA', 1, 2, 6)], openId: 'gone');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final message = tester.widget<PortyStatusMessage>(
        find.byType(PortyStatusMessage),
      );
      expect(message.title, 'closed_position_detail_not_found_title');
    });
  });
}
