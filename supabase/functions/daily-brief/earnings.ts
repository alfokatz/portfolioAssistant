// Resultados del brief (solo Gold, spec §3.4):
// - `reported`: un 8-K con ítem 2.02 presentado desde el último cierre, con link
//   a la SEC. Está confirmado.
// - `estimated`: una próxima fecha ESTIMADA que cae en los 3 días hábiles
//   siguientes (EDGAR no publica calendario: se repite el reporte de hace un
//   año, ver `estimateNextReport`). Siempre se rotula "estimada" en la app.
//
// Solo emisores locales (10-K/10-Q): los 6-K de los extranjeros no traen
// ítems y no hay con qué fechar el reporte (hueco anotado: sin resultados
// para ellos, nunca se inventa).

import type { Deps } from "../_shared/common.ts";
import {
  earningsReleases,
  estimateNextReport,
  type Filing,
  normalizeTicker,
} from "../_shared/sec.ts";
import { companyFilings, resolveCik } from "../_shared/sec_data.ts";
import type { EarningsItem } from "./contract.ts";

export const earningsConfig = {
  /// Tope de símbolos que se miran por brief (cartera + watchlist).
  maxSymbols: 15,
  /// Cuánto se espera a la SEC en total: lo que no llega, no sale.
  budgetMs: 8_000,
  /// Ventana de "estimada": días hábiles siguientes.
  estimatedBusinessDays: 3,
  maxItems: 6,
};

const dayMs = 86_400_000;
const addDays = (iso: string, n: number) => new Date(Date.parse(`${iso}T12:00:00Z`) + n * dayMs).toISOString().slice(0, 10);
const isBusiness = (iso: string) => {
  const dow = new Date(`${iso}T12:00:00Z`).getUTCDay();
  return dow >= 1 && dow <= 5;
};

/// El día hábil anterior a [day]: el último cierre que cuenta el brief.
export function previousBusinessDay(day: string): string {
  let d = addDays(day, -1);
  while (!isBusiness(d)) d = addDays(d, -1);
  return d;
}

/// [n] días hábiles después de [day].
export function addBusinessDays(day: string, n: number): string {
  let d = day;
  for (let left = n; left > 0;) {
    d = addDays(d, 1);
    if (isBusiness(d)) left--;
  }
  return d;
}

/// Lo que dicen las presentaciones de UN emisor local para el día [day]
/// (puro; los tests lo prueban sin red).
export function earningsOf(symbol: string, filings: Filing[], day: string): EarningsItem | null {
  const releases = earningsReleases(filings);
  const since = previousBusinessDay(day);
  // `earningsReleases` viene del más nuevo al más viejo.
  const reported = releases.find((f) => f.filed >= since && f.filed <= day);
  if (reported) return { ticker: symbol, kind: "reported", date: reported.filed, url: reported.url };
  // `estimateNextReport` devuelve fechas > su "hoy": se le pasa el día anterior
  // para que "hoy" también cuente.
  const next = estimateNextReport(releases.map((f) => f.filed), addDays(day, -1));
  if (next && next.date >= day && next.date <= addBusinessDays(day, earningsConfig.estimatedBusinessDays)) {
    return { ticker: symbol, kind: "estimated", date: next.date, url: null };
  }
  return null;
}

type SecDeps = Pick<Deps, "db" | "fetch" | "env" | "now" | "background">;

/// Resultados de [symbols] para el brief de [day]. Nunca lanza: lo que la SEC
/// no responde a tiempo se omite. Los confirmados van primero.
export async function earningsFor(deps: SecDeps, symbols: string[], day: string): Promise<EarningsItem[]> {
  const deadline = deps.now() + earningsConfig.budgetMs;
  const out: EarningsItem[] = [];
  for (const symbol of [...new Set(symbols)].slice(0, earningsConfig.maxSymbols)) {
    if (deps.now() > deadline) break;
    try {
      const row = await resolveCik(deps, normalizeTicker(symbol));
      if (!row) continue;
      const { value } = await companyFilings(deps, row.cik);
      if (value.company.filer !== "domestic") continue;
      const item = earningsOf(symbol, value.filings, day);
      if (item) out.push(item);
    } catch (e) {
      console.error("[daily-brief] earnings", symbol, String(e));
    }
  }
  return out
    .sort((a, b) => Number(b.kind === "reported") - Number(a.kind === "reported") || a.date.localeCompare(b.date) ||
      a.ticker.localeCompare(b.ticker))
    .slice(0, earningsConfig.maxItems);
}
