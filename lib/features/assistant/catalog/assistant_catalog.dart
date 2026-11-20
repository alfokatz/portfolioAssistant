import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/areas/porty_areas.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog_widgets.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/broker_link_widgets.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
import 'package:portfolio_assistant/features/assistant/utils/period_labels.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

/// El catálogo ÚNICO del asistente: todos los widgets de Porty, más solo
/// los dos componentes básicos de genui que la app usa (Column como raíz,
/// Text como fallback del normalizer). El resto de los básicos (Button,
/// TextField, Video…) no se usan y ocupaban ~7K tokens del schema que va
/// en cada request.
abstract final class AssistantCatalog {
  static const widgetNames = {
    'QaAnswerText',
    'QaTipBanner',
    'QaPriceChart',
    'QaCompareChart',
    'QaTickerSnapshot',
    'QaTickerMove',
    'QaMetricStrip',
    'QaEarningsCalendar',
    'QaFundamentals',
    'QaCompanyAnalysis',
    'QaEtfHoldings',
    'QaAllocationPlan',
    'QaWatchlist',
    'QaWeeklyReport',
    'QaInfoList',
    'QaGoldTeaser',
    'QaNewsSummary',
    'QaPositionsSnapshot',
    'QaPeriodChange',
    'QaConcentrationBar',
    'QaPnLBreakdown',
    'QaTopMovers',
    'QaClosedPositionList',
    'QaPositionList',
    'QaComparisonRow',
    'QaBudgetSplit',
    'QaInvestOption',
    'QaInvestConfirm',
    'QaSavingsPlan',
    'QaBuyPlan',
    'QaGoalStatus',
    'QaActionProposal',
  };

  static const basicComponentNames = {'Column', 'Text'};

  /// Widgets que solo agrega la app después del turno: se registran para
  /// MOSTRARLOS ([build] con `forDisplay`), pero no van en el prompt (el
  /// modelo no los conoce, así que el hash del prompt no cambia).
  static const appOnlyWidgetNames = {'QaBrokerLink'};

  static List<CatalogItem> get _appOnlyItems => [qaBrokerLinkItem];

  static List<CatalogItem> get items => [
    qaAnswerTextItem,
    qaTipBannerItem,
    _priceChartItem,
    qaCompareChartItem,
    _tickerSnapshotItem,
    _tickerMoveItem,
    qaMetricStripComparisonItem,
    qaEarningsCalendarItem,
    qaFundamentalsItem,
    qaCompanyAnalysisItem,
    qaEtfHoldingsItem,
    qaAllocationPlanItem,
    qaWatchlistItem,
    qaWeeklyReportItem,
    qaInfoListItem,
    qaGoldTeaserItem,
    qaNewsSummaryItem,
    qaPositionsSnapshotItem,
    qaPeriodChangeItem,
    qaConcentrationBarItem,
    qaPnLBreakdownItem,
    qaTopMoversItem,
    qaClosedPositionListItem,
    qaPositionListItem,
    qaComparisonRowItem,
    qaBudgetSplitItem,
    qaInvestOptionItem,
    qaInvestConfirmItem,
    qaSavingsPlanItem,
    qaGoalStatusItem,
    qaBuyPlanItem,
    qaActionProposalItem,
  ];

