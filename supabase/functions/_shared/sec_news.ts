// Capa 3 de las noticias por ticker: presentaciones recientes de la SEC (EDGAR),
// gratis y oficiales, para emisores de EE. UU. (CEDEAR y ADR incluidos, vía su
// subyacente). Salen como un titular más con fuente "SEC", link a la propia
// presentación y sin imagen.
//
// No muestra ni resume el texto de la presentación: solo qué TIPO de hecho es
// ("Presentó resultados trimestrales (8-K)"), armado por nosotros desde el
// formulario y los ítems del 8-K. El título depende del idioma de quien lo ve,
// así que en la caché compartida va el `kind` y el título se arma al servir
// (`filingTitle`).
//
// Cuota de la SEC: `companyFilings` ya cachea 1 h por empresa y `secFetch`
// limita cada instancia a ~5 pedidos/s (el tope de la SEC es 10/s).

import type { Deps } from "./common.ts";
import type { Headline } from "./gdelt.ts";
import { isUsPlainSymbol } from "./news_fallback.ts";
import { type Filing, normalizeTicker, relevantItems } from "./sec.ts";
import { companyFilings, resolveCik } from "./sec_data.ts";

export const secNewsConfig = {
  /// Ventana de lo "reciente".
  windowHours: 72,
  /// Presentaciones por ticker.
  maxPerTicker: 2,
};

export const SEC_SOURCE = "SEC";
export const SEC_DOMAIN = "sec.gov";

export type FilingKind =
  | "results"
  | "agreement"
  | "assets"
  | "management"
  | "market_update"
  | "other_event"
  | "quarterly_report"
  | "annual_report"
  | "foreign_update";

/// Prioridad de los ítems del 8-K: resultados primero.
const itemKinds: [string, FilingKind][] = [
  ["2.02", "results"],
  ["1.01", "agreement"],
  ["2.01", "assets"],
  ["5.02", "management"],
  ["7.01", "market_update"],
  ["8.01", "other_event"],
];

const titles: Record<FilingKind, { es: string; en: string }> = {
  results: { es: "Presentó resultados trimestrales", en: "Reported quarterly results" },
  agreement: { es: "Firmó un acuerdo relevante", en: "Entered a material agreement" },
  assets: { es: "Completó una compra o venta de activos", en: "Completed an acquisition or disposal" },
  management: { es: "Anunció cambios en su dirección", en: "Announced a leadership change" },
  market_update: { es: "Comunicó información al mercado", en: "Shared an update with the market" },
  other_event: { es: "Informó otro hecho relevante", en: "Reported another material event" },
  quarterly_report: { es: "Presentó su informe trimestral", en: "Filed its quarterly report" },
  annual_report: { es: "Presentó su informe anual", en: "Filed its annual report" },
  foreign_update: { es: "Comunicó información al mercado", en: "Shared an update with the market" },
};

/// "Presentó resultados trimestrales (8-K)" / "Reported quarterly results (8-K)".
export const filingTitle = (kind: FilingKind, form: string, lang: "es" | "en") =>
  `${(titles[kind] ?? titles.market_update)[lang]} (${form})`;

/// Qué tipo de hecho es una presentación; null si no se muestra (8-K sin ítems
/// relevantes, enmiendas, formularios que no son noticia).
export function classifyFiling(f: Pick<Filing, "form" | "items">): FilingKind | null {
  if (f.form === "8-K") {
    for (const [item, kind] of itemKinds) if (f.items.includes(item) && relevantItems.has(item)) return kind;
    return null;
  }
  if (f.form === "10-Q") return "quarterly_report";
  if (f.form === "10-K" || f.form === "20-F" || f.form === "40-F") return "annual_report";
  if (f.form === "6-K") return "foreign_update";
  return null;
}

/// Cuándo se presentó: `accepted` si lo trae; si no, la fecha a mediodía UTC
/// (lo cacheado antes de `accepted` solo tiene el día).
const filedAt = (f: Filing) => f.accepted ?? `${f.filed}T12:00:00.000Z`;

const priority: Record<FilingKind, number> = {
  results: 0, agreement: 1, assets: 2, management: 3, other_event: 4, market_update: 5,
  quarterly_report: 6, annual_report: 6, foreign_update: 7,
};

/// Puro: presentaciones de [filings] dentro de la ventana, como titulares.
export function filingsToHeadlines(filings: Filing[], nowMs: number): Headline[] {
  const out: Headline[] = [];
  for (const f of filings) {
    const kind = classifyFiling(f);
    if (!kind) continue;
    const at = Date.parse(filedAt(f));
    if (!Number.isFinite(at) || nowMs - at > secNewsConfig.windowHours * 3600_000) continue;
    out.push({
      title: filingTitle(kind, f.form, "es"),
      url: f.url,
      source: SEC_SOURCE,
      domain: SEC_DOMAIN,
      // Nunca en el futuro (la fecha sin hora se toma a mediodía).
      published_at: new Date(Math.min(at, nowMs)).toISOString(),
      language: "es",
      source_kind: "filing",
      filing: { form: f.form, kind },
    });
  }
  // Resultados primero; después lo más nuevo.
  return out
    .sort((a, b) =>
      priority[a.filing!.kind as FilingKind] - priority[b.filing!.kind as FilingKind] || b.published_at.localeCompare(a.published_at)
    )
    .slice(0, secNewsConfig.maxPerTicker);
}

export type SecNewsResult = { status: "ok" | "skipped" | "failed"; items: Headline[] };

type SecDeps = Pick<Deps, "db" | "fetch" | "env" | "now" | "background">;

/// Presentaciones recientes de [symbol] (ya el subyacente de EE. UU.). `skipped`
/// = no aplica (no es un emisor de la SEC); `failed` = la SEC no respondió.
/// Nunca lanza.
export async function secHeadlines(deps: SecDeps, symbol: string): Promise<SecNewsResult> {
  if (!isUsPlainSymbol(symbol)) return { status: "skipped", items: [] };
  try {
    const row = await resolveCik(deps, normalizeTicker(symbol));
    if (!row) return { status: "skipped", items: [] };
    const { value } = await companyFilings(deps, row.cik);
    return { status: "ok", items: filingsToHeadlines(value.filings, deps.now()) };
  } catch (e) {
    console.error("[sec-news]", symbol, String(e));
    return { status: "failed", items: [] };
  }
}

/// Un titular de la SEC con el título en el idioma de [lang].
export const localizedFilingTitle = (h: Pick<Headline, "title" | "filing">, lang: "es" | "en") =>
  h.filing ? filingTitle(h.filing.kind as FilingKind, h.filing.form, lang) : h.title;
