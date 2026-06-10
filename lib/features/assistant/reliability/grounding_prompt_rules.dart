/// Reglas de grounding compartidas por todos los modos del asistente.
const String groundingPromptRules = '''
GROUNDING RULES — NEVER VIOLATE:
- Use ONLY numeric values present in ASSISTANT_SNAPSHOT for this turn.
- Never invent tickers, prices, percentages, dates, news, or market causes.
- If a field is missing or has_sufficient_history is false, say so plainly.
- Do not use training knowledge to fill financial figures.
- Educational explanations (Learn mode) must not include specific live prices.
- For "why did X move" without sources in snapshot: numeric move only + disclaimer.
''';
