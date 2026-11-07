import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

/// Widgets de inversión y planificación: render del example del catálogo
/// (que también ve el modelo), casos degenerados y follow-ups.
void main() {
  final catalog = AssistantCatalog.build();
  CatalogItem item(String name) =>
      catalog.items.firstWhere((i) => i.name == name);

  /// Renderiza [name] con [data] arbitrario, opcionalmente dentro de un
  /// [QaFollowUpScope] que registra las preguntas enviadas.
  Future<List<String>> pumpItem(
    WidgetTester tester,
    String name,
    Map<String, dynamic> data, {
    bool withScope = false,
  }) async {
    final sent = <String>[];
    await tester.binding.setSurfaceSize(genuiTestViewportSize);
    final component = {'id': 'x', 'component': name, ...data};
    Widget body = SingleChildScrollView(
      child: Builder(
        builder:
            (context) => item(name).widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: component,
                catalog: catalog,
              ),
            ),
      ),
    );
    if (withScope) {
      body = QaFollowUpScope(onFollowUp: sent.add, child: body);
    }
    await tester.pumpWidget(genuiTestApp(child: body));
    await tester.pumpAndSettle();
    expect(find.byType(GenUiErrorCard), findsNothing);
    expect(tester.takeException(), isNull);
    return sent;
  }

  group('QaInvestOption', () {
    testWidgets('example renders identity, fit, price, tags and pros/cons', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaInvestOption'));
      await tester.pumpAndSettle();

      expect(find.text('NVDA'), findsOneWidget);
      expect(find.text('Buen encaje'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(find.text('\$120.50'), findsOneWidget);
      expect(find.text('7 días'), findsOneWidget);
      expect(find.text('Tecnología'), findsOneWidget);
      expect(find.text('Crecimiento'), findsOneWidget);
      expect(find.text('A FAVOR'), findsOneWidget);
      expect(find.text('EN CONTRA'), findsOneWidget);
      // Sin scope no hay a dónde mandar follow-ups: la barra no aparece.
      expect(find.byType(QaFollowUpBar), findsOneWidget);
      expect(find.text('Noticias'), findsNothing);
    });

    testWidgets('follow-ups include the budget simulation and send it', (
      tester,
    ) async {
      final sent = await pumpItem(tester, 'QaInvestOption', {
        'ticker': 'jpm',
        'thesis': 'Banco más grande de EE.UU.',
        'fitScore': 60,
        'pro': 'Dividendos estables',
        'con': 'Sensible a tasas',
        'budgetUsd': 500,
      }, withScope: true);

      expect(find.text('JPM'), findsOneWidget);
      expect(find.text('Encaje medio'), findsOneWidget);
      expect(find.text('Noticias'), findsOneWidget);
      await tester.ensureVisible(find.text('Simular \$500'));
      await tester.pump();
      await tester.tap(find.text('Simular \$500'));
      expect(sent, ['Simulá invertir \$500 en JPM']);
    });

    testWidgets('long thesis collapses to 3 lines with a local toggle', (
      tester,
    ) async {
      await pumpItem(tester, 'QaInvestOption', {
        'ticker': 'GS',
        'thesis': List.filled(40, 'banca de inversión').join(' '),
        'fitScore': 30,
        'pro': '',
        'con': '',
      });
      expect(find.text('Bajo encaje'), findsOneWidget);
      expect(find.text('Ver más'), findsOneWidget);
      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();
      expect(find.text('Ver menos'), findsOneWidget);
    });

    testWidgets('short thesis and missing optionals render cleanly', (
      tester,
    ) async {
      await pumpItem(tester, 'QaInvestOption', {'ticker': 'BAC'});
      expect(find.text('BAC'), findsOneWidget);
      expect(find.text('Ver más'), findsNothing);
      expect(find.text('7 días'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });
  });

  group('QaBudgetSplit', () {
    testWidgets('example: total hero, segmented bar, legend rows', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaBudgetSplit'));
      await tester.pumpAndSettle();

      expect(find.text('\$5,000'), findsOneWidget);
      expect(find.text('entre 3 activos'), findsOneWidget);
      expect(find.byType(QaSegmentedBar), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(QaProgressBar), findsNothing);
      expect(find.text('\$2,500'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('rows are tappable and fill a missing amount from pct', (
      tester,
    ) async {
      final sent = await pumpItem(tester, 'QaBudgetSplit', {
        'totalBudget': 1000,
        'items': [
          {'ticker': 'VOO', 'pct': 70},
          {'ticker': 'SCHD', 'amount': 300},
        ],
      }, withScope: true);

      expect(find.text('\$700'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      await tester.tap(find.text('VOO'));
      expect(sent, ['¿Cómo viene VOO?']);
    });

    testWidgets('empty items do not throw', (tester) async {
      await pumpItem(tester, 'QaBudgetSplit', {'totalBudget': 0, 'items': []});
      expect(find.text('Sin activos asignados'), findsOneWidget);
    });
  });

  testWidgets('QaInvestConfirm renders a receipt with ticker chips', (
    tester,
  ) async {
    await pumpCatalogItemExample(tester, catalog, item('QaInvestConfirm'));
    await tester.pumpAndSettle();

    expect(find.text('Simulación lista'), findsOneWidget);
    expect(find.text('\$5,000'), findsOneWidget);
    for (final t in ['NVDA', 'MSFT', 'AAPL']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.textContaining('No constituye asesoramiento'), findsOneWidget);
  });

  group('QaTipBanner', () {
    testWidgets('a tip carries the highlighted Porty signature', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item('QaTipBanner'));
      await tester.pumpAndSettle();

      expect(find.textContaining('concentración'), findsOneWidget);
      final shell = tester.widget<QaCardShell>(find.byType(QaCardShell));
      expect(shell.highlighted, isTrue);
    });

    testWidgets('a warning is a flat block, not a highlighted card', (
      tester,
    ) async {
      await pumpItem(tester, 'QaTipBanner', {
        'message': 'Ya tenés 60% en Tecnología.',
        'tone': 'warning',
      });
      expect(find.text('Ya tenés 60% en Tecnología.'), findsOneWidget);
      expect(find.byType(QaCardShell), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('empty message renders nothing', (tester) async {
      await pumpItem(tester, 'QaTipBanner', {'message': '', 'tone': 'info'});
      expect(find.byType(QaCardShell), findsNothing);
    });
  });
}
