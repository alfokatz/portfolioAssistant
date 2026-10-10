import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/analysis_widgets.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog_widgets.dart';

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
    'marketValue': S.number(description: 'positions[].market_value'),
  },
  required: ['ticker', 'weightPct', 'pnlPct'],
);

final _allocationItemSchema = S.object(
  properties: {
    'ticker': S.string(),
    'weightPct': S.number(description: 'positions[].weight_pct'),
  },
  required: ['ticker', 'weightPct'],
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
    'pnlPct': S.number(
      description:
          'Rendimiento TOTAL desde la compra (P&L %). Usar este campo O '
          'changePct, nunca ambos.',
    ),
    'changePct': S.number(
      description:
          'Variación de precio DENTRO de una ventana (ej. esta semana), no '
          'P&L total. Requiere periodLabel en QaTopMovers.',
    ),
  },
  required: ['ticker'],
);

final _budgetSplitItemSchema = S.object(
  properties: {'ticker': S.string(), 'amount': S.number(), 'pct': S.number()},
  required: ['ticker', 'amount', 'pct'],
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
  widgetBuilder:
      (ctx) =>
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
    description:
        'Fila de 2-3 métricas clave, lado a lado: portfolio mode para '
        'valor/P&L/P&L%, explore mode para comparar 2-3 tickers a la vez '
        '(un item por ticker).',
    properties: {
      'items': S.list(items: _metricItemSchema, minItems: 2, maxItems: 3),
    },
    required: ['items'],
  ),
  widgetBuilder:
      (ctx) =>
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

