import 'rules_contract.dart';

/// Casos contrato del modo Learn tal como están hoy (ver
/// `rules_contract.dart`). Compartidos con la suite unificada, que tiene
/// que cubrir cada id — ver `unified_rules_contract_test.dart`.
const learnRuleCases = <RuleCase>[
  RuleCase(
    id: 'LN-CONCEPT',
    question: '¿qué es diversificar?',
    section: 'WIDGET SELECTION',
    expectedWidgets: ['QaAnswerText'],
    anchors: ['- Pure conceptual answers: QaAnswerText only.'],
  ),
  RuleCase(
    id: 'LN-CONCEPT-TAKEAWAY',
    question: '¿qué es el interés compuesto y cómo lo aprovecho?',
    section: 'WIDGET SELECTION',
    expectedWidgets: ['QaAnswerText', 'QaTipBanner'],
    anchors: ['- Concept + practical takeaway: QaAnswerText + QaTipBanner.'],
  ),
  RuleCase(
    id: 'LN-CONCEPT-NO-RANDOM-TICKERS',
    question: '¿qué es un ETF?',
    section: 'DATA LIMITS',
    expectedWidgets: [],
    anchors: [
      'explain\n  with generic examples only — do not inject random tickers or live prices\n  unrelated to the question.',
    ],
  ),
  RuleCase(
    id: 'LN-OWN-PORTFOLIO',
    question: '¿qué es lo que tiene más riesgo en mi portfolio?',
    section: 'DATA LIMITS',
    expectedWidgets: [],
    anchors: [
      'use portfolio_context to answer\n  with their real data — do NOT say you lack that data.',
    ],
  ),
  RuleCase(
    id: 'LN-TICKER-PRICE',
    question: '¿a cuánto está NVDA? (llegando a Learn)',
    section: 'DATA LIMITS',
    expectedWidgets: [],
    anchors: [
      "say you don't have live market data for\n  that in this reply and invite them to ask about that ticker directly",
      '(e.g. "¿cómo está NVDA?")',
    ],
  ),
];