  /// [variant] lean: el catálogo para ARMAR EL PROMPT, sin los widgets que
  /// viajan con el resultado de su tool (`area_spec`) y con las reglas lean.
  /// Para mostrar las respuestas se usa siempre el completo, con
  /// [forDisplay] (suma los [appOnlyWidgetNames]).
  static Catalog build({
    PromptVariant variant = PromptVariant.classic,
    bool forDisplay = false,
  }) {
    final base = BasicCatalogItems.asCatalog();
    final unused = [
      for (final item in base.items)
        if (!basicComponentNames.contains(item.name)) item,
    ];
    final lean = variant == PromptVariant.lean;
    final deferred = lean ? PortyAreas.deferredWidgets : const <String>{};
    return base
        .copyWithout(itemsToRemove: unused)
        .copyWith(
          newItems: [
            for (final item in items)
              if (!deferred.contains(item.name)) item,
            if (forDisplay) ..._appOnlyItems,
          ],
          systemPromptFragments: [
            criticalOutputFormatRules,
            // La surface la crea la app: las reglas de genui sin
            // `createSurface` (ver [updateOnlyCatalogRules]).
            for (final fragment in base.systemPromptFragments)
              fragment == BasicCatalogItems.basicCatalogRules
                  ? updateOnlyCatalogRules
                  : fragment,
            lean
                ? AreaSpecs.leanRules(assistantPromptRules)
                : assistantPromptRules,
          ],
        );
  }
}

// Descripciones apuntando a los resultados de las tools (no a un snapshot).

/// La ventana que nombró el usuario, como clave de `periods` (get_quote) o
/// `position_periods.{T}` (get_portfolio_details). Los números de ese
/// período los pone la app desde la tool (ver `TickerPriceData`).
Schema _periodKey(String description) => S.string(
  description: description,
  enumValues: PeriodLabels.durations.keys.toList(),
);

final CatalogItem _tickerSnapshotItem = CatalogItem(
  name: 'QaTickerSnapshot',
  dataSchema: S.object(
    description:
        'FALLBACK de QaPriceChart: precio y cambios día/semana/mes de un '
        'ticker SOLO cuando get_quote.price_chart_available es false y no se '
        'nombró un período. Solo el ticker: la app pone precio, cambios y '
        'peso desde get_quote.',
    properties: {'ticker': S.string()},
    required: ['ticker'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTickerSnapshot),
  exampleData: qaTickerSnapshotItem.exampleData,
);

final CatalogItem _tickerMoveItem = CatalogItem(
  name: 'QaTickerMove',
  dataSchema: S.object(
    description:
        'Movimiento de precio de UN ticker en un período explícito. Dos '
        'usos: (1) ticker que el usuario TIENE + período → con '
        'get_portfolio_details.position_periods; (2) FALLBACK de QaPriceChart '
        'cuando price_chart_available es false → con get_quote. La app pone '
        'los números de ese período desde la tool.',
    properties: {
      'ticker': S.string(),
      'period': _periodKey('La ventana que nombró el usuario.'),
      'weightPct': S.number(
        description:
            'Solo si es un ticker propio y no llamaste get_quote: '
            'PORTFOLIO_BRIEF positions[].weight_pct.',
      ),
    },
    required: ['ticker', 'period'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTickerMove),
  exampleData: qaTickerMoveItem.exampleData,
);

final CatalogItem _priceChartItem = CatalogItem(
  name: 'QaPriceChart',
  dataSchema: S.object(
    description:
        'Gráfico de precio histórico de UN ticker, con selector de período '
        '1D/1W/1M/3M/1Y/Todo que el usuario cambia sin volver a preguntar. '
        'DEFAULT para cualquier pregunta de precio o evolución de un ticker '
        'cuando get_quote.price_chart_available es true. La app trae la '
        'serie de precios y pone precio, cambios y peso desde get_quote.',
    properties: {
      'ticker': S.string(),
      'initialRange': S.string(
        description:
            'Período inicial del gráfico según la pregunta: "1D" (hoy), '
            '"1W" (semana), "1M" (mes — default si no nombró ninguno), '
            '"3M" (trimestre), "1Y" (año), "ALL" (todo el histórico).',
        enumValues: ['1D', '1W', '1M', '3M', '1Y', 'ALL'],
      ),
      'period': _periodKey(
        'Solo si el usuario nombró una ventana (no con "ALL").',
      ),
    },
    required: ['ticker', 'initialRange'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPriceChart),
  exampleData: qaPriceChartItem.exampleData,
);
