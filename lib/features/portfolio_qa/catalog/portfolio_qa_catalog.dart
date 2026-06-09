import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/genui_core/prompts/critical_output_rules.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';
import 'package:portfolio_assistant/features/portfolio_qa/catalog/portfolio_qa_catalog_widgets.dart';

const _trendEnum = ['up', 'down', 'neutral'];
const _toneEnum = ['info', 'warning'];

final _metricItemSchema = S.object(
  properties: {
    'label': S.string(),
    'value': S.string(),
    'trend': S.string(enumValues: _trendEnum),
  },
  required: ['label', 'value', 'trend'],
);

final _concentrationItemSchema = S.object(
  properties: {
    'ticker': S.string(),
    'weightPct': S.number(),
    'isHighlighted': S.boolean(),
  },
  required: ['ticker', 'weightPct'],
);

final _positionItemSchema = S.object(
  properties: {
    'ticker': S.string(),
    'weightPct': S.number(),
    'pnlPct': S.number(),
  },
  required: ['ticker', 'weightPct', 'pnlPct'],
);

final _moverSchema = S.object(
  properties: {
    'ticker': S.string(),
    'pnlPct': S.number(),
  },
  required: ['ticker', 'pnlPct'],
);

final CatalogItem qaAnswerTextItem = CatalogItem(
  name: 'QaAnswerText',
  dataSchema: S.object(
    description: 'Respuesta concisa en texto plano (máx. 2 oraciones).',
    properties: {
      'text': S.string(
        description: 'Respuesta directa, sin saludos ni cierres.',
      ),
    },
    required: ['text'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaAnswerText),
  exampleData: [
    () => '''
[
  {
    "id": "answer",
    "component": "QaAnswerText",
    "text": "Tu portfolio subió 5,4% hoy. AAPL y MSFT explican la mayor parte del movimiento."
  }
]
''',
  ],
);

final CatalogItem qaMetricStripItem = CatalogItem(
  name: 'QaMetricStrip',
  dataSchema: S.object(
    description: 'Fila de 2-3 métricas clave del portfolio.',
    properties: {
      'items': S.list(items: _metricItemSchema, minItems: 2, maxItems: 3),
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaMetricStrip),
  exampleData: [
    () => '''
[
  {
    "id": "metrics",
    "component": "QaMetricStrip",
    "items": [
      {"label": "Valor", "value": "\$24.350", "trend": "neutral"},
      {"label": "P&L", "value": "+\$1.240", "trend": "up"},
      {"label": "P&L %", "value": "+5,4%", "trend": "up"}
    ]
  }
]
''',
  ],
);

final CatalogItem qaConcentrationBarItem = CatalogItem(
  name: 'QaConcentrationBar',
  dataSchema: S.object(
    description: 'Barras de concentración por ticker (peso %).',
    properties: {
      'title': S.string(),
      'items': S.list(items: _concentrationItemSchema, minItems: 1, maxItems: 5),
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaConcentrationBar),
  exampleData: [
    () => '''
[
  {
    "id": "concentration",
    "component": "QaConcentrationBar",
    "title": "Concentración por activo",
    "items": [
      {"ticker": "NVDA", "weightPct": 38.2, "isHighlighted": true},
      {"ticker": "AAPL", "weightPct": 22.5, "isHighlighted": false},
      {"ticker": "MSFT", "weightPct": 18.1, "isHighlighted": false}
    ]
  }
]
''',
  ],
);

final CatalogItem qaPnLBreakdownItem = CatalogItem(
  name: 'QaPnLBreakdown',
  dataSchema: S.object(
    description: 'Desglose invertido → valor actual → resultado.',
    properties: {
      'costBasis': S.number(),
      'currentValue': S.number(),
      'gainLoss': S.number(),
      'gainLossPercent': S.number(),
    },
    required: ['costBasis', 'currentValue', 'gainLoss', 'gainLossPercent'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPnLBreakdown),
  exampleData: [
    () => '''
[
  {
    "id": "pnl",
    "component": "QaPnLBreakdown",
    "costBasis": 23110.50,
    "currentValue": 24350.80,
    "gainLoss": 1240.30,
    "gainLossPercent": 5.37
  }
]
''',
  ],
);

final CatalogItem qaTopMoversItem = CatalogItem(
  name: 'QaTopMovers',
  dataSchema: S.object(
    description: 'Mejor y peor posición por rendimiento %.',
    properties: {
      'best': _moverSchema,
      'worst': _moverSchema,
    },
    required: ['best', 'worst'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTopMovers),
  exampleData: [
    () => '''
[
  {
    "id": "movers",
    "component": "QaTopMovers",
    "best": {"ticker": "AAPL", "pnlPct": 8.1},
    "worst": {"ticker": "TSLA", "pnlPct": -3.2}
  }
]
''',
  ],
);

final CatalogItem qaPositionListItem = CatalogItem(
  name: 'QaPositionList',
  dataSchema: S.object(
    description: 'Lista compacta de posiciones con peso y P&L %.',
    properties: {
      'title': S.string(),
      'items': S.list(items: _positionItemSchema, minItems: 1, maxItems: 6),
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPositionList),
  exampleData: [
    () => '''
[
  {
    "id": "positions",
    "component": "QaPositionList",
    "title": "Tus posiciones",
    "items": [
      {"ticker": "AAPL", "weightPct": 23.0, "pnlPct": 8.1},
      {"ticker": "MSFT", "weightPct": 18.5, "pnlPct": 4.2}
    ]
  }
]
''',
  ],
);

final CatalogItem qaTipBannerItem = CatalogItem(
  name: 'QaTipBanner',
  dataSchema: S.object(
    description: 'Nota educativa breve (1 línea).',
    properties: {
      'message': S.string(),
      'tone': S.string(enumValues: _toneEnum),
    },
    required: ['message', 'tone'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTipBanner),
  exampleData: [
    () => '''
[
  {
    "id": "tip",
    "component": "QaTipBanner",
    "message": "Tener más del 35% en un solo activo aumenta el riesgo de concentración.",
    "tone": "info"
  }
]
''',
  ],
);

final CatalogItem qaComparisonRowItem = CatalogItem(
  name: 'QaComparisonRow',
  dataSchema: S.object(
    description: 'Comparación lado a lado de dos activos o métricas.',
    properties: {
      'label': S.string(),
      'leftTicker': S.string(),
      'leftValue': S.string(),
      'rightTicker': S.string(),
      'rightValue': S.string(),
      'metricLabel': S.string(),
    },
    required: [
      'label',
      'leftTicker',
      'leftValue',
      'rightTicker',
      'rightValue',
    ],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaComparisonRow),
  exampleData: [
    () => '''
[
  {
    "id": "compare",
    "component": "QaComparisonRow",
    "label": "Mayor concentración",
    "leftTicker": "NVDA",
    "leftValue": "38,2%",
    "rightTicker": "AAPL",
    "rightValue": "22,5%",
    "metricLabel": "Peso en el portfolio"
  }
]
''',
  ],
);

const _portfolioQaRules = '''
PORTFOLIO Q&A RULES — CONVERSATIONAL ASSISTANT:

ROLE
You are an educational portfolio assistant inside a Flutter app.
Use ONLY data from PORTFOLIO_SNAPSHOT in each user message.
Never invent tickers, prices, or P&L figures.

RESPONSE STYLE
- Be concise: QaAnswerText must be at most 2 short sentences (~80 words max).
- No greetings, no closings, no filler ("Espero que esto te ayude").
- Never repeat numbers that appear in a widget below.
- Do NOT use markdown. All text goes in QaAnswerText.text as plain text.
- Do NOT give concrete trading orders (buy/sell X tomorrow).
- Spanish, clear and friendly tone.

LAYOUT (mandatory structure)
Root must be a Column with children in this order:
1. QaAnswerText (always required)
2. At most ONE data widget (pick the best fit, or skip for pure concepts)
3. QaTipBanner (optional, only when an educational note adds value)

WIDGET SELECTION GUIDE
- Performance / "how is my portfolio": QaMetricStrip or QaPnLBreakdown
- Risk / concentration: QaConcentrationBar
- P&L meaning: QaPnLBreakdown
- Best/worst positions: QaTopMovers
- List all positions / overview: QaPositionList
- Compare two tickers: QaComparisonRow
- Pure conceptual questions (what is diversification): QaAnswerText only, no data widget

SURFACE ID
Use the exact SURFACE_ID from the user message in createSurface and updateComponents.
''';

/// Catálogo del asistente Portfolio Q&A (respuestas concisas + widgets simples).
abstract final class PortfolioQaCatalog {
  static Catalog build() {
    final base = BasicCatalogItems.asCatalog();
    return base.copyWith(
      newItems: [
        qaAnswerTextItem,
        qaMetricStripItem,
        qaConcentrationBarItem,
        qaPnLBreakdownItem,
        qaTopMoversItem,
        qaPositionListItem,
        qaTipBannerItem,
        qaComparisonRowItem,
      ],
      systemPromptFragments: [
        criticalOutputFormatRules,
        ...base.systemPromptFragments,
        _portfolioQaRules,
      ],
    );
  }
}
