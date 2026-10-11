// SEC EDGAR (data.sec.gov / www.sec.gov / efts.sec.gov): presentaciones,
// resultados y fundamentals. Datos públicos del gobierno de EE.UU., sin key.
//
// Fair access de la SEC: identificarse con `User-Agent: Porty <email>`
// (secret SEC_USER_AGENT, el mismo de investor-pulse) y no pasar de 10
// pedidos por segundo. El limitador de acá deja cada instancia muy por
// debajo (≈5/s); la caché compartida hace que casi nada llegue a la SEC.
//
// Las funciones puras (parse*, extract*, estimate*) no tocan la red: los
// tests las prueban con respuestas guardadas.

import type { Deps } from "./common.ts";
import { sleep } from "./common.ts";

export const secConfig = {
  tickerMapUrl: "https://www.sec.gov/files/company_tickers.json",
  /// Mínimo entre pedidos de una instancia: 200 ms ≈ 5 pedidos/s.
  minIntervalMs: 200,
  timeoutMs: 10_000,
  /// Tokens (≈4 caracteres) del comunicado de resultados que se devuelven.
  pressReleaseTokens: 2_500,
};

export const submissionsUrl = (cik: string) => `https://data.sec.gov/submissions/CIK${cik}.json`;
export const companyFactsUrl = (cik: string) => `https://data.sec.gov/api/xbrl/companyfacts/CIK${cik}.json`;
export const archiveDir = (cik: string, accession: string) =>
  `https://www.sec.gov/Archives/edgar/data/${Number(cik)}/${accession.replace(/-/g, "")}`;
export const filingIndexUrl = (cik: string, accession: string) =>
  `${archiveDir(cik, accession)}/${accession}-index.htm`;
export const companyPageUrl = (cik: string) =>
  `https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=${cik}`;

// ---------------------------------------------------------------------------
// Red
// ---------------------------------------------------------------------------

export class SecUnavailable extends Error {}

let nextSlot = 0;

/// Pedido a la SEC con el User-Agent de contacto, respetando el limitador de
/// la instancia. 404 → null (no existe); otros errores → SecUnavailable.
export async function secFetch(
  deps: Pick<Deps, "fetch" | "env" | "now">,
  url: string,
): Promise<Response | null> {
  const userAgent = deps.env("SEC_USER_AGENT");
  if (!userAgent) throw new SecUnavailable("SEC_USER_AGENT not set");
  const now = Date.now();
  const wait = Math.max(0, nextSlot - now);
  nextSlot = Math.max(now, nextSlot) + secConfig.minIntervalMs;
  if (wait > 0) await sleep(wait);

  let res: Response;
  try {
    res = await deps.fetch(url, {
      headers: { "User-Agent": userAgent, "Accept-Encoding": "gzip, deflate" },
      signal: AbortSignal.timeout(secConfig.timeoutMs),
    });
  } catch (e) {
    throw new SecUnavailable(`fetch failed: ${e}`);
  }
  if (res.status === 404) {
    await res.body?.cancel();
    return null;
  }
  if (res.status !== 200) {
    await res.body?.cancel();
    throw new SecUnavailable(`http ${res.status}`);
  }
  return res;
}

// ---------------------------------------------------------------------------
// Ticker → CIK
// ---------------------------------------------------------------------------

export type TickerRow = { ticker: string; cik: string; title: string };

/// `company_tickers.json` → filas. Un ticker con clases (BRK-B) llega con
/// guion; la app lo manda con punto (BRK.B): se guardan las dos formas.
export function parseTickerMap(json: unknown): TickerRow[] {
  const out = new Map<string, TickerRow>();
  for (const v of Object.values((json ?? {}) as Record<string, unknown>)) {
    const e = v as { cik_str?: number; ticker?: string; title?: string };
    if (typeof e?.ticker !== "string" || typeof e.cik_str !== "number") continue;
    const ticker = e.ticker.toUpperCase();
    const row = { ticker, cik: String(e.cik_str).padStart(10, "0"), title: e.title ?? ticker };
    // El primero gana: la SEC lista primero la clase principal.
    if (!out.has(ticker)) out.set(ticker, row);
    const dotted = ticker.replace(/-/g, ".");
    if (dotted !== ticker && !out.has(dotted)) out.set(dotted, { ...row, ticker: dotted });
  }
  return [...out.values()];
}

