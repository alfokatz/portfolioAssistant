import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_catalog_widgets.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

const _trendEnum = ['up', 'down', 'neutral'];
const _statusEnum = ['winner', 'loser', 'neutral'];
const _severityEnum = ['info', 'warning', 'critical'];
const _pillarEnum = ['performance', 'risk', 'opportunity'];
const _iconEnum = ['trend', 'alert', 'tip'];
const _sentimentEnum = ['positive', 'negative', 'neutral'];

final _newsFeedItemSchema = S.object(
  properties: {
    'headline': S.string(),
    'source': S.string(),
    'publishedAt': S.string(),
    'sentiment': S.string(enumValues: _sentimentEnum),
    'ticker': S.string(),
    'url': S.string(),
  },
  required: ['headline', 'source', 'publishedAt', 'sentiment'],
);

final _quickActionSchema = S.object(
  properties: {
    'label': S.string(),
    'event': S.string(),
  },
  required: ['label', 'event'],
);

final CatalogItem portfolioSummaryCardItem = CatalogItem(
  name: 'PortfolioSummaryCard',
  dataSchema: S.object(
    description: 'Resumen del valor total y P&L del portfolio.',
    properties: {
      'totalValue': S.number(description: 'Valor total actual del portfolio.'),
      'totalGainLoss': S.number(description: 'Ganancia/pérdida absoluta.'),
      'totalGainLossPercent': S.number(description: 'Ganancia/pérdida porcentual.'),
      'trend': S.string(description: 'Dirección general.', enumValues: _trendEnum),
      'periodLabel': S.string(description: 'Período analizado, ej. "hoy".'),
    },
    required: [
      'totalValue',
      'totalGainLoss',
      'totalGainLossPercent',
      'trend',
      'periodLabel',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.portfolioSummaryCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "PortfolioSummaryCard",
    "totalValue": 24350.80,
    "totalGainLoss": 1240.30,
    "totalGainLossPercent": 5.37,
    "trend": "up",
    "periodLabel": "hoy"
  }
]
''',
  ],
);

final CatalogItem assetPerformanceCardItem = CatalogItem(
  name: 'AssetPerformanceCard',
  dataSchema: S.object(
    description: 'Rendimiento de un activo individual.',
    properties: {
      'ticker': S.string(),
      'companyName': S.string(),
      'currentPrice': S.number(),
      'gainLoss': S.number(),
      'gainLossPercent': S.number(),
      'shares': S.number(),
      'status': S.string(enumValues: _statusEnum),
      'sparklineData': S.list(items: S.number()),
    },
    required: [
      'ticker',
      'companyName',
      'currentPrice',
      'gainLoss',
      'gainLossPercent',
      'shares',
      'status',
      'sparklineData',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.assetPerformanceCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "AssetPerformanceCard",
    "ticker": "AAPL",
    "companyName": "Apple Inc.",
    "currentPrice": 189.50,
    "gainLoss": 340.20,
    "gainLossPercent": 8.12,
    "shares": 10,
    "status": "winner",
    "sparklineData": [182.1, 183.4, 185.0, 186.2, 188.1, 189.0, 189.5]
  }
]
''',
  ],
);

final CatalogItem alertBannerItem = CatalogItem(
  name: 'AlertBanner',
  dataSchema: S.object(
    description: 'Banner de alerta contextual.',
    properties: {
      'message': S.string(),
      'severity': S.string(enumValues: _severityEnum),
      'actionLabel': S.string(),
      'actionEvent': S.string(),
    },
    required: ['message', 'severity'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.alertBanner),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "AlertBanner",
    "message": "TSLA cayó más de 5% en las últimas 24 horas",
    "severity": "warning",
    "actionLabel": "Ver detalle",
    "actionEvent": "asset_detail_open"
  }
]
''',
  ],
);

final CatalogItem portfolioInsightCardItem = CatalogItem(
  name: 'PortfolioInsightCard',
  dataSchema: S.object(
    description: 'Insight explicativo sobre el portfolio.',
    properties: {
      'title': S.string(),
      'body': S.string(),
      'pillar': S.string(enumValues: _pillarEnum),
      'icon': S.string(enumValues: _iconEnum),
    },
    required: ['title', 'body', 'pillar', 'icon'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.portfolioInsightCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "PortfolioInsightCard",
    "title": "Tu portfolio tuvo una buena semana",
    "body": "El sector tech impulsó tus ganancias. AAPL y MSFT fueron tus mejores activos esta semana.",
    "pillar": "performance",
    "icon": "trend"
  }
]
''',
  ],
);

