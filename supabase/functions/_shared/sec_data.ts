// Datos de la SEC ya cacheados (tabla `data_source_cache`), para la función
// `sec` y los trabajos del servidor (daily-jobs). Cada pieza tiene su TTL:
//   - ticker → CIK: tabla `sec_ticker_cik`, se refresca una vez al día;
//   - presentaciones de una empresa: 1 h;
//   - fundamentals (companyfacts ya extraídos): 24 h;
//   - comunicado de resultados de una presentación: 30 días (no cambia);
//   - búsqueda de 6-K de resultados (emisores extranjeros): 24 h.

import type { Deps } from "./common.ts";
import { cached } from "./data_cache.ts";
import {
  archiveDir,
  type CompanyInfo,
  companyFactsUrl,
  earningsReleases,
  eftsResultsUrl,
  estimateNextReport,
  extractFundamentals,
  type Filing,
  type Fundamentals,
  htmlToText,
  stripEdgarHeader,
  type NextReportEstimate,
  normalizeTicker,
  parseCompany,
  parseEftsHits,
  parseFilingIndex,
  parseFilings,
  parseTickerMap,
  pressReleaseDocument,
  secConfig,
  secFetch,
  SecUnavailable,
  submissionsUrl,
  type TickerRow,
  truncateTokens,
} from "./sec.ts";

export const secTtl = {
  tickerMapHours: 24,
  filingsSeconds: 60 * 60,
  factsSeconds: 24 * 60 * 60,
  documentSeconds: 30 * 24 * 60 * 60,
  foreignResultsSeconds: 24 * 60 * 60,
};

type SecDeps = Pick<Deps, "db" | "fetch" | "env" | "now" | "background">;

async function refreshTickerMap(deps: SecDeps): Promise<void> {
  const res = await secFetch(deps, secConfig.tickerMapUrl);
  if (!res) throw new SecUnavailable("ticker map missing");
  const rows = parseTickerMap(await res.json());
  const refreshed_at = new Date(deps.now()).toISOString();
  for (let i = 0; i < rows.length; i += 2000) {
    const chunk = rows.slice(i, i + 2000).map((r) => ({ ...r, refreshed_at }));
    const { error } = await deps.db.from("sec_ticker_cik").upsert(chunk);
    if (error) throw new SecUnavailable(`sec_ticker_cik upsert: ${error.message}`);
  }
  console.log(JSON.stringify({ fn: "sec", event: "ticker_map_refreshed", rows: rows.length }));
}

