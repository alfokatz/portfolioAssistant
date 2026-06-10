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

final _closedPositionItemSchema = S.object(
  properties: {
    'ticker': S.string(),
    'pnlPct': S.number(),
    'pnlAbs': S.number(),
    'closeDateLabel': S.string(),
  },
  required: ['ticker', 'pnlPct', 'pnlAbs'],
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

final CatalogItem qaTickerMoveItem = CatalogItem(
  name: 'QaTickerMove',
  dataSchema: S.object(
    description:
        'Movimiento de precio de un ticker en un período (desde position_periods).',
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
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTickerMove),
  exampleData: [
    () => '''
[
  {
    "id": "ticker_move",
    "component": "QaTickerMove",
    "ticker": "AAPL",
    "periodLabel": "Últimos 7 días",
    "changePct": -4.2,
    "priceStart": 198.50,
    "priceEnd": 190.16,
    "weightPct": 22.5
  }
]
''',
  ],
);

final CatalogItem qaPeriodChangeItem = CatalogItem(
  name: 'QaPeriodChange',
  dataSchema: S.object(
    description:
        'Cambio del portfolio en un período temporal (semana, mes, etc.).',
    properties: {
      'periodLabel': S.string(
        description: 'Etiqueta del período, ej. "Últimos 7 días".',
      ),
      'changeAbs': S.number(description: 'Cambio absoluto en el período.'),
      'changePct': S.number(description: 'Cambio porcentual en el período.'),
      'valueStart': S.number(description: 'Valor del portfolio al inicio.'),
      'valueEnd': S.number(description: 'Valor del portfolio al cierre.'),
    },
    required: ['periodLabel', 'changeAbs', 'changePct'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPeriodChange),
  exampleData: [
    () => '''
[
  {
    "id": "period",
    "component": "QaPeriodChange",
    "periodLabel": "Últimos 7 días",
    "changeAbs": 320.50,
    "changePct": 1.33,
    "valueStart": 24030.30,
    "valueEnd": 24350.80
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

final CatalogItem qaClosedPositionListItem = CatalogItem(
  name: 'QaClosedPositionList',
  dataSchema: S.object(
    description: 'Lista compacta de posiciones cerradas con P&L realizado.',
    properties: {
      'title': S.string(),
      'items': S.list(
        items: _closedPositionItemSchema,
        minItems: 1,
        maxItems: 6,
      ),
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) => guardedCatalogWidget(
    ctx,
    PortfolioQaCatalogWidgets.qaClosedPositionList,
  ),
  exampleData: [
    () => '''
[
  {
    "id": "closed_positions",
    "component": "QaClosedPositionList",
    "title": "Posiciones cerradas",
    "items": [
      {"ticker": "AAPL", "pnlPct": 12.5, "pnlAbs": 240, "closeDateLabel": "3 jun 2026"},
      {"ticker": "TSLA", "pnlPct": -4.1, "pnlAbs": -85, "closeDateLabel": "15 may 2026"}
    ]
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

TEMPORAL QUESTIONS (CRITICAL)
The snapshot has two different P&L concepts — never confuse them:
- total_pnl_abs / total_pnl_pct = ALL-TIME since purchase (pnl_scope field)
- period_returns.{day|week|month|quarter|year} = change WITHIN that time window

When the user asks about a time period, use ONLY period_returns:
- "hoy", "último día" → period_returns.day
- "esta semana", "últimos 7 días", "semanal" → period_returns.week
- "este mes", "último mes", "mensual" → period_returns.month
- "trimestre", "últimos 3 meses" → period_returns.quarter
- "este año", "anual" → period_returns.year

For temporal questions, use QaPeriodChange with data from the matching
period_returns entry (periodLabel = label_es, changeAbs = pnl_abs,
changePct = pnl_pct, valueStart/End from the same entry).

NEVER use total_pnl_abs or QaPnLBreakdown for "esta semana" or similar.
If has_sufficient_history is false for the requested period, say so in
QaAnswerText and omit the data widget.

TICKER-SPECIFIC QUESTIONS (CRITICAL)
The snapshot has position_periods.{TICKER}.{day|week|month|quarter|year}
with price_start, price_end, change_pct, has_sufficient_history.
Use ONLY these values for a specific ticker — never invent prices or moves.

When the user asks about ONE ticker in a time window:
- "¿cómo fue AAPL esta semana?" → position_periods.AAPL.week + QaTickerMove
- Map period keys the same way as period_returns (day/week/month/quarter/year)
- QaTickerMove: ticker, periodLabel=label_es, changePct=change_pct,
  priceStart=price_start, priceEnd=price_end, weightPct from positions[]

WHY / CAUSATION QUESTIONS (CRITICAL — NO HALLUCINATION)
If the user asks WHY a ticker or the portfolio moved ("¿por qué cayó X?",
"¿qué pasó con NVDA?", "motivo de la caída"):
- You have NO verified news or event data in the snapshot.
- NEVER invent causes, news, earnings, macro events, or "probablemente…".
- State only the numeric move from position_periods or period_returns.
- Use QaTickerMove (single ticker) or QaPeriodChange (whole portfolio).
- QaAnswerText: describe the move factually in 1 sentence, e.g.
  "AAPL bajó 4,2% en los últimos 7 días según el precio de mercado."
- Add QaTipBanner (tone=info) explaining that causes require external
  news sources not available in this chat yet.

CLOSED POSITIONS (CRITICAL)
The snapshot may include closed_positions[] with REALIZED P&L per trade
(pnl_abs, pnl_pct, cost_basis, proceeds, close_date).
- closed_pnl_total_abs / closed_pnl_total_pct = aggregate realized P&L
- has_closed_positions=true when the user has closed trades
- NEVER mix closed realized P&L with open unrealized total_pnl_*
- If has_positions is false but has_closed_positions is true, the user has
  NO open positions — do not use positions[], period_returns, or QaMetricStrip
  for current portfolio value.

For closed-position questions:
- "cuánto gané en total cerrado": QaPnLBreakdown with costBasis =
  closed_pnl_total_cost_basis, currentValue = cost_basis + closed_pnl_total_abs,
  gainLoss = closed_pnl_total_abs, gainLossPercent = closed_pnl_total_pct
- "mejor/peor operación cerrada": QaTopMovers from closed_positions by pnl_pct
- "listar posiciones cerradas": QaClosedPositionList (max 6 items, most recent)
- Compare two closed tickers: QaComparisonRow using pnl_pct or pnl_abs

WIDGET SELECTION GUIDE
- Single ticker in a period (open): QaTickerMove (from position_periods)
- Temporal performance of whole portfolio (open): QaPeriodChange
- Current snapshot / open positions: QaMetricStrip
- All-time open P&L meaning: QaPnLBreakdown from total_cost_basis / total_value
- Realized P&L from closed trades: QaPnLBreakdown from closed totals
- Risk / concentration (open): QaConcentrationBar
- Best/worst open positions: QaTopMovers from positions[]
- Best/worst closed trades: QaTopMovers from closed_positions[]
- List open positions: QaPositionList
- List closed positions: QaClosedPositionList
- Compare two tickers: QaComparisonRow
- Pure conceptual questions (what is diversification): QaAnswerText only

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
        qaPeriodChangeItem,
        qaTickerMoveItem,
        qaConcentrationBarItem,
        qaPnLBreakdownItem,
        qaTopMoversItem,
        qaPositionListItem,
        qaClosedPositionListItem,
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