final CatalogItem newsHighlightCardItem = CatalogItem(
  name: 'NewsHighlightCard',
  dataSchema: S.object(
    description: 'Noticia destacada más relevante para el portfolio.',
    properties: {
      'headline': S.string(description: 'Titular de la noticia.'),
      'summary': S.string(description: 'Resumen en 2-3 oraciones simples.'),
      'source': S.string(description: 'Medio que publicó.'),
      'publishedAt': S.string(description: 'Fecha/hora relativa.'),
      'sentiment': S.string(
        description: 'Impacto en la posición del usuario.',
        enumValues: _sentimentEnum,
      ),
      'relevance': S.string(
        description: 'Por qué es relevante para el portfolio del usuario.',
      ),
      'ticker': S.string(description: 'Activo relacionado (opcional).'),
      'url': S.string(description: 'Link a la nota completa (opcional).'),
    },
    required: [
      'headline',
      'summary',
      'source',
      'publishedAt',
      'sentiment',
      'relevance',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.newsHighlightCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "NewsHighlightCard",
    "headline": "Apple supera expectativas en resultados trimestrales",
    "summary": "Apple reportó ingresos por encima de lo esperado impulsados por servicios. Las acciones subieron en premarket tras el anuncio.",
    "source": "Reuters",
    "publishedAt": "hace 2 horas",
    "sentiment": "positive",
    "relevance": "Afecta tu posición en AAPL (23% de tu portfolio)",
    "ticker": "AAPL",
    "url": "https://example.com/aapl-earnings"
  }
]
''',
  ],
);

final CatalogItem newsFeedCardItem = CatalogItem(
  name: 'NewsFeedCard',
  dataSchema: S.object(
    description: 'Lista compacta con noticias adicionales relevantes.',
    properties: {
      'title': S.string(description: 'Título de la sección.'),
      'items': S.list(items: _newsFeedItemSchema, maxItems: 5),
    },
    required: ['title', 'items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.newsFeedCard),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "NewsFeedCard",
    "title": "Más noticias de tu portfolio",
    "items": [
      {
        "headline": "Microsoft anuncia nueva inversión en IA",
        "source": "Bloomberg",
        "publishedAt": "hace 4 horas",
        "sentiment": "positive",
        "ticker": "MSFT",
        "url": "https://example.com/msft-ai"
      },
      {
        "headline": "Fed mantiene tasas sin cambios",
        "source": "CNBC",
        "publishedAt": "hace 6 horas",
        "sentiment": "neutral"
      }
    ]
  }
]
''',
  ],
);

