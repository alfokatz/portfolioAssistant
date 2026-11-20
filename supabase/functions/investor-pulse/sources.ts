// Fuentes de "qué dicen los super investors" y su parseo. Funciones puras:
// reciben texto o JSON ya bajado, así los tests no tocan la red.
//
// - Noticias: Google News RSS con el rango de la semana (after/before), un
//   pedido por inversor con sus términos unidos por OR. Solo hay titular,
//   medio y fecha: la app parafrasea, nunca cita.
// - Presentaciones a la SEC (data.sec.gov, públicas): Form 4 (compras y
//   ventas), Schedule 13D/G (pasó el 5% de una empresa) y 13F-HR (la
//   cartera del trimestre).

export type Investor = {
  id: string;
  display_name: string;
  organization: string | null;
  kind: "investor" | "market_voice";
  search_terms: string[];
  ciks: string[];
  sort: number;
};

export type Week = {
  /// Lunes y viernes `YYYY-MM-DD`.
  monday: string;
  friday: string;
  /// Sábado: fin exclusivo (lo que espera `before:` de Google).
  saturday: string;
};

type ItemBase = {
  id: string;
  investor_id: string;
  investor_name: string;
  organization: string | null;
  voice: Investor["kind"];
  /// `YYYY-MM-DD`.
  date: string;
  url: string;
};

export type NewsItem = ItemBase & {
  type: "news";
  headline: string;
  source: string;
};

export type FilingAction =
  | "buy"
  | "sell"
  | "stake"
  | "stake_update"
  | "quarterly_portfolio";

export type FilingItem = ItemBase & {
  type: "filing";
  form: string;
  action: FilingAction;
  issuer_name: string | null;
  issuer_ticker: string | null;
  /// Acciones compradas o vendidas en la semana (solo Form 4).
  shares: number | null;
  /// Período del 13F (`YYYY-MM-DD`, fin de trimestre).
  period: string | null;
};

export type PulseItem = NewsItem | FilingItem;

// ---------------------------------------------------------------------------
// Semana
// ---------------------------------------------------------------------------

/// `null` si [monday] no es un lunes `YYYY-MM-DD` válido.
export function weekOf(monday: string): Week | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(monday)) return null;
  const d = new Date(`${monday}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.getUTCDay() !== 1) return null;
  if (d.toISOString().slice(0, 10) !== monday) return null; // 2026-02-30
  const plus = (n: number) =>
    new Date(d.getTime() + n * 86_400_000).toISOString().slice(0, 10);
  return { monday, friday: plus(4), saturday: plus(5) };
}

// ---------------------------------------------------------------------------
// Noticias (Google News RSS)
// ---------------------------------------------------------------------------

export function googleNewsUrl(investor: Investor, week: Week): string {
  const terms = investor.search_terms.map((t) => `"${t}"`).join(" OR ");
  const q = `${investor.search_terms.length > 1 ? `(${terms})` : terms} ` +
    `after:${week.monday} before:${week.saturday}`;
  const params = new URLSearchParams({
    q,
    hl: "en-US",
    gl: "US",
    ceid: "US:en",
  });
  return `https://news.google.com/rss/search?${params}`;
}

export type RawHeadline = {
  headline: string;
  source: string;
  url: string;
  published: Date;
};

/// Items del RSS en el orden de Google (relevancia). Descarta los que no
/// tienen título, link https o fecha.
export function parseGoogleRss(xml: string): RawHeadline[] {
  const out: RawHeadline[] = [];
  for (const block of xml.match(/<item>[\s\S]*?<\/item>/g) ?? []) {
    const title = decode(tag(block, "title"));
    const link = decode(tag(block, "link"));
    const pub = tag(block, "pubDate");
    const source = decode(tag(block, "source"));
    if (!title || !link.startsWith("https://") || !pub) continue;
    const published = new Date(pub);
    if (Number.isNaN(published.getTime())) continue;
    const suffix = ` - ${source}`;
    out.push({
      headline: source && title.endsWith(suffix)
        ? title.slice(0, -suffix.length).trim()
        : title,
      source,
      url: link,
      published,
    });
  }
  return out;
}

