import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/closed_positions_screen.dart';

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
}
