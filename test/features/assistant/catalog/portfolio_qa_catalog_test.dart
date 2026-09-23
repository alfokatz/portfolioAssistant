import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

void main() {
  // Cada modo debe recibir solo los widgets `Qa*` que su propia guía de
  // prompt referencia — antes los 5 modos compartían el catálogo completo
  // de 19 widgets, inflando el JSON schema embebido en cada prompt con
  // widgets que ese modo ni puede usar. `Catalog.copyWith(newItems: ...)`
  // en el paquete `genui` MERGEA por nombre en vez de reemplazar — por
  // eso `PortfolioQaCatalog._buildFrom` arranca siempre de un
  // `BasicCatalogItems.asCatalog()` limpio, no de un catálogo ya poblado
  // con los 19 ítems, así no hay contaminación cruzada entre modos. Este
  // test es la verificación determinística más cercana posible a "la
  // decisión texto-vs-widget" que se puede hacer sin mockear al modelo:
  // confirma el universo de opciones que el modelo tiene disponible por
  // modo, ya que la elección final del `component` la hace el LLM, no
  // código de la app.
  Set<String> qaItemNames(AssistantMode mode) {
    final catalog = AssistantCatalog.buildFor(mode);
    return catalog.items
        .map((item) => item.name)
        .where((name) => name.startsWith('Qa'))
        .toSet();
  }

  test('learn mode only exposes QaAnswerText and QaTipBanner', () {
    expect(
      qaItemNames(AssistantMode.learn),
      {'QaAnswerText', 'QaTipBanner'},
    );
  });

  test('explore mode exposes only the widgets its guide references', () {
    expect(
      qaItemNames(AssistantMode.explore),
      {
        'QaAnswerText',
        'QaTickerSnapshot',
        'QaTickerMove',
        'QaMetricStrip',
        'QaEarningsCalendar',
        'QaNewsSummary',
        'QaTipBanner',
      },
    );
  });

  test('invest mode exposes only the widgets its guide references', () {
    expect(
      qaItemNames(AssistantMode.invest),
      {
        'QaAnswerText',
        'QaBudgetSplit',
        'QaInvestOption',
        'QaInvestConfirm',
        'QaTipBanner',
      },
    );
  });

  test('plan mode exposes only the widgets its guide references', () {
    expect(
      qaItemNames(AssistantMode.plan),
      {
        'QaAnswerText',
        'QaGoalCard',
        'QaProjectionStrip',
        'QaProjectionChart',
        'QaMilestoneList',
        'QaTipBanner',
      },
    );
  });

  test('portfolio mode exposes the widgets its own guide references', () {
    expect(
      qaItemNames(AssistantMode.portfolio),
      {
        'QaAnswerText',
        'QaMetricStrip',
        'QaTickerMove',
        'QaPeriodChange',
        'QaConcentrationBar',
        'QaPnLBreakdown',
        'QaTopMovers',
        'QaClosedPositionList',
        'QaPositionList',
        'QaTipBanner',
        'QaComparisonRow',
      },
    );
  });

  test('every mode includes QaAnswerText (the text-only fallback)', () {
    for (final mode in AssistantMode.values) {
      expect(
        qaItemNames(mode),
        contains('QaAnswerText'),
        reason: '$mode must always be able to answer with plain text',
      );
    }
  });

  test('no widget is left unreachable by every mode combined', () {
    const allExpected = {
      'QaAnswerText',
      'QaMetricStrip',
      'QaTickerSnapshot',
      'QaTickerMove',
      'QaEarningsCalendar',
      'QaNewsSummary',
      'QaPeriodChange',
      'QaConcentrationBar',
      'QaPnLBreakdown',
      'QaTopMovers',
      'QaClosedPositionList',
      'QaPositionList',
      'QaTipBanner',
      'QaComparisonRow',
      'QaInvestOption',
      'QaBudgetSplit',
      'QaInvestConfirm',
      'QaGoalCard',
      'QaProjectionStrip',
      'QaProjectionChart',
      'QaMilestoneList',
    };

    final covered = AssistantMode.values
        .expand((mode) => qaItemNames(mode))
        .toSet();

    expect(covered, allExpected);
  });
}