final CatalogItem qaTickerSnapshotItem = CatalogItem(
  name: 'QaTickerSnapshot',
  dataSchema: S.object(
    description:
        'Snapshot de precio y cambios día/semana/mes de un ticker (modo explore).',
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
  exampleData: [
    () => '''
[
  {
    "id": "ticker_snapshot",
    "component": "QaTickerSnapshot",
    "ticker": "NVDA",
    "currentPrice": 120.50,
    "dayChangePct": 1.2,
    "weekChangePct": -2.1,
    "monthChangePct": 5.8,
    "weightPct": 0
  }
]
''',
  ],
);

final CatalogItem qaTickerMoveItem = CatalogItem(
  name: 'QaTickerMove',
  dataSchema: S.object(
    description:
        'Movimiento de precio de un ticker en un período con fecha/hora '
        'explícita (día/semana/mes/trimestre/año): portfolio mode desde '
        'position_periods, explore mode desde explore_tickers.{TICKER}'
        '.periods. Preferilo sobre QaTickerSnapshot cuando el usuario '
        'nombra un período explícito.',
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

final CatalogItem qaPriceChartItem = CatalogItem(
  name: 'QaPriceChart',
  dataSchema: S.object(
    description:
        'Gráfico de precio histórico de UN ticker (modo explore), con '
        'selector de período 1D/1W/1M/3M/1Y/Todo que el usuario cambia sin '
        'volver a preguntar. DEFAULT para cualquier pregunta de precio o '
        'evolución de un ticker cuando explore_tickers.{TICKER}'
        '.price_chart_available es true. La app trae la serie de precios '
        'sola; los campos de snapshot/período son el fallback que se '
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
      'currentPrice': S.number(
        description: 'explore_tickers.{T}.current_price.',
      ),
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
  exampleData: [
    () => '''
[
  {
    "id": "price_chart",
    "component": "QaPriceChart",
    "ticker": "NVDA",
    "initialRange": "1W",
    "currentPrice": 120.50,
    "dayChangePct": 1.2,
    "weekChangePct": -2.1,
    "monthChangePct": 5.8,
    "periodLabel": "últimos 7 días",
    "changePct": -2.1,
    "priceStart": 123.09,
    "priceEnd": 120.50
  }
]
''',
  ],
);

/// Solo en el catálogo unificado: rendimiento comparado de 2-3 tickers.
/// La app trae las series sola; `items` es el fallback sin histórico.
final CatalogItem qaCompareChartItem = CatalogItem(
  name: 'QaCompareChart',
  dataSchema: S.object(
    description:
        'Rendimiento de precio comparado de 2-3 tickers (una línea por '
        'ticker, % desde el inicio). La app trae las series.',
    properties: {
      'tickers': S.list(items: S.string(), minItems: 2, maxItems: 3),
      'initialRange': S.string(enumValues: ['1W', '1M', '3M', '1Y']),
      'items': S.list(
        description: 'Fallback: periods.{period}.change_pct por ticker.',
        items: S.object(
          properties: {'ticker': S.string(), 'changePct': S.number()},
          required: ['ticker', 'changePct'],
        ),
        maxItems: 3,
      ),
    },
    required: ['tickers', 'initialRange'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaCompareChart),
  exampleData: [
    () => '''
[
  {
    "id": "compare_chart",
    "component": "QaCompareChart",
    "tickers": ["AAPL", "MSFT"],
    "initialRange": "1M",
    "items": [
      {"ticker": "AAPL", "changePct": -1.96},
      {"ticker": "MSFT", "changePct": 1.39}
    ]
  }
]
''',
  ],
);

/// Solo en el catálogo unificado (ver `UnifiedAssistantCatalog`): la foto
/// de las posiciones abiertas que en modo Portfolio hacía `QaMetricStrip`.
final CatalogItem qaPositionsSnapshotItem = CatalogItem(
  name: 'QaPositionsSnapshot',
  dataSchema: S.object(
    description:
        'Foto actual de TUS posiciones abiertas: valor total, P&L y P&L% '
        'desde la compra (portfolio.total_value, total_pnl_abs, '
        'total_pnl_pct). Nunca para comparar tickers.',
    properties: {
      'totalValue': S.number(description: 'portfolio.total_value'),
      'pnlAbs': S.number(description: 'portfolio.total_pnl_abs'),
      'pnlPct': S.number(description: 'portfolio.total_pnl_pct'),
      'positionsCount': S.integer(
        description: 'Cantidad de posiciones abiertas (portfolio.positions).',
      ),
      'positions': S.list(
        description: 'Reparto por peso, de PORTFOLIO_BRIEF positions[].',
        items: _allocationItemSchema,
        maxItems: 10,
      ),
    },
    required: ['totalValue', 'pnlAbs', 'pnlPct'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(
        ctx,
        PortfolioQaCatalogWidgets.qaPositionsSnapshot,
      ),
  exampleData: [
    () => '''
[
  {
    "id": "positions_snapshot",
    "component": "QaPositionsSnapshot",
    "totalValue": 12450.3,
    "pnlAbs": 1830.5,
    "pnlPct": 17.2,
    "positionsCount": 6,
    "positions": [
      {"ticker": "NVDA", "weightPct": 38.2},
      {"ticker": "AAPL", "weightPct": 22.5},
      {"ticker": "MSFT", "weightPct": 18.1},
      {"ticker": "VOO", "weightPct": 11.4},
      {"ticker": "KO", "weightPct": 6.3},
      {"ticker": "TSLA", "weightPct": 3.5}
    ]
  }
]
''',
  ],
);

/// Solo en el catálogo unificado: mismo widget `QaMetricStrip`, con la
/// descripción reducida a su único significado ahí — comparar 2-3 tickers.
/// (El ítem compartido `qaMetricStripItem` mantiene la descripción de dos
/// significados que usa el pipeline por modos, que sigue intacto.)
final CatalogItem qaMetricStripComparisonItem = CatalogItem(
  name: 'QaMetricStrip',
  dataSchema: S.object(
    description:
        'Compara 2-3 tickers lado a lado, un item por ticker (variación de '
        'precio en la ventana pedida). NUNCA para la foto de tus posiciones '
        '(eso es QaPositionsSnapshot).',
    properties: {
      'items': S.list(items: _metricItemSchema, minItems: 2, maxItems: 3),
      'periodLabel': S.string(description: 'periods.{period}.label_es'),
    },
    required: ['items'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaMetricStrip),
  exampleData: [
    () => '''
[
  {
    "id": "compare",
    "component": "QaMetricStrip",
    "periodLabel": "último día",
    "items": [
      {"label": "NVDA", "value": "+3,4%", "trend": "up"},
      {"label": "AMD", "value": "-1,2%", "trend": "down"}
    ]
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
  widgetBuilder:
      (ctx) =>
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
    description:
        'Concentración por ticker (peso %), mayor primero. isHighlighted '
        'resalta las que importan para la respuesta.',
    properties: {
      'title': S.string(),
      'items': S.list(
        items: _concentrationItemSchema,
        minItems: 1,
        maxItems: 5,
      ),
    },
    required: ['items'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(
        ctx,
        PortfolioQaCatalogWidgets.qaConcentrationBar,
      ),
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
      'title': S.string(
        description: 'Opcional, ej. "Desde la compra" o "Resultado realizado".',
      ),
      'costBasis': S.number(),
      'currentValue': S.number(),
      'gainLoss': S.number(),
      'gainLossPercent': S.number(),
    },
    required: ['costBasis', 'currentValue', 'gainLoss', 'gainLossPercent'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPnLBreakdown),
  exampleData: [
    () => '''
[
  {
    "id": "pnl",
    "component": "QaPnLBreakdown",
    "title": "Desde la compra",
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
    description:
        'Mejor y peor posición: por rendimiento total (pnlPct) o por '
        'variación dentro de una ventana (changePct + periodLabel).',
    properties: {
      'best': _moverSchema,
      'worst': _moverSchema,
      'periodLabel': S.string(
        description:
            'Solo con changePct: la ventana, ej. "últimos 7 días" '
            '(position_periods.{T}.{period}.label_es).',
      ),
    },
    required: ['best', 'worst'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTopMovers),
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
    () => '''
[
  {
    "id": "movers_week",
    "component": "QaTopMovers",
    "periodLabel": "últimos 7 días",
    "best": {"ticker": "NVDA", "changePct": 4.3},
    "worst": {"ticker": "MSFT", "changePct": -1.8}
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
      'items': S.list(items: _closedPositionItemSchema, maxItems: 6),
      'totalPnlAbs': S.number(description: 'closed_pnl_total_abs'),
      'totalPnlPct': S.number(description: 'closed_pnl_total_pct'),
    },
    required: ['items'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(
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
    "totalPnlAbs": 155,
    "totalPnlPct": 5.8,
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
    description: 'Lista de posiciones con peso y P&L %, mayor peso primero.',
    properties: {
      'title': S.string(),
      'items': S.list(items: _positionItemSchema, minItems: 1, maxItems: 12),
    },
    required: ['items'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPositionList),
  exampleData: [
    () => '''
[
  {
    "id": "positions",
    "component": "QaPositionList",
    "title": "Tus posiciones",
    "items": [
      {"ticker": "AAPL", "weightPct": 23.0, "pnlPct": 8.1, "marketValue": 2864},
      {"ticker": "MSFT", "weightPct": 18.5, "pnlPct": -4.2, "marketValue": 2303}
    ]
  }
]
''',
  ],
);

const _fundamentalsGroupEnum = [
  'valuation',
  'profitability',
  'dividend',
  'other',
];

final _fundamentalsMetricItemSchema = S.object(
  properties: {
    'label': S.string(
      description:
          'Nombre corto del indicador, ej. "P/E", "Market cap", "Margen '
          'neto", "Dividend yield".',
    ),
    'value': S.string(
      description:
          'Valor ya formateado como texto, copiado/formateado de '
          'fundamentals.{TICKER} — nunca inventado. Ej. "38,6x", "\$4,98T", '
          '"27,6%".',
    ),
    'group': S.string(
      enumValues: _fundamentalsGroupEnum,
      description:
          'Sección: valuation (P/E, P/B, EV/EBITDA, market cap), '
          'profitability (márgenes, ROE, ROA, EPS), dividend (yield, '
          'payout), other (beta, volumen).',
    ),
  },
  required: ['label', 'value'],
);

final CatalogItem qaFundamentalsItem = CatalogItem(
  name: 'QaFundamentals',
  dataSchema: S.object(
    description:
        'Métricas fundamentales de UN ticker (valuación, rentabilidad, '
        'dividendo), tomadas de fundamentals.{TICKER}. Lista flexible de '
        '1-8 pares label/value: incluí solo los indicadores relevantes a la '
        'pregunta, no todos los disponibles. El rango de 52 semanas va en '
        'week52Low/week52High, no como item.',
    properties: {
      'ticker': S.string(),
      'industry': S.string(description: 'fundamentals.industry (opcional).'),
      'items': S.list(
        items: _fundamentalsMetricItemSchema,
        minItems: 1,
        maxItems: 8,
      ),
      'week52Low': S.number(description: 'week_52_low (opcional).'),
      'week52High': S.number(description: 'week_52_high (opcional).'),
      'currentPrice': S.number(
        description:
            'Precio actual de get_quote, solo si ya lo llamaste (opcional).',
      ),
    },
    required: ['ticker', 'items'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaFundamentals),
  exampleData: [
    () => '''
[
  {
    "id": "fundamentals",
    "component": "QaFundamentals",
    "ticker": "AAPL",
    "industry": "Technology",
    "items": [
      {"label": "P/E (TTM)", "value": "38,6x", "group": "valuation"},
      {"label": "Market cap", "value": "\$4,98T", "group": "valuation"},
      {"label": "Margen neto", "value": "27,6%", "group": "profitability"},
      {"label": "ROE", "value": "151,9%", "group": "profitability"},
      {"label": "Dividend yield", "value": "0,51%", "group": "dividend"}
    ],
    "week52Low": 169.21,
    "week52High": 260.10
  }
]
''',
  ],
);

/// Composición de UN ETF o fondo. El modelo solo nombra el ticker: las
/// posiciones, pesos, sectores y costo los pone la app desde
/// `get_etf_holdings` (ver `FundWidgets`).
final CatalogItem qaEtfHoldingsItem = CatalogItem(
  name: 'QaEtfHoldings',
  dataSchema: S.object(
    description:
        'Composición de UN ETF/fondo. Solo el ticker: la app pone posiciones, '
        'pesos, sectores y costo desde get_etf_holdings.',
    properties: {'ticker': S.string()},
    required: ['ticker'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaEtfHoldings),
  exampleData: [
    () => '''
[
  {
    "id": "holdings",
    "component": "QaEtfHoldings",
    "ticker": "XLF"
  }
]
''',
  ],
);

/// Análisis de UNA empresa. El modelo solo escribe texto: todos los números
/// de la card los pone la app desde las tools del turno (ver
/// `AnalysisWidgets`).
final CatalogItem qaCompanyAnalysisItem = CatalogItem(
  name: 'QaCompanyAnalysis',
  dataSchema: S.object(
    description:
        'Análisis de UNA empresa para un inversor casual. Escribí SOLO texto '
        'en español llano: la app completa sola precio, métricas, rango 52 '
        'semanas, resultados, titulares, riesgo y cartera desde tus tools. '
        'Cada número que escribas debe estar en un resultado de tool; sin '
        'consejos de compra/venta ni "barata/cara" sin un dato comparable.',
    properties: {
      'ticker': S.string(),
      'summary': S.string(
        description: '2-3 oraciones: la lectura general de la empresa.',
      ),
      'keyPoints': S.list(
        description: '3-4 puntos cortos.',
        items: S.object(
          properties: {
            'tone': S.string(enumValues: ['strength', 'neutral', 'watch']),
            'text': S.string(
              description:
                  'Ej. "Rentabilidad alta: gana 30 de cada 100 dólares que '
                  'vende".',
            ),
          },
          required: ['tone', 'text'],
        ),
        maxItems: 4,
      ),
      'metrics': S.list(
        description: 'Las 3-4 métricas más relevantes (no todas).',
        items: S.object(
          properties: {
            'key': S.string(
              enumValues: [for (final m in AnalysisMetric.values) m.key],
            ),
            'explanation': S.string(
              description:
                  'Una línea de qué significa, ej. "pagás 11,6 veces lo '
                  'que gana por año".',
            ),
          },
          required: ['key', 'explanation'],
        ),
        maxItems: 4,
      ),
      'newsTake': S.string(
        description:
            'Solo si get_news ok: una línea con el tono general de lo que '
            'dicen los titulares.',
      ),
    },
    required: ['ticker', 'summary'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(
        ctx,
        PortfolioQaCatalogWidgets.qaCompanyAnalysis,
      ),
  exampleData: [
    () => '''
[
  {
    "id": "analysis",
    "component": "QaCompanyAnalysis",
    "ticker": "BAC",
    "summary": "Bank of America es uno de los bancos más grandes de Estados Unidos y hoy gana bien con lo que presta. El mercado lo valora con cautela, típico de un banco.",
    "keyPoints": [
      {"tone": "strength", "text": "Rentabilidad alta: gana 30 de cada 100 dólares que vende."},
      {"tone": "neutral", "text": "Paga un dividendo del 3,2% por año."},
      {"tone": "watch", "text": "Como todo banco, depende de las tasas de interés."}
    ],
    "metrics": [
      {"key": "pe_ttm", "explanation": "Pagás 11,6 veces lo que la empresa gana por año."},
      {"key": "net_margin_ttm", "explanation": "De cada 100 dólares que factura, le quedan 30."},
      {"key": "roe_ttm", "explanation": "Gana 11 dólares por cada 100 que pusieron sus accionistas."}
    ],
    "newsTake": "Los titulares hablan sobre todo de sus resultados y del negocio de tarjetas."
  }
]
''',
  ],
);

/// Lo agrega la APP (nunca el modelo) cuando una fuente de Gold vino
/// `locked`: ver `AssistantAnswerReview._withGoldTeaser`.
final CatalogItem qaGoldTeaserItem = CatalogItem(
  name: 'QaGoldTeaser',
  dataSchema: S.object(
    description: 'Solo lo agrega la app. Nunca lo emitas.',
    properties: {'ticker': S.string()},
    required: ['ticker'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaGoldTeaser),
  exampleData: [
    () => '''
[
  {"id": "goldTeaser", "component": "QaGoldTeaser", "ticker": "NVDA"}
]
''',
  ],
);

final _newsItemSchema = S.object(
  properties: {
    'headline': S.string(),
    'summaryLine': S.string(
      description: 'Resumen en UNA oración, lenguaje llano (no jerga).',
    ),
    'dateLabel': S.string(
      description:
          'Fecha legible de la noticia, ej. "hoy", "hace 2 días", '
          '"18 sep 2026" — debe reflejar la antigüedad real.',
    ),
    'source': S.string(description: 'Medio/fuente de la noticia (opcional).'),
    'url': S.string(
      description:
          'news[].url copiada TAL CUAL de get_news (la app la usa para la '
          'imagen y el link). Nunca inventada.',
    ),
    'ticker': S.string(
      description: 'news[].ticker, solo si la card mezcla varios tickers.',
    ),
  },
  required: ['headline', 'summaryLine', 'dateLabel'],
);

final _epsQuarterSchema = S.object(
  properties: {
    'periodLabel': S.string(description: 'fiscal_period_label, ej. "T2 FY26".'),
    'epsActual': S.number(),
    'epsEstimate': S.number(),
  },
  required: ['periodLabel', 'epsActual', 'epsEstimate'],
);

final CatalogItem qaEarningsCalendarItem = CatalogItem(
  name: 'QaEarningsCalendar',
  dataSchema: S.object(
    description:
        'Próximo reporte de resultados de un ticker y/o cómo le fue en sus '
        'últimos reportes (real vs. esperado por el mercado). Los bloques '
        'son independientes: nextReport* para "¿cuándo reporta X?", eps* + '
        'history para "¿cómo le fue a X?".',
    properties: {
      'ticker': S.string(),
      'nextReportDateLabel': S.string(
        description:
            'Fecha del próximo reporte, legible, ej. "13 nov 2026" '
            '(omitir si no hay reporte próximo programado).',
      ),
      'nextReportDate': S.string(
        description:
            'next_report.date (ISO "2026-11-13"), junto con '
            'nextReportDateLabel — la app calcula la cuenta regresiva.',
      ),
      'timingLabel': S.string(
        description: 'next_report.timing_label (opcional).',
      ),
      'fiscalPeriodLabel': S.string(
        description: 'Ej. "T3 FY26" (opcional, junto con nextReportDateLabel).',
      ),
      'nextEpsEstimate': S.number(
        description:
            'EPS esperado por el mercado para el PRÓXIMO reporte (consenso '
            'de analistas, no un resultado ya publicado). Opcional, junto '
            'con nextReportDateLabel — usar para "¿cuáles son las ganancias '
            'esperadas de X?" / "expected earnings". Distinto de epsEstimate, '
            'que es la comparación del último reporte YA publicado.',
      ),
      'latestReportDateLabel': S.string(
        description:
            'latest_result.report_date_label, o su fiscal_period_label si '
            'no hay fecha (opcional).',
      ),
      'epsActual': S.number(
        description: 'EPS real del último reporte (opcional).',
      ),
      'epsEstimate': S.number(
        description: 'EPS esperado por el mercado (opcional).',
      ),
      'beat': S.boolean(
        description: 'true si epsActual superó epsEstimate (opcional).',
      ),
      'history': S.list(
        description:
            'get_earnings history copiado en el mismo orden (más viejo '
            'primero), para "¿cómo le fue?" (opcional).',
        items: _epsQuarterSchema,
        maxItems: 4,
      ),
    },
    required: ['ticker'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(
        ctx,
        PortfolioQaCatalogWidgets.qaEarningsCalendar,
      ),
  exampleData: [
    () => '''
[
  {
    "id": "earnings_next",
    "component": "QaEarningsCalendar",
    "ticker": "NVDA",
    "nextReportDateLabel": "13 nov 2026",
    "nextReportDate": "2026-11-13",
    "timingLabel": "Después del cierre",
    "fiscalPeriodLabel": "T3 FY26",
    "nextEpsEstimate": 1.28
  }
]
''',
    () => '''
[
  {
    "id": "earnings_latest",
    "component": "QaEarningsCalendar",
    "ticker": "MSFT",
    "latestReportDateLabel": "24 jul 2026",
    "epsActual": 3.30,
    "epsEstimate": 3.10,
    "beat": true
  }
]
''',
    () => '''
[
  {
    "id": "earnings_full",
    "component": "QaEarningsCalendar",
    "ticker": "TSLA",
    "nextReportDateLabel": "20 oct 2026",
    "nextReportDate": "2026-10-20",
    "fiscalPeriodLabel": "T3 FY26",
    "nextEpsEstimate": 0.45,
    "latestReportDateLabel": "22 jul 2026",
    "epsActual": 0.40,
    "epsEstimate": 0.43,
    "beat": false,
    "history": [
      {"periodLabel": "T3 FY25", "epsActual": 0.50, "epsEstimate": 0.55},
      {"periodLabel": "T4 FY25", "epsActual": 0.50, "epsEstimate": 0.47},
      {"periodLabel": "T1 FY26", "epsActual": 0.27, "epsEstimate": 0.41},
      {"periodLabel": "T2 FY26", "epsActual": 0.40, "epsEstimate": 0.43}
    ]
  }
]
''',
  ],
);

final CatalogItem qaNewsSummaryItem = CatalogItem(
  name: 'QaNewsSummary',
  dataSchema: S.object(
    description:
        '2-3 titulares recientes de un ticker, resumidos en una línea cada '
        'uno en lenguaje llano, con fecha visible. Cada item lleva la url '
        'de get_news.',
    properties: {
      'ticker': S.string(),
      'items': S.list(items: _newsItemSchema, minItems: 1, maxItems: 3),
    },
    required: ['ticker', 'items'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaNewsSummary),
  exampleData: [
    () => '''
[
  {
    "id": "news",
    "component": "QaNewsSummary",
    "ticker": "AAPL",
    "items": [
      {
        "headline": "Apple supera expectativas de ingresos en el trimestre",
        "summaryLine": "Los ingresos por servicios impulsaron el resultado por encima de lo esperado.",
        "dateLabel": "hace 2 días",
        "source": "Reuters",
        "url": "https://www.reuters.com/technology/apple-results"
      },
      {
        "headline": "Apple anuncia nueva línea de chips propios",
        "summaryLine": "La compañía busca reducir su dependencia de proveedores externos.",
        "dateLabel": "hace 5 días",
        "source": "Bloomberg",
        "url": "https://www.bloomberg.com/news/apple-chips"
      }
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
  widgetBuilder:
      (ctx) => guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaTipBanner),
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

final CatalogItem qaInvestOptionItem = CatalogItem(
  name: 'QaInvestOption',
  dataSchema: S.object(
    description: 'UN candidato de inversión educativa; una card por candidato.',
    properties: {
      'ticker': S.string(),
      'thesis': S.string(description: 'Tesis breve (1-2 frases).'),
      'fitScore': S.number(
        description:
            'Puntuación de encaje 0-100 (desde candidates[].fit_score).',
      ),
      'pro': S.string(description: 'Argumento a favor.'),
      'con': S.string(description: 'Argumento en contra.'),
      'currentPrice': S.number(
        description:
            'Precio actual (opcional, desde candidates[].current_price).',
      ),
      'weekChangePct': S.number(description: 'candidates[].week_change_pct'),
      'riskLevel': S.string(description: 'candidates[].risk_level'),
      'sector': S.string(description: 'candidates[].sector'),
      'budgetUsd': S.number(description: 'budget_usd, si has_budget'),
    },
    required: ['ticker', 'thesis', 'fitScore', 'pro', 'con'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaInvestOption),
  exampleData: [
    () => '''
[
  {
    "id": "invest_option",
    "component": "QaInvestOption",
    "ticker": "NVDA",
    "thesis": "Líder en chips para IA",
    "fitScore": 85,
    "pro": "Diversifica fuera de tu sector dominante",
    "con": "Alta volatilidad y valuación elevada",
    "currentPrice": 120.50,
    "weekChangePct": 2.4,
    "riskLevel": "crecimiento",
    "sector": "Tecnología",
    "budgetUsd": 500
  }
]
''',
  ],
);

final CatalogItem qaBudgetSplitItem = CatalogItem(
  name: 'QaBudgetSplit',
  dataSchema: S.object(
    description: 'Distribución educativa del presupuesto entre 2-4 tickers.',
    properties: {
      'totalBudget': S.number(
        description: 'Presupuesto total en USD (desde budget_usd).',
      ),
      'items': S.list(items: _budgetSplitItemSchema, minItems: 2, maxItems: 4),
    },
    required: ['totalBudget', 'items'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaBudgetSplit),
  exampleData: [
    () => '''
[
  {
    "id": "budget_split",
    "component": "QaBudgetSplit",
    "totalBudget": 5000,
    "items": [
      {"ticker": "NVDA", "amount": 2500, "pct": 50},
      {"ticker": "MSFT", "amount": 1500, "pct": 30},
      {"ticker": "AAPL", "amount": 1000, "pct": 20}
    ]
  }
]
''',
  ],
);

final CatalogItem qaInvestConfirmItem = CatalogItem(
  name: 'QaInvestConfirm',
  dataSchema: S.object(
    description:
        'Resumen educativo de confirmación (no ejecuta operaciones reales).',
    properties: {
      'summary': S.string(description: 'Resumen breve de la simulación.'),
      'budgetUsd': S.number(description: 'Presupuesto simulado en USD.'),
      'disclaimer': S.string(
        description: 'Aviso legal educativo (tiene valor por defecto).',
      ),
      'tickers': S.list(
        items: S.string(),
        minItems: 1,
        maxItems: 4,
        description: 'Lista de tickers involucrados.',
      ),
    },
    required: ['summary', 'budgetUsd', 'tickers'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaInvestConfirm),
  exampleData: [
    () => '''
[
  {
    "id": "invest_confirm",
    "component": "QaInvestConfirm",
    "summary": "Simulación de asignar \$5.000 entre NVDA, MSFT y AAPL.",
    "budgetUsd": 5000,
    "tickers": ["NVDA", "MSFT", "AAPL"]
  }
]
''',
  ],
);

/// Operación propuesta por Porty para que el usuario la confirme (ver
/// docs/superpowers/plans/2026-10-08-acciones-de-porty.md).
final CatalogItem qaActionProposalItem = CatalogItem(
  name: 'QaActionProposal',
  dataSchema: S.object(
    description:
        'Operación para que el usuario revise y confirme: UNA por cada '
        'resultado ok de propose_*. Solo proposalId; la app pone los datos.',
    properties: {
      'proposalId': S.string(
        description: 'proposal_id del resultado de la tool propose_*.',
      ),
    },
    required: ['proposalId'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaActionProposal),
  exampleData: [
    () => '''
[
  {
    "id": "action_1",
    "component": "QaActionProposal",
    "proposalId": "3f1c2a9e-0b7d-4e55-9a51-6c2f0d8e7a10"
  }
]
''',
  ],
);

final CatalogItem qaSavingsPlanItem = CatalogItem(
  name: 'QaSavingsPlan',
  dataSchema: S.object(
    description:
        'El plan de ahorro de una meta o jubilación (ahorro mensual por '
        'escenario, curva con intereses, cartera sugerida, retiro). Solo '
        'planId; la app pone todos los datos.',
    properties: {
      'planId': S.string(
        description: 'plan_id del resultado de get_goal_projection.',
      ),
      'focus': S.string(
        enumValues: ['income', 'savings', 'growth', 'progress'],
        description:
            'Qué responde arriba: income (cómo cobraría un ingreso), '
            'savings (cuánto ahorrar), growth (cómo crece / otro aporte), '
            'progress (cómo va la meta).',
      ),
    },
    required: ['planId'],
  ),
  widgetBuilder:
      (ctx) =>
          guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaSavingsPlan),
  exampleData: [
    () => '''
[
  {
    "id": "plan",
    "component": "QaSavingsPlan",
    "planId": "plan-1a2b3c4d",
    "focus": "income"
  }
]
''',
  ],
);

final CatalogItem qaBuyPlanItem = CatalogItem(
  name: 'QaBuyPlan',
  dataSchema: S.object(
    description:
        'La compra mensual de un plan: qué comprar cada mes y cuánto a cada '
        'instrumento, con su rendimiento. Solo buyPlanId; la app pone los '
        'datos.',
    properties: {
      'buyPlanId': S.string(
        description: 'buy_plan_id del resultado de get_monthly_buy_plan.',
      ),
    },
    required: ['buyPlanId'],
  ),
  widgetBuilder:
      (ctx) => guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaBuyPlan),
  exampleData: [
    () => '''
[
  {
    "id": "buy",
    "component": "QaBuyPlan",
    "buyPlanId": "buy-1a2b3c4d"
  }
]
''',
  ],
);

final CatalogItem qaComparisonRowItem = CatalogItem(
  name: 'QaComparisonRow',
  dataSchema: S.object(
    description:
        'Dos tickers lado a lado con un valor cada uno (ej. P&L de tus '
        'posiciones); resalta el mayor.',
    properties: {
      'label': S.string(),
      'leftTicker': S.string(),
      'leftValue': S.string(),
      'rightTicker': S.string(),
      'rightValue': S.string(),
      'metricLabel': S.string(),
    },
    required: ['label', 'leftTicker', 'leftValue', 'rightTicker', 'rightValue'],
  ),
  widgetBuilder:
      (ctx) =>
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
