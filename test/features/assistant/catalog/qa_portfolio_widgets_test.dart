import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

final _catalog = AssistantCatalog.build();

CatalogItem _item(String name) =>
    _catalog.items.firstWhere((i) => i.name == name);

/// Monta [name] con un payload arbitrario (casos degenerados que no están
/// en exampleData), opcionalmente dentro de un [QaFollowUpScope].
Future<void> _pump(
  WidgetTester tester,
  String name,
  Map<String, Object?> data, {
  ValueChanged<String>? onFollowUp,
}) async {
  final item = _item(name);
  await tester.binding.setSurfaceSize(genuiTestViewportSize);
  final body = SingleChildScrollView(
    child: Builder(
      builder:
          (context) => item.widgetBuilder(
            catalogContextFor(
              buildContext: context,
              component: {'id': 'w', 'component': name, ...data},
              catalog: _catalog,
            ),
          ),
    ),
  );
  await tester.pumpWidget(
    genuiTestApp(
      child:
          onFollowUp == null
              ? body
              : QaFollowUpScope(onFollowUp: onFollowUp, child: body),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(GenUiErrorCard), findsNothing);
}

void main() {
  group('QaPositionsSnapshot', () {
    testWidgets('one position: singular tag, no "posiciones" grammar slip', (
      tester,
    ) async {
      await _pump(tester, 'QaPositionsSnapshot', {
        'totalValue': 1438.2,
        'pnlAbs': 428.1,
        'pnlPct': 42.37,
        'positionsCount': 1,
        'positions': [
          {'ticker': 'VOO', 'weightPct': 100},
        ],
      });
      expect(find.text('1 posición'), findsOneWidget);
      expect(find.text('\$1,438'), findsOneWidget);
      expect(find.text('\$428 · 42.4%'), findsOneWidget);
      expect(find.text('VOO'), findsOneWidget);
      expect(find.text('Otros'), findsNothing);
    });

    testWidgets('without positions: no allocation bar, no tag', (tester) async {
      await _pump(tester, 'QaPositionsSnapshot', {
        'totalValue': 0,
        'pnlAbs': 0,
        'pnlPct': 0,
      });
      expect(find.text('\$0'), findsOneWidget);
      expect(find.byType(QaSegmentedBar), findsNothing);
      expect(find.textContaining('posici'), findsNothing);
    });

    testWidgets('follow-ups hidden without scope, sent with scope', (
      tester,
    ) async {
      final data = {'totalValue': 100, 'pnlAbs': 1, 'pnlPct': 1};
      await _pump(tester, 'QaPositionsSnapshot', data);
      expect(find.text('Concentración'), findsNothing);

      final sent = <String>[];
      await _pump(tester, 'QaPositionsSnapshot', data, onFollowUp: sent.add);
      await tester.tap(find.text('Concentración'));
      expect(sent, ['¿Estoy muy concentrado?']);
    });
  });

  group('QaPeriodChange', () {
    testWidgets('example: label, signed amount, chip and start → end', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, _catalog, _item('QaPeriodChange'));
      await tester.pumpAndSettle();
      expect(find.text('ÚLTIMOS 7 DÍAS'), findsOneWidget);
      expect(find.text('+\$321'), findsOneWidget);
      expect(find.text('1.33%'), findsOneWidget);
      expect(find.text('\$24,030'), findsOneWidget);
      expect(find.text('\$24,351'), findsOneWidget);
    });

    testWidgets('loss without range + natural follow-up question', (
      tester,
    ) async {
      final sent = <String>[];
      await _pump(tester, 'QaPeriodChange', {
        'periodLabel': 'últimos 30 días',
        'changeAbs': -7.2,
        'changePct': -0.5,
      }, onFollowUp: sent.add);
      expect(find.text('-\$7'), findsOneWidget);
      expect(find.text('Al inicio'), findsNothing);
      await tester.tap(find.text('Qué subió más'));
      expect(sent, ['¿Cuál de mis acciones subió más en los últimos 30 días?']);
    });
  });

  group('QaConcentrationBar', () {
    testWidgets('example: donut with top weight and severity tag', (
      tester,
    ) async {
      await pumpCatalogItemExample(
        tester,
        _catalog,
        _item('QaConcentrationBar'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QaDonut), findsOneWidget);
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('38.2%'), findsOneWidget);
      expect(find.text('Moderada'), findsNothing);
      expect(find.text('Concentración moderada'), findsOneWidget);
    });

    testWidgets('single holding → 100% and "Alta concentración"', (
      tester,
    ) async {
      final sent = <String>[];
      await _pump(tester, 'QaConcentrationBar', {
        'title': 'Concentración en tu portfolio',
        'items': [
          {'ticker': 'VOO', 'weightPct': 100},
        ],
      }, onFollowUp: sent.add);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Alta concentración'), findsOneWidget);
      await tester.tap(find.text('Diversificar'));
      expect(sent, ['¿Cómo puedo diversificar?']);
    });

    testWidgets('empty / malformed items do not throw', (tester) async {
      await _pump(tester, 'QaConcentrationBar', {
        'items': ['VOO', null],
      });
      expect(
        find.text('No hay posiciones para medir la concentración.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('QaPnLBreakdown: hero result, stacked bar and legend', (
    tester,
  ) async {
    await pumpCatalogItemExample(tester, _catalog, _item('QaPnLBreakdown'));
    await tester.pumpAndSettle();
    expect(find.text('DESDE LA COMPRA'), findsOneWidget);
    expect(find.text('+\$1,240'), findsOneWidget);
    expect(find.text('Invertido'), findsOneWidget);
    expect(find.text('\$23,111'), findsOneWidget);
    expect(find.text('Ganancia'), findsOneWidget);
    expect(find.text('Valor actual'), findsOneWidget);
    expect(find.byType(QaSegmentedBar), findsOneWidget);
  });

  group('QaTopMovers', () {
    testWidgets('tiles are tappable and ask about the ticker', (tester) async {
      final sent = <String>[];
      await _pump(tester, 'QaTopMovers', {
        'best': {'ticker': 'NVDA', 'pnlPct': 12},
        'worst': {'ticker': 'MSFT', 'pnlPct': -3},
      }, onFollowUp: sent.add);
      await tester.tap(find.text('MSFT'));
      expect(sent, ['¿Cómo viene MSFT?']);
      expect(find.text('Por qué MSFT'), findsOneWidget);
    });

    testWidgets('same ticker in best and worst → a single tile', (
      tester,
    ) async {
      await _pump(tester, 'QaTopMovers', {
        'best': {'ticker': 'VOO', 'pnlPct': 42},
        'worst': {'ticker': 'VOO', 'pnlPct': 42},
      });
      expect(find.text('Mejor'), findsOneWidget);
      expect(find.text('Peor'), findsNothing);
    });
  });

  group('QaPositionList', () {
    testWidgets('example rows show weight, value and P&L chip', (tester) async {
      await pumpCatalogItemExample(tester, _catalog, _item('QaPositionList'));
      await tester.pumpAndSettle();
      expect(find.text('2 posiciones'), findsOneWidget);
      expect(find.text('23.0% del portfolio'), findsOneWidget);
      expect(find.text('\$2,864'), findsOneWidget);
      expect(find.text('4.2%'), findsOneWidget);
    });

    testWidgets('more than 6 rows collapse behind "Ver todas (n)"', (
      tester,
    ) async {
      final sent = <String>[];
      await _pump(tester, 'QaPositionList', {
        'items': [
          for (final t in [
            'AAA',
            'BBB',
            'CCC',
            'DDD',
            'EEE',
            'FFF',
            'GGG',
            'HHH',
          ])
            {'ticker': t, 'weightPct': 12.5, 'pnlPct': 1},
        ],
      }, onFollowUp: sent.add);
      expect(find.text('GGG'), findsNothing);
      await tester.tap(find.text('Ver todas (8)'));
      await tester.pumpAndSettle();
      expect(find.text('HHH'), findsOneWidget);
      expect(sent, isEmpty, reason: 'expand is local, not a follow-up');
      await tester.tap(find.text('AAA'));
      expect(sent, ['¿Cómo me va con AAA?']);
    });

    testWidgets('empty list → friendly empty state', (tester) async {
      await _pump(tester, 'QaPositionList', {'items': <Object>[]});
      expect(find.text('No tenés posiciones abiertas'), findsOneWidget);
    });
  });

  group('QaClosedPositionList', () {
    testWidgets('example: realized total header + rows', (tester) async {
      await pumpCatalogItemExample(
        tester,
        _catalog,
        _item('QaClosedPositionList'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resultado realizado'), findsOneWidget);
      expect(find.text('+\$155'), findsOneWidget);
      expect(find.text('2 operaciones'), findsOneWidget);
      expect(find.text('Cerrada el 3 jun 2026'), findsOneWidget);
      expect(find.text('+\$240'), findsOneWidget);
      expect(find.text('-\$85'), findsOneWidget);
    });

    testWidgets('empty or missing items → empty state, never an error', (
      tester,
    ) async {
      await _pump(tester, 'QaClosedPositionList', {'items': <Object>[]});
      expect(find.text('Todavía no cerraste posiciones'), findsOneWidget);
      await _pump(tester, 'QaClosedPositionList', {'title': 'Cerradas'});
      expect(find.text('Todavía no cerraste posiciones'), findsOneWidget);
    });

    testWidgets('string numbers and missing optional fields are tolerated', (
      tester,
    ) async {
      await _pump(tester, 'QaClosedPositionList', {
        'items': [
          {'ticker': 'AAPL', 'pnlPct': '12.5', 'pnlAbs': '240'},
        ],
      });
      expect(find.text('Cerrada'), findsOneWidget);
      expect(find.text('+\$240'), findsOneWidget);
      expect(find.text('Resultado realizado'), findsNothing);
    });
  });
}
