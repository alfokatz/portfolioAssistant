// Titulares con recomendación directa al lector (revisión de compliance
// 2026-11-05). Se descartan, no se reescriben. "Analyst upgrades to Buy" no
// entra: informa un hecho. Misma lista y mismos casos que
// `WidgetItemsSelector.recommendation` (lib/features/home_widget/domain/);
// si cambia una, cambia la otra.

export const recommendationPatterns: RegExp[] = [
  /should you (buy|sell)/i,
  /(stocks?|shares?) to (buy|sell)/i,
  /(buy|sell) (now|today|this)/i,
  /time to (buy|sell)/i,
  /must[- ](buy|sell)/i,
  /best .* to (buy|sell)/i,
  /comprá|vendé|aprovechá/i,
];

export function isRecommendation(headline: string): boolean {
  return recommendationPatterns.some((r) => r.test(headline));
}
