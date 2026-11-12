import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_market_parts.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  final catalog = AssistantCatalog.build();
  CatalogItem item(String name) =>
      catalog.items.firstWhere((i) => i.name == name);

  /// Renderiza un payload arbitrario (no el example) del componente.
  Future<void> pumpComponent(
    WidgetTester tester,
    Map<String, dynamic> component, {
    ValueChanged<String>? onFollowUp,
  }) async {
    await tester.binding.setSurfaceSize(genuiTestViewportSize);
    final body = SingleChildScrollView(
      child: Builder(
        builder:
            (context) => item(component['component'] as String).widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: {'id': 'x', ...component},
                catalog: catalog,
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
  }

  group('QaMarketParts', () {
    test('parses model-formatted numbers', () {
      expect(QaMarketParts.parseLooseNumber('+1,2%'), 1.2);
      expect(QaMarketParts.parseLooseNumber('-\$1.240'), -1.24);
      expect(QaMarketParts.parseLooseNumber('\$24.350,5'), 24350.5);
      expect(QaMarketParts.parseLooseNumber('n/a'), isNull);
      expect(QaMarketParts.looksLikeTicker('BRK.B'), isTrue);
      expect(QaMarketParts.looksLikeTicker('P&L %'), isFalse);
      expect(QaMarketParts.weightLabel(12.4), '12% de tu portfolio');
      expect(QaMarketParts.weightLabel(2.5), '2.5% de tu portfolio');
    });
  });

  group('QaTickerSnapshot', () {
    testWidgets('header, hero price and period chips', (tester) async {
      await pumpCatalogItemExample(tester, catalog, item('QaTickerSnapshot'));
      expect(find.text('NVDA'), findsOneWidget);
      expect(find.text('\$120.50'), findsOneWidget);
      for (final label in ['Día', 'Semana', 'Mes']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('1.20%'), findsOneWidget);
      expect(find.text('2.10%'), findsOneWidget);
    });

    testWidgets('missing periods are omitted, never shown as 0', (
      tester,
    ) async {
      await pumpComponent(tester, {
        'component': 'QaTickerSnapshot',
        'ticker': 'VOO',
        'currentPrice': 500,
      });
      expect(find.text('\$500.00'), findsOneWidget);
      expect(find.text('Día'), findsNothing);
      expect(find.text('0.00%'), findsNothing);
    });

    testWidgets('follow-ups exclude the chart and send the question', (
      tester,
    ) async {
      final sent = <String>[];
      await pumpComponent(tester, {
        'component': 'QaTickerSnapshot',
        'ticker': 'VOO',
        'currentPrice': 500,
      }, onFollowUp: sent.add);
      expect(find.text('Gráfico'), findsNothing);
      await tester.tap(find.text('Noticias'));
      expect(sent, ['¿Qué noticias hay de VOO?']);
    });
  });

  group('QaTickerMove', () {
    testWidgets('hero end price, change chip, period and weight', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaTickerMove'));
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('\$190.16'), findsNWidgets(2)); // hero + "Cierre"
      expect(find.text('\$8.34 (4.20%)'), findsOneWidget);
      expect(find.text('Últimos 7 días'), findsOneWidget);
      expect(find.text('23% de tu portfolio'), findsOneWidget);
      expect(find.text('-\$8.34'), findsOneWidget);
    });

    testWidgets('without prices shows the % as hero', (tester) async {
      await pumpComponent(tester, {
        'component': 'QaTickerMove',
        'ticker': 'AAPL',
        'periodLabel': 'último día',
        'changePct': 1.5,
      });
      expect(find.text('+1.50%'), findsOneWidget);
      expect(find.text('Inicio'), findsNothing);
    });
  });

  group('QaMetricStrip', () {
    testWidgets('ticker rows with chips, period and a subtle leader', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaMetricStrip'));
      expect(find.text('NVDA vs AMD'), findsOneWidget);
      expect(find.text('Variación · Último día'), findsOneWidget);
      expect(find.text('3,4%'), findsOneWidget);
      expect(find.text('1,2%'), findsOneWidget);
      expect(find.text('Lidera'), findsOneWidget);
    });

    testWidgets('follow-ups lead to the compare chart', (tester) async {
      final sent = <String>[];
      await pumpComponent(tester, {
        'component': 'QaMetricStrip',
        'items': [
          {'label': 'AAPL', 'value': '-1,96%', 'trend': 'down'},
          {'label': 'MSFT', 'value': '+1,39%', 'trend': 'up'},
        ],
      }, onFollowUp: sent.add);
      await tester.tap(find.text('Gráfico 1 año'));
      expect(sent, ['Compará el rendimiento de AAPL y MSFT en el último año']);
    });

    testWidgets('non-ticker labels render as metric columns', (tester) async {
      await pumpComponent(tester, {
        'component': 'QaMetricStrip',
        'items': [
          {'label': 'Valor', 'value': '\$24.350', 'trend': 'neutral'},
          {'label': 'P&L', 'value': '+\$1.240', 'trend': 'up'},
        ],
      });
      expect(find.text('Valor'), findsOneWidget);
      expect(find.text('+\$1.240'), findsOneWidget);
      expect(find.text('Lidera'), findsNothing);
    });

    testWidgets('empty items → message, no crash', (tester) async {
      await pumpComponent(tester, {
        'component': 'QaMetricStrip',
        'items': <Object>[],
      });
      expect(find.text('Sin datos para comparar.'), findsOneWidget);
    });
  });

  group('QaComparisonRow', () {
    testWidgets('two sides with big values and the larger one tagged', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaComparisonRow'));
      expect(find.text('Mayor concentración'), findsOneWidget);
      expect(find.text('Peso en el portfolio'), findsOneWidget);
      expect(find.text('38,2%'), findsOneWidget);
      expect(find.text('22,5%'), findsOneWidget);
      expect(find.text('Mayor'), findsOneWidget); // valores sin signo
      expect(find.text('vs'), findsOneWidget);
    });

    testWidgets('signed values tag the better one as "Mejor"', (tester) async {
      await pumpComponent(tester, {
        'component': 'QaComparisonRow',
        'label': '¿Con cuál ganaste más?',
        'leftTicker': 'AAPL',
        'leftValue': '-3,1%',
        'rightTicker': 'MSFT',
        'rightValue': '+12,4%',
        'metricLabel': 'Rendimiento en tu cartera',
      });
      expect(find.text('Mejor'), findsOneWidget);
      expect(find.text('+12,4%'), findsOneWidget);
    });

    testWidgets('missing values degrade to dashes', (tester) async {
      await pumpComponent(tester, {
        'component': 'QaComparisonRow',
        'label': '',
        'leftTicker': 'AAPL',
        'leftValue': '',
        'rightTicker': 'MSFT',
        'rightValue': 'n/a',
      });
      expect(find.text('Comparación'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Mejor'), findsNothing);
      expect(find.text('Mayor'), findsNothing);
    });
  });
}
