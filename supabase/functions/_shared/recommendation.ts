// Titulares con recomendación directa al lector (revisión de compliance
// 2026-11-05, ampliada en la de 2026-11-21 H5). Se descartan, no se reescriben.
// "Analyst upgrades to Buy" no entra: informa un hecho. Misma lista y mismos
// casos que `WidgetItemsSelector.recommendation`
// (lib/features/home_widget/domain/); si cambia una, cambia la otra.
//
// Criterio para no tirar noticias legítimas ("Apple compra una startup"):
// - Las formas verbales imperativas ambiguas con la tercera persona (es:
//   compra, vende, invierte; en: buy, sell, invest) solo cuentan al INICIO del
//   titular (o tras ":", "!", "¡", "¿", "|", "–", "—"), donde son una orden. Con
//   un sujeto antes ("Apple compra...") es un hecho y pasa.
// - Las formas que no coinciden con la tercera persona del indicativo (es
//   compre/venda/invierta, comprá/vendé) cuentan con ese mismo ancla de inicio
//   o, las voseantes, en cualquier parte.
// - "Compra de..."/"Compra del..." (sustantivo) y "Sell off", "Sell America",
//   "Buy American" (noticias) quedan afuera.
// - Costo asumido: "price target" también descarta titulares informativos de
//   analistas ("X sube el price target de Y"). Es a propósito: es la frase
//   que más se parece a una recomendación y la revisión pidió bajarla.
// - Los "{0,1}" acotan "qué X comprar" / "what X to buy" para no agarrar
//   "Por qué Tesla quiere vender...".

export const recommendationPatterns: RegExp[] = [
  /should you (buy|sell)/i,
  /(stocks?|shares?) to (buy|sell)/i,
  /(buy|sell) (now|today|this)/i,
  /time to (buy|sell)/i,
  /must[- ](buy|sell)/i,
  /best .* to (buy|sell)/i,
  /comprá|vendé|aprovechá/i,
  // H5 (2026-11-21)
  /\b(stock|etf|crypto)s? picks?\b/i,
  /\btop (\d+ )?picks?\b/i,
  /price targets?\b|precio objetivo|objetivo de precio/i,
  /price (predictions?|forecasts?)|predicci[oó]n(es)? del? precios?|pron[oó]sticos? del? precios?/i,
  /\bwhat (\w+ )?to (buy|sell)\b/i,
  /\bqu[eé] (\w+ )?(comprar|vender)\b/i,
  /d[oó]nde (invertir|poner (tu|su) (plata|dinero))|where to (invest|put your money)/i,
  /(acciones|cedears|bonos|criptos?|criptomonedas|etfs?) para (comprar|vender|invertir)/i,
  /mejores .* para (comprar|invertir)/i,
  /^\s*(?:(?:buy|sell)\s+(?!off\b|america\b|american\b)|invest\s+(?:in|now|today)\b)/i,
  /(?:^|[:!¡¿|–—])\s*(?:compra|vende|invierte|aprovecha)\s+(?!de\b|del\b)/i,
  /(?:^|[:!¡¿|–—])\s*(?:compre|venda|invierta)n?\b/i,
  /invert[ií](?![a-záéíóúñ])/i,
];

export function isRecommendation(headline: string): boolean {
  return recommendationPatterns.some((r) => r.test(headline));
}