export const normalizeTicker = (t: string) => t.trim().toUpperCase().replace(/-/g, ".");

// ---------------------------------------------------------------------------
// Presentaciones (submissions)
// ---------------------------------------------------------------------------

export type Filing = {
  form: string;
  filed: string;
  report_date: string | null;
  items: string[];
  accession: string;
  primary_document: string;
  url: string;
  index_url: string;
};

export type CompanyInfo = {
  cik: string;
  name: string;
  industry: string | null;
  fiscal_year_end: string | null;
  /// domestic = 10-K/10-Q (trimestres en XBRL); foreign = 20-F/6-K/40-F.
  filer: "domestic" | "foreign";
};

/// Las formas que le importan a un inversor minorista.
export const relevantForms = new Set([
  "8-K", "8-K/A", "10-Q", "10-K", "10-K/A", "6-K", "20-F", "20-F/A", "40-F",
]);

/// Ítems del 8-K que se muestran (2.02 resultados, 7.01 Reg FD, 8.01 otros
/// hechos relevantes, más los grandes: 1.01 acuerdos, 2.01 adquisiciones,
/// 5.02 directivos).
export const relevantItems = new Set(["1.01", "2.01", "2.02", "5.02", "7.01", "8.01"]);

export const itemLabels: Record<string, string> = {
  "1.01": "Acuerdo relevante",
  "2.01": "Compra o venta de activos",
  "2.02": "Resultados",
  "5.02": "Cambio de directivos",
  "7.01": "Comunicación al mercado",
  "8.01": "Otros hechos relevantes",
};

// deno-lint-ignore no-explicit-any
export function parseCompany(json: any, cik: string): CompanyInfo {
  const forms: string[] = json?.filings?.recent?.form ?? [];
  const domestic = forms.some((f) => f === "10-K" || f === "10-Q");
  return {
    cik,
    name: String(json?.name ?? ""),
    industry: json?.sicDescription ? String(json.sicDescription) : null,
    fiscal_year_end: json?.fiscalYearEnd ? String(json.fiscalYearEnd) : null,
    filer: domestic ? "domestic" : "foreign",
  };
}

/// Las presentaciones más recientes primero, solo las formas relevantes.
// deno-lint-ignore no-explicit-any
export function parseFilings(json: any, cik: string, limit = 60): Filing[] {
  const r = json?.filings?.recent;
  if (!r || !Array.isArray(r.form)) return [];
  const out: Filing[] = [];
  for (let i = 0; i < r.form.length && out.length < limit; i++) {
    const form = String(r.form[i]);
    if (!relevantForms.has(form)) continue;
    const accession = String(r.accessionNumber?.[i] ?? "");
    const doc = String(r.primaryDocument?.[i] ?? "").replace(/^xsl[^/]*\//, "");
    const items = String(r.items?.[i] ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    out.push({
      form,
      filed: String(r.filingDate?.[i] ?? ""),
      report_date: r.reportDate?.[i] ? String(r.reportDate[i]) : null,
      items,
      accession,
      primary_document: doc,
      url: `${archiveDir(cik, accession)}/${doc}`,
      index_url: filingIndexUrl(cik, accession),
    });
  }
  return out;
}

/// Lo que se muestra: 10-Q/10-K/20-F/40-F siempre; 8-K solo con algún ítem
/// relevante; 6-K todos (no traen ítems).
export function isNotable(f: Filing): boolean {
  if (f.form.startsWith("8-K")) return f.items.some((i) => relevantItems.has(i));
  return true;
}

/// Comunicados de resultados de un emisor local (8-K con ítem 2.02), el más
/// reciente primero.
export const earningsReleases = (filings: Filing[]) =>
  filings.filter((f) => f.form.startsWith("8-K") && f.items.includes("2.02"));

// ---------------------------------------------------------------------------
// Índice de una presentación y texto del exhibit
// ---------------------------------------------------------------------------

export type IndexDocument = { seq: string; description: string; name: string; type: string; url: string };

/// Tabla de documentos de `…-index.htm`.
export function parseFilingIndex(html: string): IndexDocument[] {
  const start = html.indexOf("tableFile");
  if (start < 0) return [];
  const table = html.slice(start, html.indexOf("</table>", start));
  const out: IndexDocument[] = [];
  for (const row of table.match(/<tr[^>]*>[\s\S]*?<\/tr>/g) ?? []) {
    const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((m) => m[1]);
    if (cells.length < 4) continue;
    const href = row.match(/href="([^"]+)"/)?.[1];
    if (!href) continue;
    const path = href.replace(/^\/ix\?doc=/, "");
    out.push({
      seq: stripTags(cells[0]),
      description: stripTags(cells[1]),
      name: stripTags(cells[2]).replace(/\s*iXBRL$/, ""),
      type: stripTags(cells[3]),
      url: path.startsWith("http") ? path : `https://www.sec.gov${path}`,
    });
  }
  return out;
}

/// El comunicado de prensa: EX-99.1 (o el primer EX-99.x en HTML o texto).
export function pressReleaseDocument(docs: IndexDocument[]): IndexDocument | null {
  const isText = (d: IndexDocument) => /\.(htm|html|txt)$/i.test(d.name);
  return docs.find((d) => d.type.toUpperCase() === "EX-99.1" && isText(d)) ??
    docs.find((d) => d.type.toUpperCase().startsWith("EX-99") && isText(d)) ??
    null;
}

const entities: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", rsquo: "’", lsquo: "‘",
  rdquo: "”", ldquo: "“", mdash: "—", ndash: "–", hellip: "…", bull: "•", reg: "®", trade: "™",
};

