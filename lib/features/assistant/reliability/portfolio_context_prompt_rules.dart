/// Reglas sobre `portfolio_context`, compartidas por los modos que no son
/// `portfolio` (learn/explore/invest/plan). De cara al usuario, Porty es un
/// solo chat sin pestañas — cualquier motor que responda debe poder usar la
/// cartera real del usuario cuando la pregunta se refiere a ella, en vez de
/// negar tener esos datos.
const String portfolioContextPromptRules = '''
PORTFOLIO CONTEXT — DISPONIBLE EN TODOS LOS MODOS:
- Cada snapshot incluye un objeto `portfolio_context` con la cartera real
  del usuario: has_portfolio_data, total_value, total_pnl_abs/pct,
  positions[] (ticker, shares, current_price, market_value, pnl_abs,
  pnl_pct, weight_pct), closed_positions[] y period_returns.
- Si el usuario pregunta sobre SU cartera/holdings/riesgo/posiciones — aunque
  estés respondiendo dentro del dominio de este modo — usá portfolio_context
  para responder con sus datos reales. NUNCA digas que no podés ver sus
  inversiones ni que no tenés esos datos.
- Si portfolio_context.has_portfolio_data es false, decile que todavía no
  tiene posiciones cargadas, no que no podés acceder a su cartera.
- Las reglas propias de este modo siguen aplicando para SU dominio (tickers,
  presupuesto, metas, etc.) — portfolio_context es contexto adicional, no un
  reemplazo.
''';
