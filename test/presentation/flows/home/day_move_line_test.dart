// La línea "Hoy +$X (+Y%)" del hero de la Home: mismos textos que el widget.
// Correr: flutter test test/presentation/flows/home/day_move_line_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/portfolio_hero_section.dart';

PortfolioDayMove _move(DayMovePeriod p, double abs, double pct) =>
    PortfolioDayMove(
      absolute: abs,
      percent: pct,
      period: p,
      asOfDay: DateTime(2026, 11, 5),
      topContributor: null,
    );

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'shows period, signed amount and percent (${dark ? 'dark' : 'light'}, 375)',
      (tester) async {
        tester.view.physicalSize = const Size(375, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final probe = ProviderContainer();
        final theme =
            dark
                ? probe.read(themeDataDarkProvider)
                : probe.read(themeDataLightProvider);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  DayMoveLine(move: _move(DayMovePeriod.today, 123.45, 1.0)),
                  DayMoveLine(move: _move(DayMovePeriod.lastClose, -50, -0.4)),
                ],
              ),
            ),
          ),
        );

        // Sin traducciones cargadas, .tr() devuelve la clave.
        expect(find.textContaining('home_widget_period_today'), findsOneWidget);
        expect(find.textContaining(r'+$123.45 (+1.0%)'), findsOneWidget);
        expect(
          find.textContaining('home_widget_period_last_close'),
          findsOneWidget,
        );
        expect(find.textContaining(r'-$50.00 (-0.4%)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
