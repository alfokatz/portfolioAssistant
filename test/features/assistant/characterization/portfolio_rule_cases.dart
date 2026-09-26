import 'rules_contract.dart';

/// Casos contrato del modo Portfolio tal como están hoy (ver
/// `rules_contract.dart`). Compartidos con la suite unificada, que tiene
/// que cubrir cada id — ver `unified_rules_contract_test.dart`.
const portfolioRuleCases = <RuleCase>[
  // Rendimiento de la cartera completa en un período.
  RuleCase(
    id: 'PF-TEMP-DAY',
    question: '¿cómo le fue a mi portfolio hoy?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: ['"hoy", "último día" → period_returns.day', 'use QaPeriodChange'],
  ),
  RuleCase(
    id: 'PF-TEMP-WEEK',
    question: '¿cómo le fue a mi portfolio esta semana?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: [
      '"esta semana", "últimos 7 días", "semanal" → period_returns.week',
    ],
  ),
  RuleCase(
    id: 'PF-TEMP-MONTH',
    question: '¿cómo vino mi cartera este mes?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: ['"este mes", "último mes", "mensual" → period_returns.month'],
  ),
  RuleCase(
    id: 'PF-TEMP-QUARTER',
    question: '¿cómo le fue a mi portfolio en el trimestre?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: ['"trimestre", "últimos 3 meses" → period_returns.quarter'],
  ),
  RuleCase(
    id: 'PF-TEMP-YEAR',
    question: '¿cómo le fue a mi portfolio este año?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: ['"este año", "anual" → period_returns.year'],
  ),
  RuleCase(
    id: 'PF-TEMP-NOT-ALLTIME',
    question: '¿cuánto gané esta semana?',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: ['QaPeriodChange'],
    anchors: [
      'NEVER use total_pnl_abs or QaPnLBreakdown for "esta semana" or similar.',
      'total_pnl_abs / total_pnl_pct = ALL-TIME since purchase',
    ],
  ),
  RuleCase(
    id: 'PF-TEMP-NO-HISTORY',
    question: '¿cómo le fue a mi portfolio este año? (sin historial)',
    section: 'TEMPORAL QUESTIONS',
    expectedWidgets: [],
    anchors: [
      'If has_sufficient_history is false for the requested period, say so in\nQaAnswerText and omit the data widget.',
    ],
  ),
  // Un ticker (de la cartera) en un período.
  RuleCase(
    id: 'PF-TICKER-PERIOD',
    question: '¿cómo fue AAPL esta semana?',
    section: 'TICKER-SPECIFIC QUESTIONS',
    expectedWidgets: ['QaTickerMove'],
    anchors: [
      '"¿cómo fue AAPL esta semana?" → position_periods.AAPL.week + QaTickerMove',
      'weightPct from positions[]',
    ],
  ),
  // "¿Por qué?" — sin noticias en el snapshot de Portfolio.
  RuleCase(
    id: 'PF-WHY-TICKER',
    question: '¿por qué cayó NVDA?',
    section: 'WHY / CAUSATION QUESTIONS',
    expectedWidgets: ['QaTickerMove', 'QaTipBanner'],
    anchors: [
      'You have NO verified news or event data in the snapshot.',
      'NEVER invent causes, news, earnings, macro events, or "probablemente…".',
      'Use QaTickerMove (single ticker) or QaPeriodChange (whole portfolio).',
      'Add QaTipBanner (tone=info)',
    ],
  ),
  RuleCase(
    id: 'PF-WHY-PORTFOLIO',
    question: '¿por qué bajó mi portfolio?',
    section: 'WHY / CAUSATION QUESTIONS',
    expectedWidgets: ['QaPeriodChange', 'QaTipBanner'],
    anchors: [
      'State only the numeric move from position_periods or period_returns.',
    ],
  ),
  // Posiciones cerradas (P&L realizado).
  RuleCase(
    id: 'PF-CLOSED-TOTAL',
    question: '¿cuánto gané en total con lo que cerré?',
    section: 'CLOSED POSITIONS',
    expectedWidgets: ['QaPnLBreakdown'],
    anchors: [
      '"cuánto gané en total cerrado": QaPnLBreakdown with costBasis =\n  closed_pnl_total_cost_basis',
    ],
  ),
  RuleCase(
    id: 'PF-CLOSED-BEST-WORST',
    question: '¿cuál fue mi mejor operación cerrada?',
    section: 'CLOSED POSITIONS',
    expectedWidgets: ['QaTopMovers'],
    anchors: [
      '"mejor/peor operación cerrada": QaTopMovers from closed_positions by pnl_pct',
    ],
  ),
  RuleCase(
    id: 'PF-CLOSED-LIST',
    question: 'listame mis posiciones cerradas',
    section: 'CLOSED POSITIONS',
    expectedWidgets: ['QaClosedPositionList'],
    anchors: [
      '"listar posiciones cerradas": QaClosedPositionList (max 6 items, most recent)',
    ],
  ),
  RuleCase(
    id: 'PF-CLOSED-COMPARE',
    question: 'comparame lo que gané con TSLA y con AMD (cerradas)',
    section: 'CLOSED POSITIONS',
    expectedWidgets: ['QaComparisonRow'],
    anchors: [
      'Compare two closed tickers: QaComparisonRow using pnl_pct or pnl_abs',
    ],
  ),
  RuleCase(
    id: 'PF-CLOSED-NO-MIX',
    question: '¿cuánto gané en total? (con abiertas y cerradas)',
    section: 'CLOSED POSITIONS',
    expectedWidgets: [],
    anchors: [
      'NEVER mix closed realized P&L with open unrealized total_pnl_*',
      'If has_positions is false but has_closed_positions is true, the user has\n  NO open positions',
    ],
  ),
  // Guía general (lista plana, sin jerarquía — ver KNOWN GAPS abajo).
  RuleCase(
    id: 'PF-GUIDE-SNAPSHOT',
    question: '¿cómo está mi cartera ahora?',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaMetricStrip'],
    anchors: ['- Current snapshot / open positions: QaMetricStrip'],
  ),
  RuleCase(
    id: 'PF-GUIDE-ALLTIME',
    question: '¿cuánto gané desde que compré todo?',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaPnLBreakdown'],
    anchors: [
      '- All-time open P&L meaning: QaPnLBreakdown from total_cost_basis / total_value',
    ],
  ),
  RuleCase(
    id: 'PF-GUIDE-RISK',
    question: '¿qué tan concentrada está mi cartera?',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaConcentrationBar'],
    anchors: ['- Risk / concentration (open): QaConcentrationBar'],
  ),
  RuleCase(
    id: 'PF-GUIDE-BEST-WORST-OPEN',
    question: '¿cuáles son mis mejores y peores posiciones?',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaTopMovers'],
    anchors: ['- Best/worst open positions: QaTopMovers from positions[]'],
  ),
  RuleCase(
    id: 'PF-GUIDE-LIST-OPEN',
    question: 'listame mis posiciones',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaPositionList'],
    anchors: ['- List open positions: QaPositionList'],
  ),
  RuleCase(
    id: 'PF-GUIDE-COMPARE',
    question: 'comparame AAPL y MSFT en mi cartera',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaComparisonRow'],
    anchors: ['- Compare two tickers: QaComparisonRow'],
  ),
  RuleCase(
    id: 'PF-GUIDE-CONCEPT',
    question: '¿qué es la diversificación?',
    section: 'WIDGET SELECTION GUIDE',
    expectedWidgets: ['QaAnswerText'],
    anchors: [
      '- Pure conceptual questions (what is diversification): QaAnswerText only',
    ],
  ),
];
