import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';

PositionValuation _v(String ticker, double pnl, double pct) =>
    PositionValuation(
      position: Position(
        id: ticker,
        ticker: ticker,
        quantity: 1,
        purchasePrice: 100,
        purchaseDate: DateTime(2026, 1, 5),
      ),
      currentPrice: 100,
      marketValue: 100,
      pnlAbsolute: pnl,
      pnlPercent: pct,
    );

Widget _app(List<PositionValuation> valuations) {
  final container = ProviderContainer();
  return MaterialApp(
    theme: container.read(themeDataLightProvider),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PnlDistributionCard(valuations: valuations),
      ),
    ),
  );
}

void main() {
  testWidgets('rows from best to worst, with the numbers written '
      '(bug 2026-10-06: raw-double tooltip)', (tester) async {
    await tester.pumpWidget(
      _app([
        _v('AMZN', 120.5, 8.2),
        _v('TSLA', -45.1, -3.4),
        _v('VOO', 445.7497684488692, 12.3),
      ]),
    );

    final voo = tester.getTopLeft(find.text('VOO')).dy;
    final amzn = tester.getTopLeft(find.text('AMZN')).dy;
    final tsla = tester.getTopLeft(find.text('TSLA')).dy;
    expect(voo < amzn && amzn < tsla, isTrue);
    expect(find.text('+\$445.75'), findsOneWidget);
    expect(find.text('+12.3%'), findsOneWidget);
    expect(find.text('-\$45.10'), findsOneWidget);
    expect(find.text('-3.4%'), findsOneWidget);
    expect(find.byType(DivergingBar), findsNWidgets(3));
    expect(find.textContaining('445.749'), findsNothing);
  });

  testWidgets('long portfolios collapse to five with "show all"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([for (var i = 0; i < 8; i++) _v('T$i', 10.0 * i, i.toDouble())]),
    );
    expect(find.byType(DivergingBar), findsNWidgets(5));
    expect(find.text('home_pnl_show_all'), findsOneWidget);

    await tester.tap(find.text('home_pnl_show_all'));
    await tester.pumpAndSettle();
    expect(find.byType(DivergingBar), findsNWidgets(8));
    expect(find.text('home_pnl_show_less'), findsOneWidget);
  });

  testWidgets('six or fewer: no toggle', (tester) async {
    await tester.pumpWidget(
      _app([for (var i = 0; i < 6; i++) _v('T$i', 10.0 * i, i.toDouble())]),
    );
    expect(find.byType(DivergingBar), findsNWidgets(6));
    expect(find.text('home_pnl_show_all'), findsNothing);
  });
}
