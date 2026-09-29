import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
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
  properties: {
    'ticker': S.string(),
    'amount': S.number(),
    'pct': S.number(),
  },
  required: ['ticker', 'amount', 'pct'],
);

final _milestoneItemSchema = S.object(
  properties: {
    'label': S.string(),
    'amount': S.number(),
    'dateLabel': S.string(description: 'Fecha legible, ej. "1 ene 2030".'),
  },
  required: ['label', 'amount', 'dateLabel'],
);

final _projectionChartPointSchema = S.object(
  properties: {
    'label': S.string(
      description: 'Etiqueta del punto en el eje X, ej. "Ene 2027".',
    ),
    'value': S.number(description: 'Monto proyectado en ese punto.'),
  },
  required: ['label', 'value'],
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
    description:
        'Fila de 2-3 métricas clave, lado a lado: portfolio mode para '
        'valor/P&L/P&L%, explore mode para comparar 2-3 tickers a la vez '
        '(un item por ticker).',
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

final CatalogItem qaTickerSnapshotItem = CatalogItem(
  name: 'QaTickerSnapshot',
  dataSchema: S.object(
    description:
        'Snapshot de precio y cambios día/semana/mes de un ticker (modo explore).',
    properties: {
      'ticker': S.string(),
      'currentPrice': S.number(description: 'Precio actual del ticker.'),
      'dayChangePct': S.number(description: 'Cambio porcentual del último día.'),
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
  widgetBuilder: (ctx) =>
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
      'currentPrice': S.number(description: 'explore_tickers.{T}.current_price.'),
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
  widgetBuilder: (ctx) =>
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
    },
    required: ['totalValue', 'pnlAbs', 'pnlPct'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaPositionsSnapshot),
  exampleData: [
    () => '''
[
  {
    "id": "positions_snapshot",
    "component": "QaPositionsSnapshot",
    "totalValue": 12450.3,
    "pnlAbs": 1830.5,
    "pnlPct": 17.2,
    "positionsCount": 6
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
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaMetricStrip),
  exampleData: [
    () => '''
[
  {
    "id": "compare",
    "component": "QaMetricStrip",
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
  },
  required: ['label', 'value'],
);

final CatalogItem qaFundamentalsItem = CatalogItem(
  name: 'QaFundamentals',
  dataSchema: S.object(
    description:
        'Métricas fundamentales de UN ticker (valuación, rentabilidad, '
        'dividendo, rango de 52 semanas), tomadas de fundamentals.{TICKER}. '
        'Lista flexible de 1-6 pares label/value: incluí solo los '
        'indicadores relevantes a la pregunta, no todos los disponibles.',
    properties: {
      'ticker': S.string(),
      'items': S.list(
        items: _fundamentalsMetricItemSchema,
        minItems: 1,
        maxItems: 6,
      ),
    },
    required: ['ticker', 'items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaFundamentals),
  exampleData: [
    () => '''
[
  {
    "id": "fundamentals",
    "component": "QaFundamentals",
    "ticker": "AAPL",
    "items": [
      {"label": "P/E (TTM)", "value": "38,6x"},
      {"label": "Market cap", "value": "\$4,98T"},
      {"label": "Margen neto", "value": "27,6%"},
      {"label": "Dividend yield", "value": "0,51%"}
    ]
  }
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
  },
  required: ['headline', 'summaryLine', 'dateLabel'],
);

final CatalogItem qaEarningsCalendarItem = CatalogItem(
  name: 'QaEarningsCalendar',
  dataSchema: S.object(
    description:
        'Próximo reporte de resultados de un ticker y/o cómo le fue en su '
        'último reporte (real vs. esperado por el mercado). Los dos bloques '
        'son independientes: usa nextReportDateLabel para "¿cuándo reporta '
        'X?" y los campos eps* para "¿cómo le fue a X?".',
    properties: {
      'ticker': S.string(),
      'nextReportDateLabel': S.string(
        description:
            'Fecha del próximo reporte, legible, ej. "13 nov 2026" '
            '(omitir si no hay reporte próximo programado).',
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
        description: 'Fecha del último reporte ya publicado (opcional).',
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
    },
    required: ['ticker'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaEarningsCalendar),
  exampleData: [
    () => '''
[
  {
    "id": "earnings_next",
    "component": "QaEarningsCalendar",
    "ticker": "NVDA",
    "nextReportDateLabel": "13 nov 2026",
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
  ],
);

final CatalogItem qaNewsSummaryItem = CatalogItem(
  name: 'QaNewsSummary',
  dataSchema: S.object(
    description:
        '2-3 titulares recientes de un ticker, resumidos en una línea cada '
        'uno en lenguaje llano, con fecha visible.',
    properties: {
      'ticker': S.string(),
      'items': S.list(items: _newsItemSchema, minItems: 1, maxItems: 3),
    },
    required: ['ticker', 'items'],
  ),
  widgetBuilder: (ctx) =>
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
        "source": "Reuters"
      },
      {
        "headline": "Apple anuncia nueva línea de chips propios",
        "summaryLine": "La compañía busca reducir su dependencia de proveedores externos.",
        "dateLabel": "hace 5 días",
        "source": "Bloomberg"
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

final CatalogItem qaInvestOptionItem = CatalogItem(
  name: 'QaInvestOption',
  dataSchema: S.object(
    description:
        'Tarjeta de opción de inversión educativa con fit score y pros/contras.',
    properties: {
      'ticker': S.string(),
      'thesis': S.string(description: 'Tesis breve en una línea.'),
      'fitScore': S.number(
        description: 'Puntuación de encaje 0-100 (desde candidates[].fit_score).',
      ),
      'pro': S.string(description: 'Argumento a favor.'),
      'con': S.string(description: 'Argumento en contra.'),
      'currentPrice': S.number(
        description: 'Precio actual (opcional, desde candidates[].current_price).',
      ),
    },
    required: ['ticker', 'thesis', 'fitScore', 'pro', 'con'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaInvestOption),
  exampleData: [
    () => '''
[
  {
    "id": "invest_option",
    "component": "QaInvestOption",
    "ticker": "NVDA",
    "thesis": "Líder en IA con fuerte momentum semanal",
    "fitScore": 78,
    "pro": "Diversifica fuera de tu sector dominante",
    "con": "Alta volatilidad y valuación elevada",
    "currentPrice": 120.50
  }
]
''',
  ],
);

final CatalogItem qaBudgetSplitItem = CatalogItem(
  name: 'QaBudgetSplit',
  dataSchema: S.object(
    description:
        'Distribución educativa del presupuesto entre 2-4 tickers.',
    properties: {
      'totalBudget': S.number(
        description: 'Presupuesto total en USD (desde budget_usd).',
      ),
      'items': S.list(
        items: _budgetSplitItemSchema,
        minItems: 2,
        maxItems: 4,
      ),
    },
    required: ['totalBudget', 'items'],
  ),
  widgetBuilder: (ctx) =>
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
  widgetBuilder: (ctx) =>
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

final CatalogItem qaGoalCardItem = CatalogItem(
  name: 'QaGoalCard',
  dataSchema: S.object(
    description: 'Tarjeta de meta financiera con monto objetivo y fecha.',
    properties: {
      'label': S.string(description: 'Nombre de la meta (desde active_goal.label).'),
      'targetAmount': S.number(
        description: 'Monto objetivo en USD (desde active_goal.target_amount).',
      ),
      'targetDateLabel': S.string(
        description: 'Fecha objetivo legible (desde active_goal.target_date).',
      ),
      'currentAmount': S.number(
        description:
            'Monto actual en USD (opcional, desde current_portfolio_value).',
      ),
    },
    required: ['label', 'targetAmount', 'targetDateLabel'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaGoalCard),
  exampleData: [
    () => '''
[
  {
    "id": "goal",
    "component": "QaGoalCard",
    "label": "Fondo de emergencia",
    "targetAmount": 50000,
    "targetDateLabel": "1 ene 2030",
    "currentAmount": 12000
  }
]
''',
  ],
);

final CatalogItem qaProjectionStripItem = CatalogItem(
  name: 'QaProjectionStrip',
  dataSchema: S.object(
    description:
        'Fila de 2-3 métricas de proyección (desde get_goal_projection.projection).',
    properties: {
      'requiredMonthlySavings': S.number(
        description: 'Ahorro mensual requerido (projection.required_monthly_savings).',
      ),
      'monthlyContributionUsed': S.number(
        description:
            'Aporte mensual usado (projection.monthly_contribution_used).',
      ),
      'monthsRemaining': S.number(
        description: 'Meses restantes (projection.months_remaining).',
      ),
      'projectedAmountAtDate': S.number(
        description:
            'Monto proyectado a la fecha (projection.projected_amount_at_date).',
      ),
      'onTrack': S.boolean(
        description: 'Si el aporte actual alcanza la meta (projection.on_track).',
      ),
    },
    required: ['monthsRemaining'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaProjectionStrip),
  exampleData: [
    () => '''
[
  {
    "id": "projection",
    "component": "QaProjectionStrip",
    "requiredMonthlySavings": 883.72,
    "monthlyContributionUsed": 200,
    "monthsRemaining": 43,
    "projectedAmountAtDate": 20600,
    "onTrack": false
  }
]
''',
  ],
);

final CatalogItem qaProjectionChartItem = CatalogItem(
  name: 'QaProjectionChart',
  dataSchema: S.object(
    description:
        'Chart de líneas de una proyección en el tiempo (ej. evolución '
        'proyectada de una meta financiera). Requiere al menos 2 puntos.',
    properties: {
      'label': S.string(description: 'Título corto del chart.'),
      'points': S.list(
        items: _projectionChartPointSchema,
        minItems: 2,
        maxItems: 12,
      ),
    },
    required: ['label', 'points'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaProjectionChart),
  exampleData: [
    () => '''
[
  {
    "id": "projection_chart",
    "component": "QaProjectionChart",
    "label": "Proyección de tu meta",
    "points": [
      {"label": "Hoy", "value": 5000},
      {"label": "Año 1", "value": 9800},
      {"label": "Año 2", "value": 14900},
      {"label": "Año 3", "value": 20600}
    ]
  }
]
''',
  ],
);

final CatalogItem qaMilestoneListItem = CatalogItem(
  name: 'QaMilestoneList',
  dataSchema: S.object(
    description: 'Lista compacta de hitos de la meta (desde get_goal_projection.milestones).',
    properties: {
      'title': S.string(),
      'items': S.list(
        items: _milestoneItemSchema,
        minItems: 1,
        maxItems: 4,
      ),
    },
    required: ['items'],
  ),
  widgetBuilder: (ctx) =>
      guardedCatalogWidget(ctx, PortfolioQaCatalogWidgets.qaMilestoneList),
  exampleData: [
    () => '''
[
  {
    "id": "milestones",
    "component": "QaMilestoneList",
    "title": "Hitos de la meta",
    "items": [
      {"label": "25%", "amount": 12500, "dateLabel": "10 jun 2027"},
      {"label": "50%", "amount": 25000, "dateLabel": "10 jun 2028"},
      {"label": "75%", "amount": 37500, "dateLabel": "10 jun 2029"},
      {"label": "100%", "amount": 50000, "dateLabel": "1 ene 2030"}
    ]
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