/// Palabras que hacen que un titular sea sobre mercados y no sobre la vida
/// personal de alguien. Inglés: el feed es de la edición US.
const marketWords =
  /\b(stocks?|shares?|markets?|funds?|invest\w*|stakes?|bets?|buy\w*|bought|sell\w*|sold|portfolio|positions?|holdings?|economy|economic|recession|inflation|rates?|fed|federal reserve|bubble|bonds?|treasur\w*|yields?|crypto|bitcoin|letter|memo|warns?|warning|bull\w*|bear\w*|rally|crash\w*|valuations?|earnings|s&p|nasdaq|dow|tariffs?|dollar|gold|ai|short\w*)\b/i;

const maxNewsPerInvestor = 3;
const maxPerSource = 2;

/// Se queda con los titulares que nombran al inversor (algún término
/// completo), son de mercado y caen en la semana. Un solo titular por hecho
/// (varios medios con la misma nota) y como mucho [maxPerSource] por medio.
export function selectNews(
  raw: RawHeadline[],
  investor: Investor,
  week: Week,
): RawHeadline[] {
  const from = Date.parse(`${week.monday}T00:00:00Z`);
  // Google fecha en UTC; la semana de EEUU termina el viernes a la noche:
  // hasta el sábado 06:00 UTC sigue siendo viernes en Nueva York.
  const to = Date.parse(`${week.saturday}T06:00:00Z`);
  const terms = investor.search_terms.map((t) => t.toLowerCase());
  const picked: RawHeadline[] = [];
  const perSource = new Map<string, number>();
  for (const h of raw) {
    const t = h.published.getTime();
    if (t < from || t >= to) continue;
    const lower = h.headline.toLowerCase();
    if (!terms.some((term) => lower.includes(term))) continue;
    if (!marketWords.test(h.headline)) continue;
    if (picked.some((p) => sameEvent(p.headline, h.headline))) continue;
    const n = perSource.get(h.source) ?? 0;
    if (n >= maxPerSource) continue;
    perSource.set(h.source, n + 1);
    picked.push(h);
    if (picked.length >= maxNewsPerInvestor) break;
  }
  return picked;
}

/// Dos titulares cuentan el mismo hecho si comparten la mayoría de sus
/// palabras con contenido.
export function sameEvent(a: string, b: string): boolean {
  const wa = contentWords(a);
  const wb = contentWords(b);
  if (wa.size === 0 || wb.size === 0) return false;
  let shared = 0;
  for (const w of wa) if (wb.has(w)) shared++;
  return shared / Math.min(wa.size, wb.size) >= 0.6;
}

const stopWords = new Set([
  "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "as",
  "at", "by", "is", "are", "was", "his", "her", "its", "from", "says", "said",
  "after", "over", "into", "than", "that", "this", "new",
]);

function contentWords(s: string): Set<string> {
  return new Set(
    s.toLowerCase().replace(/[^a-z0-9&$ ]/g, " ").split(/\s+/)
      .filter((w) => w.length > 2 && !stopWords.has(w)),
  );
}

// ---------------------------------------------------------------------------
// SEC / EDGAR
// ---------------------------------------------------------------------------

export function submissionsUrl(cik: string): string {
  return `https://data.sec.gov/submissions/CIK${cik.padStart(10, "0")}.json`;
}

export const tickerMapUrl = "https://www.sec.gov/files/company_tickers.json";

export type RecentFiling = {
  cik: string;
  form: string;
  filingDate: string;
  accession: string;
  /// Documento XML crudo (sin el prefijo de la vista `xsl…/`).
  rawDocument: string;
  reportDate: string | null;
};

const form4 = new Set(["4"]);
const schedule13 = new Set([
  "SCHEDULE 13D", "SCHEDULE 13D/A", "SCHEDULE 13G", "SCHEDULE 13G/A",
  "SC 13D", "SC 13D/A", "SC 13G", "SC 13G/A",
]);
const form13f = new Set(["13F-HR"]);

