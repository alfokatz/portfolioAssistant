import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/use_cases/get_position_lots_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/positions_section.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/position_detail_screen.dart';

/// Use case de lotes controlado por el test: no responde hasta que se
/// completa [completer], así se prueba que nada espera la red.
class _PendingLots implements GetPositionLotsByTickerUseCase {
  final completer = Completer<Either<HttpError, List<PositionValuation>>>();
  var calls = 0;

  @override
  Future<Either<HttpError, List<PositionValuation>>> call({
    required String params,
  }) {
    calls++;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PositionValuation _lot(
  String id,
  double qty,
  double buy,
  double now,
  int day,
) => PortfolioCalculator.valuate(
  position: Position(
    id: id,
    ticker: 'AMZN',
    quantity: qty,
    purchasePrice: buy,
    purchaseDate: DateTime(2026, 3, day),
  ),
  currentPrice: now,
);

final _lots = [_lot('a', 2, 150, 200, 20), _lot('b', 1, 180, 200, 5)];
final _seed = PositionDetailSeed.fromLots(_lots)!;

ThemeData get _theme => ProviderContainer().read(themeDataLightProvider);

Widget _detail(_PendingLots lots, {PositionDetailSeed? seed}) => ProviderScope(
  overrides: [getPositionLotsByTickerUseCaseProvider.overrideWithValue(lots)],
  child: MaterialApp(
    theme: _theme,
    home: PositionDetailScreen(ticker: 'AMZN', seed: seed),
  ),
);

void main() {
  testWidgets('with the home data, the summary and every purchase are on '
      'screen from the first frame — no spinner, no wait', (tester) async {
    final lots = _PendingLots();
    await tester.pumpWidget(_detail(lots, seed: _seed));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('\$600.00'), findsOneWidget); // valor de mercado total
    expect(find.text('+\$120.00 (25.00%)'), findsOneWidget);
    expect(find.text('+\$100.00'), findsOneWidget); // lote a
    expect(find.text('+\$20.00'), findsOneWidget); // lote b
    // La red sigue pendiente: lo de arriba no dependió de ella.
    expect(lots.completer.isCompleted, isFalse);
  });

  testWidgets('a fresher price updates the values in place, without '
      'remounting the list', (tester) async {
    final lots = _PendingLots();
    await tester.pumpWidget(_detail(lots, seed: _seed));
    await tester.pumpAndSettle();
    final listBefore = tester.element(find.byType(ListView));

    lots.completer.complete(
      Right([_lot('a', 2, 150, 210, 20), _lot('b', 1, 180, 210, 5)]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // A mitad del crossfade del valor conviven viejo y nuevo...
    expect(find.text('\$630.00'), findsOneWidget);
    await tester.pumpAndSettle();
    // ...y al final solo queda el nuevo, en la misma lista.
    expect(find.text('\$600.00'), findsNothing);
    expect(find.text('\$630.00'), findsOneWidget);
    expect(tester.element(find.byType(ListView)), same(listBefore));
  });

  testWidgets('without data (deep link) it shows a skeleton with the final '
      'layout instead of a centered spinner, then crossfades to content', (
    tester,
  ) async {
    final lots = _PendingLots();
    await tester.pumpWidget(_detail(lots));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Mismos labels que el contenido real.
    expect(find.text('position_detail_summary'), findsOneWidget);
    final summaryTop = tester.getTopLeft(find.text('position_detail_summary'));
    final purchasesTop = tester.getTopLeft(
      find.text('position_detail_purchases'),
    );

    lots.completer.complete(Right(_lots));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Crossfade: los dos estados se ven a la vez solo durante el fade.
    await tester.pumpAndSettle();
    expect(find.text('\$600.00'), findsOneWidget);
    // Nada se movió: el skeleton tenía la altura final.
    expect(tester.getTopLeft(find.text('position_detail_summary')), summaryTop);
    expect(
      tester.getTopLeft(find.text('position_detail_purchases')),
      purchasesTop,
    );
  });

  testWidgets('with disableAnimations the content appears in its final '
      'state right away', (tester) async {
    final lots = _PendingLots();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _detail(lots),
      ),
    );
    await tester.pump();
    lots.completer.complete(Right(_lots));
    await tester.pump();
    await tester.pump();

    expect(find.text('\$600.00'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('tapping a position pushes the detail right away (go_router\'s '
      'one parsing frame), already filled, without waiting for any future', (
    tester,
  ) async {
    final lots = _PendingLots();
    final summary = _seed.summary;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => Scaffold(
                body: PositionsSection(
                  valuations: [summary],
                  onPositionTap:
                      (v) => GotoPositionDetail(
                        ticker: v.position.ticker,
                        seed: _seed,
                      ).navigate(context: context),
                ),
              ),
        ),
        ...PositionRouter.getRoutes(),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          getPositionLotsByTickerUseCaseProvider.overrideWithValue(lots),
        ],
        child: MaterialApp.router(theme: _theme, routerConfig: router),
      ),
    );

    await tester.tap(find.byType(PositionRowWidget));
    var frames = 0;
    while (find.byType(PositionDetailScreen).evaluate().isEmpty &&
        frames < 10) {
      await tester.pump();
      frames++;
    }
    // Frame 1: go_router procesa la ruta (su parseo es asíncrono); frame 2:
    // la ruta ya está construida y llena. Nada espera la red.
    expect(frames, lessThanOrEqualTo(2));
    expect(find.byType(PositionDetailScreen), findsOneWidget);
    expect(find.text('+\$120.00 (25.00%)'), findsOneWidget);
    expect(lots.completer.isCompleted, isFalse);
    await tester.pumpAndSettle();
  });
}