function decodeEntities(s: string): string {
  return s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, n) => entities[n.toLowerCase()] ?? m);
}

function stripTags(s: string): string {
  return decodeEntities(s.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
}

/// HTML de EDGAR → texto plano legible (sin estilos, scripts ni XBRL oculto),
/// con un salto por bloque.
export function htmlToText(html: string): string {
  const body = html
    .replace(/<(script|style|head)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<ix:header[\s\S]*?<\/ix:header>/gi, " ")
    .replace(/<div[^>]*display:\s*none[\s\S]*?<\/div>/gi, " ")
    .replace(/<\/(p|div|tr|li|h\d|table)>|<br\s*\/?>/gi, "\n")
    .replace(/<\/t[dh]>/gi, " | ")
    .replace(/<[^>]+>/g, " ");
  return decodeEntities(body)
    .split("\n")
    .map((line) => line.replace(/[ \t ]+/g, " ").replace(/(\s*\|\s*)+$/, "").replace(/^(\s*\|\s*)+/, "").trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

/// Saca el encabezado SGML de EDGAR que precede al documento ("EX-99.1",
/// número de secuencia, nombre de archivo, descripción).
export function stripEdgarHeader(text: string): string {
  const lines = text.split("\n");
  let i = 0;
  while (
    i < Math.min(lines.length, 6) &&
    (/^(EX-\d|EXHIBIT \d|\d+$|FORM \d|\d+-K$)/i.test(lines[i]) || /\.(htm|html|txt)$/i.test(lines[i]))
  ) i++;
  return lines.slice(i).join("\n");
}

/// Recorta a ~[maxTokens] tokens (≈4 caracteres por token), en un fin de línea.
export function truncateTokens(text: string, maxTokens: number): { text: string; truncated: boolean } {
  const maxChars = maxTokens * 4;
  if (text.length <= maxChars) return { text, truncated: false };
  const cut = text.lastIndexOf("\n", maxChars);
  return { text: text.slice(0, cut > maxChars * 0.6 ? cut : maxChars).trimEnd(), truncated: true };
}

// ---------------------------------------------------------------------------
// Búsqueda full-text (emisores extranjeros: el 6-K de resultados)
// ---------------------------------------------------------------------------

export function eftsResultsUrl(cik: string, from: string, to: string): string {
  const params = new URLSearchParams({
    q: '"quarter" "results"',
    forms: "6-K",
    ciks: cik,
    startdt: from,
    enddt: to,
  });
  return `https://efts.sec.gov/LATEST/search-index?${params}`;
}

export type EftsHit = { accession: string; file: string; filed: string; type: string };

/// Exhibits 99.x de 6-K que hablan de resultados trimestrales, el más
/// reciente primero.
// deno-lint-ignore no-explicit-any
export function parseEftsHits(json: any): EftsHit[] {
  const hits = json?.hits?.hits;
  if (!Array.isArray(hits)) return [];
  const out: EftsHit[] = [];
  for (const h of hits) {
    const [accession, file] = String(h?._id ?? "").split(":");
    const type = String(h?._source?.file_type ?? "");
    const filed = String(h?._source?.file_date ?? "");
    if (!accession || !file || !/^EX-99/i.test(type) || !/\.(htm|html|txt)$/i.test(file)) continue;
    out.push({ accession, file, filed, type });
  }
  return out.sort((a, b) => b.filed.localeCompare(a.filed) || a.type.localeCompare(b.type));
}

// ---------------------------------------------------------------------------
// Fundamentals (companyfacts XBRL)
// ---------------------------------------------------------------------------

type Fact = {
  start?: string;
  end: string;
  val: number;
  fy?: number;
  fp?: string;
  form?: string;
  filed: string;
  accn?: string;
};

type Series = { concept: string; unit: string; facts: Fact[] };

/// Conceptos candidatos por métrica, en orden de preferencia, para us-gaap
/// (emisores de EE.UU.) e ifrs-full (extranjeros que presentan en IFRS).
const concepts = {
  revenue: {
    "us-gaap": [
      "Revenues",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "RevenueFromContractWithCustomerIncludingAssessedTax",
      "SalesRevenueNet",
    ],
    "ifrs-full": ["Revenue", "RevenueFromContractsWithCustomers"],
  },
  net_income: {
    "us-gaap": ["NetIncomeLoss", "NetIncomeLossAvailableToCommonStockholdersBasic", "ProfitLoss"],
    "ifrs-full": ["ProfitLossAttributableToOwnersOfParent", "ProfitLoss"],
  },
  eps_diluted: {
    "us-gaap": ["EarningsPerShareDiluted", "EarningsPerShareBasicAndDiluted", "EarningsPerShareBasic"],
    "ifrs-full": ["DilutedEarningsLossPerShare", "BasicAndDilutedEarningsLossPerShare", "BasicEarningsLossPerShare"],
  },
  operating_income: {
    "us-gaap": ["OperatingIncomeLoss"],
    "ifrs-full": ["ProfitLossFromOperatingActivities"],
  },
  gross_profit: { "us-gaap": ["GrossProfit"], "ifrs-full": ["GrossProfit"] },
  d_and_a: {
    "us-gaap": ["DepreciationDepletionAndAmortization", "DepreciationAndAmortization", "DepreciationAmortizationAndAccretionNet"],
    "ifrs-full": ["DepreciationAndAmortisationExpense"],
  },
  dividends_per_share: {
    "us-gaap": ["CommonStockDividendsPerShareDeclared", "CommonStockDividendsPerShareCashPaid"],
    "ifrs-full": ["DividendsRecognisedAsDistributionsToOwnersPerShare"],
  },
  equity: {
    "us-gaap": ["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"],
    "ifrs-full": ["EquityAttributableToOwnersOfParent", "Equity"],
  },
  assets: { "us-gaap": ["Assets"], "ifrs-full": ["Assets"] },
  long_term_debt: {
    "us-gaap": ["LongTermDebt", "LongTermDebtNoncurrent", "LongTermDebtAndCapitalLeaseObligations"],
    "ifrs-full": ["Borrowings", "LongtermBorrowings", "NoncurrentPortionOfNoncurrentBorrowings"],
  },
  cash: {
    "us-gaap": [
      "CashAndCashEquivalentsAtCarryingValue",
      "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents",
    ],
    "ifrs-full": ["CashAndCashEquivalents"],
  },
} as const;

type Metric = keyof typeof concepts;

/// Solo informes periódicos auditados/revisados. Los 6-K/8-K con XBRL
/// (algunos extranjeros, como GGAL) traen períodos con rótulos que no
/// cierran y duplican trimestres.
const periodicForms = /^(10-K|10-Q|20-F|40-F)(\/A)?$/;
const perShare = new Set<Metric>(["eps_diluted", "dividends_per_share"]);
const instant = new Set<Metric>(["equity", "assets", "long_term_debt", "cash"]);

const days = (a: string, b: string) => (Date.parse(b) - Date.parse(a)) / 86_400_000;

/// Unidad de una serie: la moneda del emisor ([currency]); si no la tiene,
/// la primera moneda que haya. Nunca "pure" (KO publicó EPS sin unidad).
function pickUnit(units: Record<string, Fact[]>, metric: Metric, currency: string): string | null {
  // Solo la moneda del emisor: mezclar (EPS en ARS con ingresos en USD)
  // da ratios sin sentido. Sin dato en esa moneda, la métrica queda vacía.
  const want = perShare.has(metric) ? `${currency}/shares` : currency;
  return units[want]?.length ? want : null;
}

/// La serie de una métrica: entre los conceptos candidatos, el que tiene el
/// dato más reciente (YPF dejó de usar `Revenue` en 2021, por ejemplo).
// deno-lint-ignore no-explicit-any
function seriesFor(facts: any, metric: Metric, currency: string): Series | null {
  let best: Series | null = null;
  let bestEnd = "";
  for (const [taxonomy, names] of Object.entries(concepts[metric])) {
    for (const name of names) {
      const units = facts?.facts?.[taxonomy]?.[name]?.units as Record<string, Fact[]> | undefined;
      if (!units) continue;
      const unit = pickUnit(units, metric, currency);
      if (!unit) continue;
      const list = units[unit].filter((f) =>
        typeof f.val === "number" && f.end && f.filed && periodicForms.test(f.form ?? "")
      );
      const end = list.reduce((m, f) => (f.end > m ? f.end : m), "");
      if (end > bestEnd) {
        best = { concept: `${taxonomy}:${name}`, unit, facts: list };
        bestEnd = end;
      }
    }
  }
  return best;
}

/// Moneda en que presenta el emisor: la de sus ingresos con más datos en
/// los últimos 3 años (BABA → CNY aunque también publique algunos en USD).
// deno-lint-ignore no-explicit-any
export function reportingCurrency(facts: any): string {
  const counts = new Map<string, number>();
  // Ingresos; un banco que no publica "Revenue" (GGAL) cae al resultado neto.
  const candidates = { ...concepts.revenue } as Record<string, readonly string[]>;
  for (const [tax, names] of Object.entries(concepts.net_income)) {
    candidates[tax] = [...(candidates[tax] ?? []), ...names];
  }
  for (const [taxonomy, names] of Object.entries(candidates)) {
    for (const name of names) {
      const units = facts?.facts?.[taxonomy]?.[name]?.units as Record<string, Fact[]> | undefined;
      for (const [unit, list] of Object.entries(units ?? {})) {
        if (!/^[A-Z]{3}$/.test(unit)) continue;
        const latest = list.reduce((m, f) => (f.end > m ? f.end : m), "");
        const recent = list.filter((f) => days(f.end, latest) < 3 * 366).length;
        counts.set(unit, (counts.get(unit) ?? 0) + recent);
      }
    }
  }
  let best = "USD";
  let bestCount = -1;
  for (const [unit, n] of counts) {
    if (n > bestCount || (n === bestCount && unit === "USD")) {
      best = unit;
      bestCount = n;
    }
  }
  return best;
}

type Period = { start: string | null; end: string; val: number; fy: number | null; fp: string | null };

/// Un valor por período: el de la presentación más nueva (incluye
/// reexpresiones); el rótulo fiscal, de la original (la primera que lo
/// informó: en las comparativas de años siguientes `fy` es el de ese año).
function byPeriod(facts: Fact[]): Map<string, Period> {
  const out = new Map<string, Period & { filed: string; firstFiled: string }>();
  for (const f of facts) {
    const key = `${f.start ?? ""}|${f.end}`;
    const prev = out.get(key);
    if (!prev) {
      out.set(key, { start: f.start ?? null, end: f.end, val: f.val, fy: f.fy ?? null, fp: f.fp ?? null, filed: f.filed, firstFiled: f.filed });
      continue;
    }
    if (f.filed > prev.filed) {
      prev.val = f.val;
      prev.filed = f.filed;
    }
    if (f.filed < prev.firstFiled) {
      prev.firstFiled = f.filed;
      prev.fy = f.fy ?? prev.fy;
      prev.fp = f.fp ?? prev.fp;
    }
  }
  return out;
}

export type QuarterPoint = { start: string; end: string; fiscal_year: number | null; fiscal_quarter: number | null; val: number; derived: boolean };
export type YearPoint = { start: string; end: string; fiscal_year: number | null; val: number };

/// Trimestres (≈90 días) más el Q4 calculado como año − (Q1+Q2+Q3), que el
/// 10-K no publica por separado. Más viejo primero.
function quartersOf(periods: Map<string, Period>): QuarterPoint[] {
  const quarters: QuarterPoint[] = [];
  const years: Period[] = [];
  for (const p of periods.values()) {
    if (!p.start) continue;
    const d = days(p.start, p.end);
    if (d >= 80 && d <= 100) {
      const q = p.fp && /^Q[1-4]$/.test(p.fp) ? Number(p.fp[1]) : null;
      quarters.push({ start: p.start, end: p.end, fiscal_year: p.fy, fiscal_quarter: q, val: p.val, derived: false });
    } else if (d >= 350 && d <= 380) {
      years.push(p);
    }
  }
  for (const y of years) {
    const inside = quarters.filter((q) => !q.derived && q.start >= y.start! && q.end <= y.end);
    if (inside.length !== 3) continue;
    const lastEnd = inside.reduce((m, q) => (q.end > m ? q.end : m), "");
    if (quarters.some((q) => q.end === y.end)) continue;
    const start = new Date(Date.parse(lastEnd) + 86_400_000).toISOString().slice(0, 10);
    quarters.push({
      start,
      end: y.end,
      fiscal_year: y.fy,
      fiscal_quarter: 4,
      val: y.val - inside.reduce((s, q) => s + q.val, 0),
      derived: true,
    });
  }
  return quarters.sort((a, b) => a.end.localeCompare(b.end));
}

function yearsOf(periods: Map<string, Period>): YearPoint[] {
  const out: YearPoint[] = [];
  for (const p of periods.values()) {
    if (!p.start) continue;
    const d = days(p.start, p.end);
    if (d >= 350 && d <= 380) out.push({ start: p.start, end: p.end, fiscal_year: p.fy, val: p.val });
  }
  return out.sort((a, b) => a.end.localeCompare(b.end));
}

function latestInstant(periods: Map<string, Period>): { end: string; val: number } | null {
  let best: { end: string; val: number } | null = null;
  for (const p of periods.values()) {
    if (p.start) continue;
    if (!best || p.end > best.end) best = { end: p.end, val: p.val };
  }
  return best;
}

export type FundamentalsQuarter = {
  label: string;
  fiscal_year: number | null;
  fiscal_quarter: number | null;
  end: string;
  revenue: number | null;
  net_income: number | null;
  eps_diluted: number | null;
  /// Contra el mismo trimestre del año anterior.
  revenue_yoy_pct: number | null;
  eps_yoy_pct: number | null;
  /// Q4 calculado (año − tres trimestres): el EPS es aproximado.
  derived?: true;
};

export type FundamentalsYear = {
  fiscal_year: number | null;
  end: string;
  revenue: number | null;
  net_income: number | null;
  eps_diluted: number | null;
};

export type Fundamentals = {
  currency: string;
  /// "4q" = suma de los últimos 4 trimestres; "annual" = último año fiscal
  /// (emisores extranjeros, que no publican trimestres en XBRL).
  ttm_basis: "4q" | "annual" | null;
  ttm_end: string | null;
  revenue_ttm: number | null;
  net_income_ttm: number | null;
  eps_diluted_ttm: number | null;
  operating_income_ttm: number | null;
  gross_profit_ttm: number | null;
  ebitda_ttm: number | null;
  dividends_per_share_ttm: number | null;
  gross_margin_pct: number | null;
  operating_margin_pct: number | null;
  net_margin_pct: number | null;
  revenue_growth_yoy_pct: number | null;
  eps_growth_yoy_pct: number | null;
  balance_as_of: string | null;
  equity: number | null;
  assets: number | null;
  long_term_debt: number | null;
  cash: number | null;
  roe_pct: number | null;
  roa_pct: number | null;
  shares_outstanding: number | null;
  shares_as_of: string | null;
  quarters: FundamentalsQuarter[];
  years: FundamentalsYear[];
};

const round = (v: number | null, digits = 2) =>
  v === null || !Number.isFinite(v) ? null : Number(v.toFixed(digits));
const pct = (num: number | null, den: number | null) =>
  num === null || den === null || den === 0 ? null : round((num / den) * 100, 1);
const growth = (now: number | null, before: number | null) =>
  now === null || before === null || before <= 0 ? null : round(((now - before) / before) * 100, 1);

export function fiscalLabel(fy: number | null, fq: number | null): string {
  if (fy === null) return "";
  const yy = String(fy).slice(-2);
  return fq ? `T${fq} FY${yy}` : `FY${yy}`;
}

/// Acciones en circulación (portada del último 10-Q/10-K/20-F). Con varias
/// clases, la portada trae un dato por clase en la misma fecha: se suman.
// deno-lint-ignore no-explicit-any
function sharesOutstanding(facts: any): { val: number; end: string } | null {
  const list = (facts?.facts?.dei?.EntityCommonStockSharesOutstanding?.units?.shares ?? []) as Fact[];
  if (list.length === 0) return null;
  const latestFiled = list.reduce((m, f) => (f.filed > m ? f.filed : m), "");
  const sameFiling = list.filter((f) => f.filed === latestFiled);
  const end = sameFiling.reduce((m, f) => (f.end > m ? f.end : m), "");
  const val = sameFiling.filter((f) => f.end === end).reduce((s, f) => s + f.val, 0);
  return val > 0 ? { val, end } : null;
}

// deno-lint-ignore no-explicit-any
export function extractFundamentals(facts: any): Fundamentals {
  const currency = reportingCurrency(facts);
  const metrics = Object.keys(concepts) as Metric[];
  const periods = new Map<Metric, Map<string, Period>>();
  for (const m of metrics) {
    const s = seriesFor(facts, m, currency);
    periods.set(m, s ? byPeriod(s.facts) : new Map());
  }
  const quarters = new Map<Metric, QuarterPoint[]>();
  const years = new Map<Metric, YearPoint[]>();
  for (const m of metrics) {
    if (instant.has(m)) continue;
    quarters.set(m, quartersOf(periods.get(m)!));
    years.set(m, yearsOf(periods.get(m)!));
  }

  // Trimestres de referencia: los de los ingresos (o el resultado neto).
  const spine = (quarters.get("revenue")!.length ? quarters.get("revenue") : quarters.get("net_income"))!;
  const valueAt = (m: Metric, end: string) => quarters.get(m)!.find((q) => q.end === end)?.val ?? null;
  const yearAt = (m: Metric, end: string) => years.get(m)!.find((y) => y.end === end)?.val ?? null;

  const lastQuarters = spine.slice(-8);
  const consecutive = (list: QuarterPoint[]) =>
    list.length === 4 && list.every((q, i) => i === 0 || days(list[i - 1].end, q.end) < 100);
  const recent4 = lastQuarters.slice(-4);
  const prior4 = lastQuarters.length >= 8 ? lastQuarters.slice(0, 4) : [];

  const sumOver = (m: Metric, list: QuarterPoint[]) => {
    if (!consecutive(list)) return null;
    const vals = list.map((q) => valueAt(m, q.end));
    return vals.every((v) => v !== null) ? (vals as number[]).reduce((s, v) => s + v, 0) : null;
  };

  // Último año fiscal (de los ingresos) para los emisores sin trimestres.
  const yearSpine = (years.get("revenue")!.length ? years.get("revenue") : years.get("net_income"))!;
  const lastYear = yearSpine.at(-1) ?? null;
  const prevYear = yearSpine.at(-2) ?? null;
  const quarterly = consecutive(recent4) &&
    (!lastYear || recent4[3].end >= lastYear.end);

  const ttm = (m: Metric) => quarterly ? sumOver(m, recent4) : lastYear ? yearAt(m, lastYear.end) : null;
  const prevTtm = (m: Metric) => quarterly ? sumOver(m, prior4) : prevYear ? yearAt(m, prevYear.end) : null;

  const revenue = ttm("revenue");
  const netIncome = ttm("net_income");
  const operating = ttm("operating_income");
  const gross = ttm("gross_profit");
  const dna = ttm("d_and_a");
  const eps = ttm("eps_diluted");

  const instantOf = (m: Metric) => latestInstant(periods.get(m)!);
  const equity = instantOf("equity");
  const assets = instantOf("assets");
  const debt = instantOf("long_term_debt");
  const cash = instantOf("cash");
  const balanceAsOf = [equity, assets, cash].map((x) => x?.end ?? "").reduce((m, e) => (e > m ? e : m), "");
  // Un dato de balance viejo (KO dejó de usar LongTermDebt) no se mezcla.
  const fresh = (x: { end: string; val: number } | null) =>
    x && balanceAsOf && days(x.end, balanceAsOf) < 200 ? x.val : null;
  const shares = sharesOutstanding(facts);

  const ttmEnd = quarterly ? recent4[3].end : lastYear?.end ?? null;
  return {
    currency,
    ttm_basis: quarterly ? "4q" : lastYear ? "annual" : null,
    ttm_end: ttmEnd,
    revenue_ttm: revenue,
    net_income_ttm: netIncome,
    eps_diluted_ttm: round(eps),
    operating_income_ttm: operating,
    gross_profit_ttm: gross,
    ebitda_ttm: operating !== null && dna !== null ? operating + dna : null,
    dividends_per_share_ttm: round(ttm("dividends_per_share"), 4),
    gross_margin_pct: pct(gross, revenue),
    operating_margin_pct: pct(operating, revenue),
    net_margin_pct: pct(netIncome, revenue),
    revenue_growth_yoy_pct: growth(revenue, prevTtm("revenue")),
    eps_growth_yoy_pct: growth(eps, prevTtm("eps_diluted")),
    balance_as_of: balanceAsOf || null,
    equity: fresh(equity),
    assets: fresh(assets),
    long_term_debt: fresh(debt),
    cash: fresh(cash),
    roe_pct: equity && equity.val > 0 ? pct(netIncome, fresh(equity)) : null,
    roa_pct: pct(netIncome, fresh(assets)),
    shares_outstanding: shares?.val ?? null,
    shares_as_of: shares?.end ?? null,
    quarters: spine.slice(-4).map((q) => {
      const yearAgo = spine.find((p) => Math.abs(days(p.end, q.end) - 364) <= 20);
      const epsNow = valueAt("eps_diluted", q.end);
      return {
        label: fiscalLabel(q.fiscal_year, q.fiscal_quarter),
        fiscal_year: q.fiscal_year,
        fiscal_quarter: q.fiscal_quarter,
        end: q.end,
        revenue: valueAt("revenue", q.end),
        net_income: valueAt("net_income", q.end),
        eps_diluted: round(epsNow),
        revenue_yoy_pct: yearAgo ? growth(valueAt("revenue", q.end), valueAt("revenue", yearAgo.end)) : null,
        eps_yoy_pct: yearAgo ? growth(epsNow, valueAt("eps_diluted", yearAgo.end)) : null,
        ...(q.derived ? { derived: true as const } : {}),
      };
    }),
    years: yearSpine.slice(-3).map((y) => ({
      fiscal_year: y.fiscal_year,
      end: y.end,
      revenue: yearAt("revenue", y.end),
      net_income: yearAt("net_income", y.end),
      eps_diluted: round(yearAt("eps_diluted", y.end)),
    })),
  };
}

// ---------------------------------------------------------------------------
// Próximo reporte (estimado: EDGAR no publica un calendario)
// ---------------------------------------------------------------------------

export type NextReportEstimate = {
  date: string;
  /// same_quarter_last_year = un año después del reporte equivalente (las
  /// empresas repiten su calendario); last_report_plus_quarter = último
  /// reporte + 91 días.
  basis: "same_quarter_last_year" | "last_report_plus_quarter";
};

const addDaysIso = (iso: string, n: number) =>
  new Date(Date.parse(`${iso}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

/// [reportDates]: fechas de los comunicados de resultados ya presentados.
/// Toma el primer "mismo reporte un año después" (364 días: mismo día de la
/// semana) que todavía no pasó y cae después del último reporte; si no hay,
/// último + 91 días.
export function estimateNextReport(reportDates: string[], today: string): NextReportEstimate | null {
  const sorted = [...new Set(reportDates)].filter(Boolean).sort();
  if (sorted.length === 0) return null;
  const last = sorted.at(-1)!;
  // Sin reportes en más de un año: no hay calendario que repetir.
  if (days(last, today) > 400) return null;
  const candidates = sorted
    .map((d) => addDaysIso(d, 364))
    .filter((d) => d > today && days(last, d) > 45 && days(last, d) <= 120)
    .sort();
  if (candidates.length > 0) return { date: candidates[0], basis: "same_quarter_last_year" };
  let next = addDaysIso(last, 91);
  while (next <= today) next = addDaysIso(next, 91);
  return { date: next, basis: "last_report_plus_quarter" };
}