/// Presentaciones de la semana que importan, de un `submissions/CIK….json`.
export function recentFilings(
  // deno-lint-ignore no-explicit-any
  json: any,
  cik: string,
  week: Week,
): RecentFiling[] {
  const r = json?.filings?.recent;
  if (!r || !Array.isArray(r.form)) return [];
  const out: RecentFiling[] = [];
  for (let i = 0; i < r.form.length; i++) {
    const form = String(r.form[i]);
    const date = String(r.filingDate?.[i] ?? "");
    if (date < week.monday || date > week.friday) continue;
    if (!form4.has(form) && !schedule13.has(form) && !form13f.has(form)) {
      continue;
    }
    const doc = String(r.primaryDocument?.[i] ?? "");
    out.push({
      cik: String(Number(cik)),
      form,
      filingDate: date,
      accession: String(r.accessionNumber?.[i] ?? ""),
      rawDocument: doc.replace(/^xsl[^/]*\//, ""),
      reportDate: r.reportDate?.[i] ? String(r.reportDate[i]) : null,
    });
  }
  return out;
}

export function needsDocument(f: RecentFiling): boolean {
  return !form13f.has(f.form);
}

export function documentUrl(f: RecentFiling): string {
  return `https://www.sec.gov/Archives/edgar/data/${f.cik}/` +
    `${f.accession.replace(/-/g, "")}/${f.rawDocument}`;
}

/// Página de la presentación en EDGAR: es lo que abre el usuario.
export function filingIndexUrl(f: RecentFiling): string {
  return `https://www.sec.gov/Archives/edgar/data/${f.cik}/` +
    `${f.accession.replace(/-/g, "")}/${f.accession}-index.htm`;
}

export type Form4 = {
  issuerName: string | null;
  issuerTicker: string | null;
  bought: number;
  sold: number;
};

/// Form 4 donde el inversor es quien opera (no la empresa operada: los
/// Form 4 de los directivos de Berkshire también aparecen en su CIK).
/// Solo compras (P) y ventas (S) de acciones: los otros códigos (premios,
/// regalos, ejercicios) no dicen nada de lo que piensa del mercado.
export function parseForm4(xml: string, investorCik: string): Form4 | null {
  const owners = [...xml.matchAll(/<rptOwnerCik>\s*(\d+)\s*<\/rptOwnerCik>/g)]
    .map((m) => String(Number(m[1])));
  if (!owners.includes(String(Number(investorCik)))) return null;
  let bought = 0;
  let sold = 0;
  for (
    const block of xml.match(
      /<nonDerivativeTransaction>[\s\S]*?<\/nonDerivativeTransaction>/g,
    ) ?? []
  ) {
    const code = tag(block, "transactionCode");
    const shares = Number(valueOf(block, "transactionShares"));
    if (!Number.isFinite(shares)) continue;
    if (code === "P") bought += shares;
    if (code === "S") sold += shares;
  }
  if (bought === 0 && sold === 0) return null;
  return {
    issuerName: tag(xml, "issuerName") || null,
    // Con varias clases viene "LEN, LEN.B": la primera es la principal.
    issuerTicker: (tag(xml, "issuerTradingSymbol") || "")
      .split(/[,;\s]+/)[0]
      .toUpperCase() || null,
    bought,
    sold,
  };
}

/// Emisora de un Schedule 13D/G (formato XML de la SEC desde 2024).
export function parseSchedule13(
  xml: string,
): { issuerName: string | null; issuerCik: string | null } {
  return {
    issuerName: tag(xml, "issuerName") || null,
    issuerCik: (() => {
      const c = tag(xml, "issuerCik");
      return c ? String(Number(c)) : null;
    })(),
  };
}

/// `company_tickers.json` → CIK → ticker (el primero listado: la clase
/// principal).
// deno-lint-ignore no-explicit-any
export function tickerMap(json: any): Map<string, string> {
  const map = new Map<string, string>();
  for (const v of Object.values(json ?? {})) {
    // deno-lint-ignore no-explicit-any
    const row = v as any;
    const cik = String(row?.cik_str ?? "");
    if (cik && row?.ticker && !map.has(cik)) {
      map.set(cik, String(row.ticker).replace(/-/g, ".").toUpperCase());
    }
  }
  return map;
}

// ---------------------------------------------------------------------------
// XML mínimo (los documentos son chicos y de estructura fija)
// ---------------------------------------------------------------------------

/// Contenido del primer `<name>` (con o sin namespace), sin espacios.
function tag(xml: string, name: string): string {
  const m = xml.match(
    new RegExp(`<(?:\\w+:)?${name}(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?${name}>`),
  );
  if (!m) return "";
  return m[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").trim();
}

/// `<name><value>X</value></name>` (estilo de los Form 4).
function valueOf(xml: string, name: string): string {
  const inner = tag(xml, name);
  const v = inner.match(/<value>\s*([^<]*?)\s*<\/value>/);
  return (v ? v[1] : inner).trim();
}

function decode(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'");
}
