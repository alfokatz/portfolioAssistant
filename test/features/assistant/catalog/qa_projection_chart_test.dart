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

  testWidgets(
    'does not crash when mounted active under reduced motion and '
    'onFinished mutates ancestor state synchronously (regression: '
    'setState during build)',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: _MutatingAncestor(
                builder: (context, mutate) => QaProjectionChart(
                  label: 'Sin animación',
                  points: points,
                  onFinished: mutate,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sin animación'), findsOneWidget);
    },
  );

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

/// Ancestro mínimo cuyo `setState()` se dispara desde el `builder` que le
/// pasa el caller — simula el `onFinished` real de `AssistantScreen`, que
/// hace `notifier.markRevealed(...)` sincrónicamente cuando un widget de
/// reveal ya montado revelado dispara su callback durante el build.
class _MutatingAncestor extends StatefulWidget {
  const _MutatingAncestor({required this.builder});

  final Widget Function(BuildContext context, VoidCallback mutate) builder;

  @override
  State<_MutatingAncestor> createState() => _MutatingAncestorState();
}

class _MutatingAncestorState extends State<_MutatingAncestor> {
  @override
  Widget build(BuildContext context) {
    return widget.builder(context, () => setState(() {}));
  }
}
