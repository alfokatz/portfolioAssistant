import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/assistant/areas/area_specs.dart';
import 'package:portfolio_assistant/features/assistant/areas/porty_areas.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog_widgets.dart';
import 'package:portfolio_assistant/features/assistant/prompts/assistant_prompt_rules.dart';
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
  /// Para mostrar las respuestas se usa siempre el completo.
  static Catalog build({PromptVariant variant = PromptVariant.classic}) {
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
          ],
          systemPromptFragments: [
            criticalOutputFormatRules,
            ...base.systemPromptFragments,
            lean
                ? AreaSpecs.leanRules(assistantPromptRules)
                : assistantPromptRules,
          ],
        );
  }
}

// Descripciones apuntando a los resultados de las tools (no a un snapshot).

final CatalogItem _tickerSnapshotItem = CatalogItem(
  name: 'QaTickerSnapshot',
  dataSchema: S.object(
    description:
        'FALLBACK de QaPriceChart: precio y cambios día/semana/mes de un '
        'ticker SOLO cuando get_quote.price_chart_available es false y no se '
        'nombró un período.',
    properties: {
      'ticker': S.string(),
      'currentPrice': S.number(description: 'Precio actual del ticker.'),
      'dayChangePct': S.number(
        description: 'Cambio porcentual del último día.',
      ),
      'weekChangePct': S.number(
        description: 'Cambio porcentual de los últimos 7 días.',
      ),
      'monthChangePct': S.number(
        description: 'Cambio porcentual de los últimos 30 días.',
      ),
      'weightPct': S.number(
        description: 'Peso del ticker en el portfolio (opcional).',
      ),
    },
    required: ['ticker', 'currentPrice'],
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
        'usos: (1) ticker que el usuario TIENE + período → desde '
        'get_portfolio_details.position_periods; (2) FALLBACK de QaPriceChart '
        'cuando price_chart_available es false → desde get_quote periods.',
    properties: {
      'ticker': S.string(),
      'periodLabel': S.string(
        description: 'Etiqueta del período, ej. "Últimos 7 días".',
      ),
      'changePct': S.number(description: 'Cambio porcentual del precio.'),
      'priceStart': S.number(description: 'Precio al inicio del período.'),
      'priceEnd': S.number(description: 'Precio al cierre del período.'),
      'weightPct': S.number(
        description: 'Peso del ticker en el portfolio (opcional).',
      ),
    },
    required: ['ticker', 'periodLabel', 'changePct'],
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
        'serie de precios sola; los campos de período son el fallback que se '
        'muestra si no hay histórico.',
    properties: {
      'ticker': S.string(),
      'initialRange': S.string(
        description:
            'Período inicial del gráfico según la pregunta: "1D" (hoy), '
            '"1W" (semana), "1M" (mes — default si no nombró ninguno), '
            '"3M" (trimestre), "1Y" (año), "ALL" (todo el histórico).',
        enumValues: ['1D', '1W', '1M', '3M', '1Y', 'ALL'],
      ),
      'currentPrice': S.number(description: 'get_quote current_price.'),
      'dayChangePct': S.number(description: 'periods.day.change_pct.'),
      'weekChangePct': S.number(description: 'periods.week.change_pct.'),
      'monthChangePct': S.number(description: 'periods.month.change_pct.'),
      'periodLabel': S.string(
        description:
            'Solo si el usuario nombró un período: periods.{period}.label_es.',
      ),
      'changePct': S.number(
        description: 'Solo si nombró un período: periods.{period}.change_pct.',
      ),
      'priceStart': S.number(
        description: 'Solo si nombró un período: periods.{period}.price_start.',
      ),
      'priceEnd': S.number(
        description: 'Solo si nombró un período: periods.{period}.price_end.',
      ),
      'weightPct': S.number(
        description: 'Peso del ticker en el portfolio (opcional).',
      ),
    },
    required: ['ticker', 'initialRange', 'currentPrice'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPriceChart),
  exampleData: qaPriceChartItem.exampleData,
);
