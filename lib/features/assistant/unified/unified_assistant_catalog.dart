import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog_widgets.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_prompt_rules.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

/// Grounding sin referencias a modos (la versión compartida,
/// `groundingPromptRules`, nombra "Learn mode" y la sigue usando el
/// pipeline por modos).
const String unifiedGroundingRules = '''
GROUNDING RULES — NEVER VIOLATE:
- Use ONLY numeric values present in ASSISTANT_SNAPSHOT for this turn.
- Never invent tickers, prices, percentages, dates, news, or market causes.
- If a field is missing or has_sufficient_history is false, say so plainly.
- Do not use training knowledge to fill financial figures.
- Conceptual explanations must not include specific live prices.
- For "why did X move" without news sources in the snapshot: numeric move
  only + disclaimer.
''';

/// Catálogo ÚNICO del pipeline sin modos: los widgets de Portfolio + Learn +
/// Explore (17, con `QaAnswerText`/`QaTipBanner` deduplicados,
/// `QaPositionsSnapshot` separado de `QaMetricStrip`, y `QaFundamentals`
/// sumado para valuación/rentabilidad/dividendo por ticker). Invest y Plan
/// quedan afuera — siguen con su propio catálogo.
abstract final class UnifiedAssistantCatalog {
  static const widgetNames = {
    'QaAnswerText',
    'QaTipBanner',
    'QaPriceChart',
    'QaTickerSnapshot',
    'QaTickerMove',
    'QaMetricStrip',
    'QaEarningsCalendar',
    'QaFundamentals',
    'QaNewsSummary',
    'QaPositionsSnapshot',
    'QaPeriodChange',
    'QaConcentrationBar',
    'QaPnLBreakdown',
    'QaTopMovers',
    'QaClosedPositionList',
    'QaPositionList',
    'QaComparisonRow',
  };

  static List<CatalogItem> get items => [
    qaAnswerTextItem,
    qaTipBannerItem,
    _priceChartItem,
    _tickerSnapshotItem,
    _tickerMoveItem,
    qaMetricStripComparisonItem,
    qaEarningsCalendarItem,
    qaFundamentalsItem,
    qaNewsSummaryItem,
    qaPositionsSnapshotItem,
    qaPeriodChangeItem,
    qaConcentrationBarItem,
    qaPnLBreakdownItem,
    qaTopMoversItem,
    qaClosedPositionListItem,
    qaPositionListItem,
    qaComparisonRowItem,
  ];

  static Catalog build() {
    final base = BasicCatalogItems.asCatalog();
    return base.copyWith(
      newItems: items,
      systemPromptFragments: [
        criticalOutputFormatRules,
        ...base.systemPromptFragments,
        unifiedGroundingRules,
        unifiedPromptRules,
      ],
    );
  }
}

// Variantes con descripción neutra (sin "modo explore"/"portfolio mode" ni
// claves `explore_tickers`) de los tres ítems compartidos cuya descripción
// las nombra. Mismo nombre de componente y mismo widget.

final CatalogItem _tickerSnapshotItem = CatalogItem(
  name: 'QaTickerSnapshot',
  dataSchema: S.object(
    description:
        'FALLBACK de QaPriceChart: precio y cambios día/semana/mes de un '
        'ticker SOLO cuando tickers.{TICKER}.price_chart_available es false '
        'y no se nombró un período.',
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
        'portfolio.position_periods; (2) FALLBACK de QaPriceChart cuando '
        'price_chart_available es false → desde tickers.{TICKER}.periods.',
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
        'cuando tickers.{TICKER}.price_chart_available es true (salvo ticker '
        'que el usuario TIENE + período explícito → QaTickerMove). La app '
        'trae la serie de precios sola; los campos de snapshot/período son '
        'el fallback que se muestra si no hay histórico.',
    properties: {
      'ticker': S.string(),
      'initialRange': S.string(
        description:
            'Período inicial del gráfico según la pregunta: "1D" (hoy), '
            '"1W" (semana), "1M" (mes — default si no nombró ninguno), '
            '"3M" (trimestre), "1Y" (año), "ALL" (todo el histórico).',
        enumValues: ['1D', '1W', '1M', '3M', '1Y', 'ALL'],
      ),
      'currentPrice': S.number(description: 'tickers.{T}.current_price.'),
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