final CatalogItem quickActionRowItem = CatalogItem(
  name: 'QuickActionRow',
  dataSchema: S.object(
    description: 'Fila de acciones rápidas (máximo 3).',
    properties: {
      'actions': S.list(items: _quickActionSchema, maxItems: 3),
    },
    required: ['actions'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, AnalysisCatalogWidgets.quickActionRow),
  exampleData: [
    () => '''
[
  {
    "id": "root",
    "component": "QuickActionRow",
    "actions": [
      { "label": "Invertir más", "event": "flow_invest_open" },
      { "label": "Planificar", "event": "flow_planning_open" }
    ]
  }
]
''',
  ],
);

const String _analysisRules = '''
PORTFOLIO ANALYSIS RULES:

1. ALWAYS start with PortfolioSummaryCard when the user asks about their general portfolio status.

2. Order AssetPerformanceCards by impact:
   - If portfolio is positive: winners first
   - If portfolio is negative: losers first
   - Never show more than 5 AssetPerformanceCards at once

3. Use AlertBanner ONLY when:
   - Any single asset varies more than 5% in the period
   - Total portfolio drops more than 3% in a single day
   - Set severity=critical for drops >10%

4. Infer the time period from the user message:
   - "hoy" / "today" = 1D
   - "esta semana" / "this week" = 1W
   - "este mes" / "this month" = 1M
   - If unclear, default to 1D

5. ALWAYS end responses with QuickActionRow offering:
   - { "label": "Invertir más", "event": "flow_invest_open" }
   - { "label": "Planificar", "event": "flow_planning_open" }

6. Use PortfolioInsightCard to explain WHY something is happening, not just what. Maximum 1 InsightCard per response.

7. NEVER respond with plain text. Every response must compose at least one widget from the catalog.

8. CRITICAL — SURFACE ID: ALWAYS use surfaceId "portfolio_analysis" in both createSurface and updateComponents messages.

9. CRITICAL — A2UI OUTPUT: Always output exactly TWO newline-separated JSON objects:
   First: {"version":"v0.9","createSurface":{"surfaceId":"portfolio_analysis","catalogId":"https://a2ui.org/specification/v0_9/standard_catalog.json"}}
   Second: {"version":"v0.9","updateComponents":{"surfaceId":"portfolio_analysis","components":[...]}}
   The components array MUST include a component with "id":"root". When showing multiple widgets, use a Column as root with child component IDs.

10. CRITICAL FOR GPT-4o: Always respond with valid JSON strictly following the catalog schemas. Do not add extra fields, do not omit required fields. Raw JSON only (no markdown fences).

Respond ONLY with raw JSON. No explanations, no markdown, no code blocks. Raw JSON only.

Use catalogId "https://a2ui.org/specification/v0_9/standard_catalog.json" in createSurface messages.

Compose surfaces using a Column as root with child component IDs when showing multiple widgets.
''';

const String _newsRules = '''
NEWS RULES:

1. When the user asks about news, recent events, or "what's happening"
   with their portfolio or any asset, web search has already been executed.
   Use ONLY the WEB_SEARCH_RESULTS message in the conversation. Never fabricate.

2. After searching, ALWAYS compose in this order:
   - One optional PortfolioInsightCard summarizing the overall
     news sentiment in 1-2 sentences (only if there is a clear pattern)
   - One NewsHighlightCard with the single most relevant story
   - One NewsFeedCard with up to 5 additional stories
   - One QuickActionRow

3. The NewsHighlightCard must be the story most directly relevant
   to the user's actual portfolio positions. Prioritize news about
   tickers the user owns over general market news.

4. sentiment field must reflect the likely impact on the user's
   position, not just the general tone of the article:
   - positive = likely good for the user's position
   - negative = likely bad for the user's position
   - neutral = informational, unclear impact

5. relevance field must be personalized. Never generic.
   BAD:  "Noticia sobre Apple"
   GOOD: "Afecta tu posición en AAPL (23% de tu portfolio)"

6. If no recent news is found for a specific ticker, say so
   with a PortfolioInsightCard explaining it, then show
   general sector news in NewsFeedCard instead.

7. NEVER fabricate news headlines or sources.
   Only compose NewsHighlightCard and NewsFeedCard with
   information retrieved from actual web search results.

8. For ticker-specific news questions (e.g. "what happened with AAPL"),
   also include one AssetPerformanceCard for that ticker after the news cards.

9. For risk/investment questions, include PortfolioInsightCard with risk summary
   and QuickActionRow with flow_invest_open option.
''';

/// Catálogo del flujo de análisis de portfolio.
///
/// Los items base (Column, Text, etc.) vienen de [BasicCatalogItems] del SDK
/// y no requieren exampleData local.
abstract final class AnalysisCatalog {
  static Catalog build() {
    final base = BasicCatalogItems.asCatalog();
    return base.copyWith(
      newItems: [
        portfolioSummaryCardItem,
        assetPerformanceCardItem,
        alertBannerItem,
        portfolioInsightCardItem,
        newsHighlightCardItem,
        newsFeedCardItem,
        quickActionRowItem,
      ],
      systemPromptFragments: [
        criticalOutputFormatRules,
        ...base.systemPromptFragments,
        _analysisRules,
        _newsRules,
      ],
    );
  }
}