/// CIK de [ticker]; null si no presenta ante la SEC. Si la tabla está vacía
/// o vieja y el ticker no aparece, la refresca antes de decir que no.
export async function resolveCik(deps: SecDeps, ticker: string): Promise<TickerRow | null> {
  const symbol = normalizeTicker(ticker);
  const lookup = async () => {
    const { data } = await deps.db
      .from("sec_ticker_cik")
      .select("ticker, cik, title, refreshed_at")
      .eq("ticker", symbol)
      .maybeSingle();
    return data as (TickerRow & { refreshed_at: string }) | null;
  };
  const staleBefore = deps.now() - secTtl.tickerMapHours * 3600_000;
  const row = await lookup();
  if (row) {
    if (Date.parse(row.refreshed_at) < staleBefore) {
      deps.background(refreshTickerMap(deps).catch((e) => console.error("ticker map refresh", e)));
    }
    return { ticker: row.ticker, cik: row.cik, title: row.title };
  }
  const { data: newest } = await deps.db
    .from("sec_ticker_cik")
    .select("refreshed_at")
    .order("refreshed_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (newest && Date.parse(newest.refreshed_at as string) >= staleBefore) return null;
  await refreshTickerMap(deps);
  const again = await lookup();
  return again ? { ticker: again.ticker, cik: again.cik, title: again.title } : null;
}

export type CompanyFilings = { company: CompanyInfo; filings: Filing[] };

export async function companyFilings(deps: SecDeps, cik: string) {
  return await cached<CompanyFilings>(deps, `sec:filings:${cik}`, secTtl.filingsSeconds, async () => {
    const res = await secFetch(deps, submissionsUrl(cik));
    if (!res) throw new SecUnavailable("submissions missing");
    const json = await res.json();
    return { company: parseCompany(json, cik), filings: parseFilings(json, cik) };
  });
}

/// `null` = la empresa no publica XBRL (p. ej. algunos fondos).
export async function companyFundamentals(deps: SecDeps, cik: string) {
  return await cached<Fundamentals | null>(deps, `sec:facts:${cik}`, secTtl.factsSeconds, async () => {
    const res = await secFetch(deps, companyFactsUrl(cik));
    return res ? extractFundamentals(await res.json()) : null;
  });
}

export type PressRelease = {
  form: string;
  filed: string;
  url: string;
  index_url: string;
  text: string;
  truncated: boolean;
};

/// Texto del comunicado (EX-99.1) de una presentación, ya limpio y recortado.
async function releaseText(deps: SecDeps, documentUrl: string): Promise<{ text: string; truncated: boolean } | null> {
  const doc = await secFetch(deps, documentUrl);
  if (!doc) return null;
  const text = stripEdgarHeader(htmlToText(await doc.text()));
  return text ? truncateTokens(text, secConfig.pressReleaseTokens) : null;
}

/// El comunicado de resultados de un 8-K 2.02 (busca el EX-99.1 en el índice).
export async function pressReleaseOf(deps: SecDeps, cik: string, filing: Filing) {
  return await cached<PressRelease | null>(
    deps,
    `sec:release:${filing.accession}`,
    secTtl.documentSeconds,
    async () => {
      const index = await secFetch(deps, filing.index_url);
      if (!index) return null;
      const doc = pressReleaseDocument(parseFilingIndex(await index.text()));
      const url = doc?.url ?? `${archiveDir(cik, filing.accession)}/${filing.primary_document}`;
      const body = await releaseText(deps, url);
      return body ? { form: filing.form, filed: filing.filed, url, index_url: filing.index_url, ...body } : null;
    },
  );
}

export type ForeignResults = { release: PressRelease | null; release_dates: string[] };

/// Emisores extranjeros: los 6-K no traen ítems, así que el comunicado de
/// resultados se busca por texto (full-text search de EDGAR) en los últimos
/// ~15 meses. Las fechas sirven también para estimar el próximo reporte.
export async function foreignResults(deps: SecDeps, cik: string) {
  return await cached<ForeignResults>(
    deps,
    `sec:foreign-results:${cik}`,
    secTtl.foreignResultsSeconds,
    async () => {
      const today = new Date(deps.now()).toISOString().slice(0, 10);
      const from = new Date(deps.now() - 460 * 86_400_000).toISOString().slice(0, 10);
      const res = await secFetch(deps, eftsResultsUrl(cik, from, today));
      const hits = res ? parseEftsHits(await res.json()) : [];
      // Una fecha por presentación, aunque traiga varios exhibits.
      const dates = [...new Set(hits.map((h) => h.filed))];
      const latest = hits[0];
      if (!latest) return { release: null, release_dates: [] };
      const url = `${archiveDir(cik, latest.accession)}/${latest.file}`;
      const body = await releaseText(deps, url);
      return {
        release: body
          ? {
            form: "6-K",
            filed: latest.filed,
            url,
            index_url: `${archiveDir(cik, latest.accession)}/${latest.accession}-index.htm`,
            ...body,
          }
          : null,
        release_dates: dates,
      };
    },
  );
}

/// Fechas de los comunicados de resultados (8-K 2.02 o 6-K de resultados) y
/// la estimación del próximo, para el calendario.
export function nextReportFrom(
  company: CompanyInfo,
  filings: Filing[],
  foreignDates: string[],
  today: string,
): NextReportEstimate | null {
  const dates = company.filer === "domestic" ? earningsReleases(filings).map((f) => f.filed) : foreignDates;
  return estimateNextReport(dates, today);
}

/// Comunicados de resultados (8-K con ítem 2.02) presentados desde [since]
/// por [symbols], para la push "salió el resultado" (daily-jobs, v2). Solo
/// emisores locales: los 6-K de extranjeros no traen ítems. Cada empresa se
/// consulta como mucho una vez por hora (caché compartida); [maxSymbols]
/// acota el pedido a la SEC por corrida.
export async function secEarningsReleases(
  deps: SecDeps,
  symbols: string[],
  since: string,
  maxSymbols = 150,
): Promise<{ symbol: string; date: string; hour: null; epsActual: null; epsEstimate: null; reported: true }[]> {
  const out: { symbol: string; date: string; hour: null; epsActual: null; epsEstimate: null; reported: true }[] = [];
  for (const symbol of symbols.slice(0, maxSymbols)) {
    try {
      const row = await resolveCik(deps, symbol);
      if (!row) continue;
      const { value } = await companyFilings(deps, row.cik);
      if (value.company.filer !== "domestic") continue;
      for (const f of earningsReleases(value.filings)) {
        if (f.filed < since) break;
        out.push({ symbol, date: f.filed, hour: null, epsActual: null, epsEstimate: null, reported: true });
      }
    } catch (e) {
      console.error("[sec] releases", symbol, e);
    }
  }
  return out;
}
