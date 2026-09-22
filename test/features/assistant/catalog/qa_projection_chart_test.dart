import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_projection_chart.dart';

void main() {
  const points = [
    ProjectionChartPoint(label: 'Hoy', value: 5000),
    ProjectionChartPoint(label: 'Año 1', value: 9800),
    ProjectionChartPoint(label: 'Año 2', value: 14900),
    ProjectionChartPoint(label: 'Año 3', value: 20600),
  ];

  testWidgets('draws progressively and calls onFinished once settled', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QaProjectionChart(
            label: 'Proyección de tu meta',
            points: points,
            onFinished: () => finished = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(finished, isFalse);

    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.text('Proyección de tu meta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not start until active is true', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QaProjectionChart(
            label: 'Esperando turno',
            points: points,
            active: false,
            onFinished: () => finished = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(finished, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows the full line instantly', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: QaProjectionChart(
              label: 'Sin animación',
              points: points,
              onFinished: () => finished = true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing and still finishes with fewer than 2 points', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QaProjectionChart(
            label: 'Un solo punto',
            points: const [ProjectionChartPoint(label: 'Hoy', value: 100)],
            onFinished: () => finished = true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });
}
